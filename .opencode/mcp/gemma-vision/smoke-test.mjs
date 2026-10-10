import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const imagePath = process.argv[2] ?? resolve(here, "../../../style_guide/liquidglass-main/site/banner.jpg");
const prompt = process.argv[3] ?? "Describe this image in one short paragraph.";
const think = process.argv[4] === "think";

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [resolve(here, "index.mjs")],
});

const client = new Client({ name: "gemma-vision-smoke-test", version: "1.0.0" });
await client.connect(transport);

const tools = await client.listTools();
console.log("tools:", tools.tools.map((t) => t.name).join(", "));

const started = Date.now();
const result = await client.callTool({
  name: "analyze_image",
  arguments: { image_path: imagePath, prompt, think },
});
console.log(`call took ${((Date.now() - started) / 1000).toFixed(1)}s`);
console.log("isError:", result.isError === true);
console.log("---");
for (const block of result.content) {
  if (block.type === "text") console.log(block.text);
}

await client.close();
