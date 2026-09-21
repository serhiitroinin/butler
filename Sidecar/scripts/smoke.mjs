/**
 * Drives the sidecar over stdio with the offline engine and a stub tool host.
 * The real tools live in Swift; this script only proves the protocol path.
 */
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { mkdtempSync, readdirSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const sidecarDir = resolve(here, "..");
const root = resolve(process.argv[2] ?? resolve(sidecarDir, "../.demo/Downloads"));
const store = mkdtempSync(join(tmpdir(), "butler-smoke-store-"));
const dataDir = mkdtempSync(join(tmpdir(), "butler-smoke-data-"));

const child = spawn(join(sidecarDir, "node_modules/.bin/fold-harness-sidecar"), [
  "--host", join(sidecarDir, "host.mjs"),
  "--store", store,
], { env: { ...process.env, BUTLER_OFFLINE: "1", BUTLER_DATA_DIR: dataDir }, stdio: ["pipe", "pipe", "inherit"] });

let nextId = 0;
const pending = new Map();
const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
const request = (method, params) => new Promise((resolveRequest, rejectRequest) => {
  const id = (nextId += 1);
  pending.set(id, { resolveRequest, rejectRequest });
  send({ jsonrpc: "2.0", id, method, params });
});

let proposal = null;
let settled = null;

function listFolder(path) {
  const base = path === "." ? root : join(root, path);
  const entries = readdirSync(base, { withFileTypes: true })
    .filter((entry) => !entry.name.startsWith("."))
    .map((entry) => {
      const stats = statSync(join(base, entry.name));
      const name = entry.name;
      const dot = name.lastIndexOf(".");
      return {
        name,
        path: path === "." ? name : `${path}/${name}`,
        kind: entry.isDirectory() ? "folder" : "file",
        ...(dot > 0 ? { ext: name.slice(dot + 1) } : {}),
        size: stats.size,
        created: stats.birthtime.toISOString(),
        modified: stats.mtime.toISOString(),
        ...(entry.isDirectory()
          ? { itemCount: readdirSync(join(base, entry.name)).filter((n) => !n.startsWith(".")).length }
          : {}),
      };
    });
  return { content: [{ type: "text", text: JSON.stringify({ path, truncated: false, entries }) }] };
}

function callTool(params) {
  if (params.name === "list_folder") return listFolder(params.input.path ?? ".");
  if (params.name === "propose_plan") {
    proposal = params.input;
    return { content: [{ type: "text", text: "The plan is recorded and shown to the user. End your turn now." }] };
  }
  return { content: [{ type: "text", text: `Unknown tool: ${params.name}` }], isError: true };
}

createInterface({ input: child.stdout }).on("line", (line) => {
  const message = JSON.parse(line);
  if (message.method === "host/tool/call") {
    send({ jsonrpc: "2.0", id: message.id, result: callTool(message.params) });
    return;
  }
  if (message.method === "harness/run/settled") {
    settled = message.params.status;
    return;
  }
  if (message.method) return;
  const entry = pending.get(message.id);
  if (!entry) return;
  pending.delete(message.id);
  if (message.error) entry.rejectRequest(new Error(JSON.stringify(message.error)));
  else entry.resolveRequest(message.result);
});

const tools = [
  {
    name: "list_folder",
    description: "List the entries of a folder relative to the managed root.",
    inputSchema: {
      type: "object",
      properties: { path: { type: "string" }, depth: { type: "integer" } },
      required: ["path"],
      additionalProperties: false,
    },
  },
  {
    name: "propose_plan",
    description: "Record the organisation plan and end the turn.",
    inputSchema: {
      type: "object",
      properties: { summary: { type: "string" }, operations: { type: "array" } },
      required: ["summary", "operations"],
      additionalProperties: false,
    },
  },
];

const initialize = await request("harness/initialize", {
  protocolVersion: 1,
  client: { name: "butler-smoke", version: "0.1.0" },
});
console.log("adapters:", initialize.adapters.join(", "));
console.log("models:", JSON.stringify(await request("harness/models", { schemaVersion: 1, adapterId: "kit:offline" })));

const started = await request("harness/run/start", {
  request: {
    schemaVersion: 1,
    session: { tenantId: "local", actorId: "owner", threadId: "smoke" },
    adapterId: "kit:offline",
    input: [{ type: "text", text: "Organise this folder by the rules." }],
  },
  tools,
  context: {
    sources: [{
      sourceId: "butler:rules",
      value: { instructions: "Sort by kind and year.", content: [] },
    }],
    unavailable: [],
  },
});
console.log("run:", started.runId, started.turnId);

const deadline = Date.now() + 20_000;
while (settled === null && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));

await request("harness/shutdown", {});
child.kill();

if (settled !== "completed") throw new Error(`the run settled as ${settled}`);
if (!proposal) throw new Error("no plan was proposed");
console.log(`settled: ${settled}`);
console.log(`summary: ${proposal.summary}`);
console.log(`operations: ${proposal.operations.length}`);
