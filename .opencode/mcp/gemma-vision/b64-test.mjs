import { readFile } from "node:fs/promises";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const b64 = await readFile(resolve(here, "../../../style_guide/liquidglass-main/site/favicon.png"), "base64");

const transport = new StdioClientTransport({ command: process.execPath, args: [resolve(here, "index.mjs")] });
const client = new Client({ name: "b64-test", version: "1.0.0" });
await client.connect(transport);

const dataUrl = `data:image/png;base64,${b64}`;
const res = await client.callTool({
  name: "analyze_image",
  arguments: { image_base64: dataUrl, prompt: "One sentence: what does this show?" },
});
console.log("isError:", res.isError === true);
for (const block of res.content) if (block.type === "text") console.log(block.text);

const both = await client.callTool({
  name: "analyze_image",
  arguments: { image_path: "x.png", image_base64: b64, prompt: "?" },
});
console.log("\nboth-inputs error:", both.content[0]?.text);

const neither = await client.callTool({ name: "analyze_image", arguments: { prompt: "?" } });
console.log("neither-input error:", neither.content[0]?.text);

await client.close();
