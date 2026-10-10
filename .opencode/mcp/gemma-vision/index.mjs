#!/usr/bin/env node
import { readFile, stat } from "node:fs/promises";
import { extname, resolve } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const OLLAMA_HOST = (process.env.OLLAMA_HOST ?? "http://127.0.0.1:11434").replace(/\/+$/, "");
const MODEL = process.env.GEMMA_MODEL ?? "gemma4:26b";
const ALLOWED_EXT = new Set([".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"]);
const MAX_BYTES = 50 * 1024 * 1024;
const THINKING_CAP = 4000;
const DEFAULT_PROMPT =
  "Describe this image in detail: objects, people, text, colors, layout, and anything unusual or notable.";
const GROUNDING_SUFFIX =
  "\n\nThe image is attached to this message. Look at it carefully and answer based only on what is actually visible in it.";
const BLIND_RE =
  /cannot see (?:any|the|an) image|no image (?:was|has been|is) (?:provided|attached|uploaded)|(?:please|kindly) (?:provide|upload|share|attach) the (?:image|icon|picture|photo)|did not (?:load|come through)|unable to view|image (?:did not|didn't) (?:load|appear)|not able to see (?:the|any|your) image/i;

function stripControl(text) {
  return text
    .replace(/<\|channel>thought[\s\S]*?<channel\|>/g, "")
    .replace(/<\|channel>thought/g, "")
    .replace(/<channel\|>/g, "")
    .replace(/<\|think\|>/g, "")
    .replace(/<\|start\|>assistant\s*/g, "")
    .trim();
}

function fail(message) {
  return { content: [{ type: "text", text: `Error: ${message}` }], isError: true };
}

async function loadImage({ image_path, image_base64 }) {
  if (image_path && image_base64) {
    throw new Error("Pass either image_path or image_base64, not both.");
  }
  if (image_path) {
    const path = resolve(image_path);
    const ext = extname(path).toLowerCase();
    if (!ALLOWED_EXT.has(ext)) {
      throw new Error(`Unsupported image type "${ext}". Supported: ${[...ALLOWED_EXT].join(" ")}.`);
    }
    const info = await stat(path).catch(() => null);
    if (!info?.isFile()) throw new Error(`Image file not found: ${path}`);
    if (info.size > MAX_BYTES) {
      throw new Error(`Image is ${Math.round(info.size / 1048576)} MB. Limit is 50 MB so calls stay responsive.`);
    }
    return { base64: await readFile(path, "base64") };
  }
  if (image_base64) {
    const base64 = image_base64.replace(/^data:image\/[a-z+.-]+;base64,/i, "");
    if (base64.length < 64) throw new Error("image_base64 is too short to be a real image.");
    return { base64 };
  }
  throw new Error("Provide image_path (preferred) or image_base64.");
}

async function askOllama(base64, prompt, think, temperature) {
  const body = {
    model: MODEL,
    messages: [{ role: "user", content: prompt, images: [base64] }],
    stream: false,
    think,
    options: { temperature, top_p: 0.95, top_k: 64 },
    keep_alive: "10m",
  };
  let res;
  try {
    res = await fetch(`${OLLAMA_HOST}/api/chat`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch (e) {
    const reason = e.cause?.code ?? e.message;
    throw new Error(`Cannot reach Ollama at ${OLLAMA_HOST} (${reason}). Start it with: ollama serve`);
  }
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    if (res.status === 404 && /not found/i.test(detail)) {
      throw new Error(`Model "${MODEL}" is not installed locally. Run: ollama pull ${MODEL}`);
    }
    throw new Error(`Ollama returned HTTP ${res.status}: ${detail.slice(0, 300)}`);
  }
  return res.json();
}

const server = new McpServer({ name: "gemma-vision", version: "1.0.0" });

server.registerTool(
  "analyze_image",
  {
    title: "Analyze image with local Gemma 4 vision",
    description: `Runs ${MODEL} on the local Ollama instance to analyze an image and return text. Nothing leaves the machine. Give it an image file path (png jpg jpeg webp gif bmp) or base64 bytes, plus an optional question such as "describe this", "read all text in this", "what is broken in this UI", or "count the objects". Set think=true for harder tasks like dense text, charts, counting, or spatial reasoning; it is slower but more thorough.`,
    inputSchema: {
      image_path: z
        .string()
        .optional()
        .describe("Path to the image on disk. Absolute, or relative to the current working directory. Use this or image_base64."),
      image_base64: z
        .string()
        .optional()
        .describe("Base64-encoded image bytes; a data:image/...;base64, prefix is accepted. Use this or image_path."),
      prompt: z
        .string()
        .optional()
        .describe("Question or instruction for the model. Omit for a detailed general description."),
      think: z
        .boolean()
        .optional()
        .describe("Enable Gemma 4 thinking mode. Slower, better on dense text, charts, counting, and spatial reasoning."),
    },
  },
  async ({ image_path, image_base64, prompt: question, think }) => {
    const thinkingOn = think === true;
    try {
      const { base64 } = await loadImage({ image_path, image_base64 });
      const prompt = question?.trim() || DEFAULT_PROMPT;

      let data = await askOllama(base64, prompt, thinkingOn, 1.0);
      let answer = stripControl(data.message?.content ?? "");
      if (BLIND_RE.test(answer)) {
        data = await askOllama(base64, prompt + GROUNDING_SUFFIX, thinkingOn, 0.7);
        answer = stripControl(data.message?.content ?? "");
        if (BLIND_RE.test(answer)) {
          return fail(
            `The model could not process the image (it reports seeing no image). The image file itself is valid. ` +
              `This is a known weakness of some local vision models; try again, use a different image, or set GEMMA_MODEL to another multimodal model (e.g. another gemma4 variant installed via: ollama pull).`,
          );
        }
      }

      const rawThinking = thinkingOn ? stripControl(data.message?.thinking ?? "") : "";
      if (!answer && !rawThinking) {
        return fail(`The model returned an empty response (done_reason: ${data.done_reason ?? "unknown"}). Try rephrasing the prompt.`);
      }

      const secs = data.total_duration ? (data.total_duration / 1e9).toFixed(1) : "?";
      const tokPerSec =
        data.eval_duration && data.eval_count ? (data.eval_count / (data.eval_duration / 1e9)).toFixed(1) : null;

      const parts = [answer];
      if (rawThinking) {
        const trimmed =
          rawThinking.length > THINKING_CAP ? `${rawThinking.slice(0, THINKING_CAP)}\n[thinking truncated]` : rawThinking;
        parts.push(`--- model thinking ---\n${trimmed}`);
      }
      parts.push(
        `gemma-vision | ${MODEL} | ${secs}s${tokPerSec ? ` | ${tokPerSec} tok/s` : ""} | ${
          data.eval_count ?? "?"
        } out tokens | thinking ${thinkingOn ? "on" : "off"}`,
      );

      return { content: [{ type: "text", text: parts.join("\n\n") }] };
    } catch (e) {
      return fail(e.message ?? String(e));
    }
  },
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(`gemma-vision MCP server ready (model=${MODEL}, ollama=${OLLAMA_HOST})`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
