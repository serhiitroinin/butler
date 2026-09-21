import { mkdirSync } from "node:fs";
import { join } from "node:path";
import type { HarnessSidecarHostDefinition } from "@serhiitroinin/fold-harness/sidecar-host";
import { createEngines } from "./engines.js";
import { createOfflineEngine } from "./offline.js";
import { SYSTEM_PROMPT } from "./prompt.js";

function requiredDirectory(name: string): string {
  const value = process.env[name];
  if (!value || !value.startsWith("/")) {
    throw new Error(`${name} must be an absolute path`);
  }
  mkdirSync(value, { recursive: true, mode: 0o700 });
  return value;
}

export default function createHarnessSidecarHost(): HarnessSidecarHostDefinition {
  const dataDir = requiredDirectory("BUTLER_DATA_DIR");
  const workspace = join(dataDir, "engine-workspace");
  const engines = createEngines({
    appName: "Butler",
    appVersion: "0.1.0",
    workspace,
    dataDir,
    systemPrompt: SYSTEM_PROMPT,
    onStderr: (engine, text) => process.stderr.write(`[${engine}] ${text}`),
  });
  const adapters = process.env.BUTLER_OFFLINE === "1"
    ? [createOfflineEngine(), ...engines]
    : engines;
  return { server: { name: "butler-sidecar", version: "0.1.0" }, adapters };
}
