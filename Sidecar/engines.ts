import { execFileSync } from "node:child_process";
import {
  copyFileSync, lstatSync, mkdirSync, renameSync, rmSync, statSync, symlinkSync, writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  CODEX_SERVICE_TIER_CONTROL_ID,
  createClaudeAgentSdkAdapter,
  createClaudeAgentSdkConnector,
  createCodexAppServerAdapter,
  createCodexAppServerProcessConnector,
  type CodexAppServerConnectRequest,
  type HarnessAdapter,
  type HarnessDiscovery,
  type HarnessEngineProfile,
} from "@serhiitroinin/fold-harness";
import { createClaudeAgentSdkDiscovery, createCodexAppServerDiscovery } from "./discovery.js";

export const CLAUDE_ENGINE = "kit:claude";
export const CODEX_ENGINE = "kit:codex";

export interface EngineKitOptions {
  appName: string;
  appVersion: string;
  /** An empty private directory. The agent gets no shell, so nothing reads it. */
  workspace: string;
  /** Private application data. The Codex session home lives here. */
  dataDir: string;
  systemPrompt: string;
  onStderr?(engine: string, text: string): void;
}

const ENV_ALLOWLIST = [
  "PATH", "USER", "TMPDIR", "LANG", "LC_ALL", "TERM",
  "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS",
];

function exactEnvironment(): Record<string, string> {
  return Object.fromEntries(ENV_ALLOWLIST.flatMap((name) => {
    const value = process.env[name];
    return value === undefined ? [] : [[name, value]];
  }));
}

const imageInput = {
  modalities: { text: { support: "stable" as const }, image: { support: "stable" as const } },
};

function profile(id: string, label: string, codex: boolean): HarnessDiscovery<HarnessEngineProfile> {
  return {
    status: "available",
    value: {
      id,
      label,
      modelSelection: "optional",
      permissions: {
        kind: codex ? "approval-policy" : "permission-mode",
        selectable: false,
        defaultModeId: "app-tools-only",
        modes: [{ id: "app-tools-only", label: "Application tools only", posture: "restricted" }],
      },
      inputPolicy: imageInput,
      ...(codex ? {
        controls: [{
          id: CODEX_SERVICE_TIER_CONTROL_ID,
          label: "Speed",
          kind: "select" as const,
          scope: "turn" as const,
          options: [{ id: "default", label: "Standard" }, { id: "priority", label: "Fast" }],
          defaultValue: "default",
        }],
      } : {}),
    },
  };
}

/**
 * Codex refreshes a token by renaming a new file over `auth.json`. A copied
 * credential would then diverge from `~/.codex` and one side loses its login.
 * A symlink keeps one credential; a regular file found here is a refresh that
 * replaced the link, so the newer one is published back before relinking.
 */
function linkCodexAuth(privateHome: string, accountHome: string): void {
  const link = join(privateHome, "auth.json");
  const target = join(accountHome, "auth.json");
  const found = lstatSync(link, { throwIfNoEntry: false });
  if (found?.isFile()) {
    const current = statSync(target, { throwIfNoEntry: false });
    if (!current || found.mtimeMs > current.mtimeMs) {
      const staged = join(accountHome, `.kit-auth-${process.pid}`);
      copyFileSync(link, staged);
      renameSync(staged, target);
    }
  } else if (found && !found.isSymbolicLink()) {
    throw new Error("The Codex session home holds an auth.json this application did not write.");
  }
  rmSync(link, { force: true });
  symlinkSync(target, link);
}

function codexHome(dataDir: string): string {
  const accountHome = process.env.CODEX_HOME ?? join(homedir(), ".codex");
  const privateHome = join(dataDir, "codex-home");
  mkdirSync(privateHome, { recursive: true, mode: 0o700 });
  linkCodexAuth(privateHome, accountHome);
  // App Server loads a config.toml in full, including mcp_servers. Own the file.
  rmSync(join(privateHome, "config.toml"), { force: true });
  writeFileSync(join(privateHome, "config.toml"), "# Written by the application.\n", { mode: 0o600 });
  return privateHome;
}

const CODEX_ARGS = [
  "app-server", "--stdio", "--strict-config",
  "--disable", "shell_tool", "--disable", "unified_exec", "--disable", "shell_snapshot",
  "-c", "skills.include_instructions=false",
  "-c", "skills.bundled.enabled=false",
  "-c", "cli_auth_credentials_store=\"file\"",
];

function codexCommand(): string {
  return execFileSync("which", ["codex"], { encoding: "utf8" }).trim();
}

function codexEnvironment(dataDir: string): Record<string, string> {
  const home = codexHome(dataDir);
  return { ...exactEnvironment(), HOME: home, CODEX_HOME: home, NO_COLOR: "1" };
}

/**
 * The application asks for limits again when its engine menu opens and after
 * every run, so a snapshot is only reused for a short while.
 */
const LIMITS_TTL_MS = 20_000;

const TOOL_OUTPUT_LIMIT = 4000;
const APPLICATION_TOOLS = new Set(["list_folder", "inspect_file", "propose_plan"]);

/**
 * Both adapters drop tool output by default, so a refused tool would reach the
 * user with no reason. Keep the application's own tool text, bounded, and drop
 * everything else. The text holds file names, so it is never logged.
 */
function keepApplicationToolOutput(name: string, output: string): string {
  return APPLICATION_TOOLS.has(name) ? output.slice(0, TOOL_OUTPUT_LIMIT) : "";
}

export function createEngines(options: EngineKitOptions): HarnessAdapter[] {
  mkdirSync(options.workspace, { recursive: true, mode: 0o700 });
  const toolPrefix = "mcp__fold-harness__";

  // Models, effort levels and plan limits come from the signed-in account: one
  // short-lived probe with no tools and no turn, cached by the discovery.
  const claudeEnvironment = () => ({ ...exactEnvironment(), HOME: homedir(), NO_COLOR: "1" });
  const claudeDiscovery = createClaudeAgentSdkDiscovery({
    limitsTtlMs: LIMITS_TTL_MS,
    onStderr: (chunk) => options.onStderr?.(CLAUDE_ENGINE, chunk),
    configure: () => ({ cwd: options.workspace, env: claudeEnvironment() }),
  });
  const claude = createClaudeAgentSdkAdapter({
    id: CLAUDE_ENGINE,
    profile: profile(CLAUDE_ENGINE, "Claude Code", false),
    models: claudeDiscovery.models,
    limits: claudeDiscovery.limits,
    events: {
      redactToolOutput: (tool, output) => keepApplicationToolOutput(
        tool.name.startsWith(toolPrefix) ? tool.name.slice(toolPrefix.length) : tool.name,
        output,
      ),
    },
    authorizeTool: (request) => request.toolName.startsWith(toolPrefix)
      ? { behavior: "allow", updatedInput: request.input }
      : { behavior: "deny", message: "Only application tools are available." },
    connect: createClaudeAgentSdkConnector({
      onStderr: (chunk) => options.onStderr?.(CLAUDE_ENGINE, chunk),
      configure: () => ({
        cwd: options.workspace,
        env: claudeEnvironment(),
        tools: [],
        skills: [],
        settingSources: [],
        strictMcpConfig: true,
        permissionMode: "default",
        systemPrompt: options.systemPrompt,
        persistSession: true,
      }),
    }),
  });

  const clientInfo = { name: options.appName, title: options.appName, version: options.appVersion };
  const codexProcess = () => createCodexAppServerProcessConnector({
    command: codexCommand(),
    args: CODEX_ARGS,
    cwd: options.workspace,
    env: codexEnvironment(options.dataDir),
    onStderr: (chunk) => options.onStderr?.(CODEX_ENGINE, new TextDecoder().decode(chunk)),
  });
  const codexDiscovery = createCodexAppServerDiscovery({
    clientInfo,
    limitsTtlMs: LIMITS_TTL_MS,
    connect: (request) => codexProcess()(request as CodexAppServerConnectRequest),
  });
  const codex = createCodexAppServerAdapter({
    id: CODEX_ENGINE,
    clientInfo,
    profile: profile(CODEX_ENGINE, "Codex", true),
    events: {
      redactToolOutput: (tool, output) => keepApplicationToolOutput(
        "name" in tool ? tool.name : "",
        output,
      ),
    },
    models: codexDiscovery.models,
    limits: codexDiscovery.limits,
    thread: (request) => ({
      cwd: options.workspace,
      sandbox: "read-only",
      approvalPolicy: "never",
      ...(request.model ? { model: request.model } : {}),
    }),
    connect: (request) => codexProcess()(request),
  });

  return [claude, codex];
}
