/**
 * Live model and limit discovery for both engines.
 *
 * This file mirrors the discovery API of the next fold-harness release (the
 * same module as in the sibling application Easel). When that release is
 * installed, import the same names from the package and delete this file and
 * the direct Agent SDK dependency.
 */

import { query, type Options, type SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import {
  codexInitializeParams,
  codexLimitSnapshot,
  codexModelCatalog,
  createCodexAppServerClient,
  createPushableAsyncIterable,
  type CodexAppServerClientInfo,
  type CodexAppServerConnection,
  type CodexInitializeOptions,
  type HarnessDiscovery,
  type HarnessDiscoveryRequest,
  type HarnessLimit,
  type HarnessLimitSnapshot,
  type HarnessModel,
  type HarnessModelCatalog,
} from "@serhiitroinin/fold-harness";

const CLAUDE_AGENT_SDK_NAMESPACE = "anthropic:claude-agent-sdk";

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function finite(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : undefined;
}

const LIMIT_LABELS: Readonly<Record<string, string>> = {
  five_hour: "5-hour",
  seven_day: "Weekly",
  seven_day_opus: "Weekly · Opus",
  seven_day_sonnet: "Weekly · Sonnet",
  seven_day_oauth_apps: "Weekly · Apps",
  seven_day_overage_included: "Weekly · Overage",
  overage: "Overage",
};

const EFFORT_LABELS: Readonly<Record<string, string>> = {
  low: "Low",
  medium: "Medium",
  high: "High",
  xhigh: "Extra high",
  max: "Max",
};

function title(value: string): string {
  return value
    .split(/[-_]/g)
    .filter(Boolean)
    .map((part) => part[0]!.toUpperCase() + part.slice(1))
    .join(" ");
}

function windowDuration(id: string): number | undefined {
  if (id === "five_hour") return 300 * 60_000;
  return id.startsWith("seven_day") ? 10_080 * 60_000 : undefined;
}

function rateLimit(id: string, usedPercent: number, resetsAt?: string, label?: string): HarnessLimit {
  const windowDurationMs = windowDuration(id);
  return {
    id,
    label: label ?? LIMIT_LABELS[id] ?? title(id),
    kind: "rate",
    scope: "account",
    unit: "%",
    usedPercent: Math.round(usedPercent),
    ...(resetsAt ? { resetsAt } : {}),
    ...(windowDurationMs !== undefined ? { windowDurationMs } : {}),
  };
}

function isoFromText(value: unknown): string | undefined {
  const parsed = Date.parse(text(value));
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : undefined;
}

const USAGE_WINDOWS = [
  "five_hour",
  "seven_day",
  "seven_day_opus",
  "seven_day_sonnet",
  "seven_day_oauth_apps",
] as const;

/**
 * Convert the Agent SDK usage response, which reports whole percentages.
 * Returns null when plan limits do not apply, for example with an API key.
 */
export function claudeAgentSdkUsageLimitSnapshot(value: unknown): HarnessLimitSnapshot | null {
  const usage = record(value);
  const windows = record(usage?.rate_limits);
  if (usage === null || windows === null || usage.rate_limits_available === false) return null;
  const limits: HarnessLimit[] = [];
  for (const id of USAGE_WINDOWS) {
    const window = record(windows[id]);
    const usedPercent = finite(window?.utilization);
    if (window === null || usedPercent === undefined) continue;
    limits.push(rateLimit(id, usedPercent, isoFromText(window.resets_at)));
  }
  for (const entry of Array.isArray(windows.model_scoped) ? windows.model_scoped : []) {
    const window = record(entry);
    const name = text(window?.display_name);
    const usedPercent = finite(window?.utilization);
    if (window === null || name === "" || usedPercent === undefined) continue;
    const id = `seven_day_model:${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`;
    limits.push({
      ...rateLimit(id, usedPercent, isoFromText(window.resets_at), `Weekly · ${name}`),
      scope: "model",
    });
  }
  const plan = text(usage.subscription_type);
  return { ...(plan ? { planLabel: title(plan) } : {}), limits };
}

/** Convert an Agent SDK `supportedModels()` response into the neutral catalog. */
export function claudeAgentSdkModelCatalog(value: unknown): HarnessModelCatalog {
  const models: HarnessModel[] = [];
  for (const entry of Array.isArray(value) ? value : []) {
    const row = record(entry);
    const id = text(row?.value);
    if (row === null || id === "" || models.some((model) => model.id === id)) continue;
    const efforts = row.supportsEffort === false || !Array.isArray(row.supportedEffortLevels)
      ? []
      : row.supportedEffortLevels.filter((level): level is string => typeof level === "string" && level !== "");
    const details = {
      ...(text(row.resolvedModel) ? { resolvedModel: text(row.resolvedModel) } : {}),
      ...(typeof row.supportsAdaptiveThinking === "boolean" ? { adaptiveThinking: row.supportsAdaptiveThinking } : {}),
      ...(typeof row.supportsFastMode === "boolean" ? { fastMode: row.supportsFastMode } : {}),
      ...(typeof row.supportsAutoMode === "boolean" ? { autoMode: row.supportsAutoMode } : {}),
    };
    models.push({
      id,
      label: text(row.displayName) || title(id),
      ...(text(row.description) ? { description: text(row.description) } : {}),
      ...(efforts.length > 0
        ? { effort: { options: efforts.map((level) => ({ id: level, label: EFFORT_LABELS[level] ?? title(level) })) } }
        : {}),
      ...(Object.keys(details).length > 0 ? { extensions: { [CLAUDE_AGENT_SDK_NAMESPACE]: details } } : {}),
    });
  }
  const preferred = models.find((model) => model.id === "default") ?? models[0];
  return {
    models,
    selection: "optional",
    ...(preferred ? { defaultModelId: preferred.id } : {}),
  };
}

export interface ClaudeAgentSdkQueryRequest {
  prompt: AsyncIterable<unknown>;
  options: Readonly<Record<string, unknown>>;
}

export const CLAUDE_AGENT_SDK_DISCOVERY_ERRORS = {
  failed: "CLAUDE_DISCOVERY_FAILED",
  signedOut: "CLAUDE_DISCOVERY_SIGNED_OUT",
} as const;

/** Process placement for a discovery probe. It grants no tools or settings. */
export interface ClaudeAgentSdkDiscoveryConfiguration {
  cwd: string;
  /** Exact subprocess environment. It is never merged with `process.env`. */
  env: Readonly<Record<string, string>>;
  /** Provider launch options such as `pathToClaudeCodeExecutable`. */
  extensions?: Readonly<Record<string, unknown>>;
}

export interface ClaudeAgentSdkDiscoveryQueryLike {
  supportedModels(): Promise<unknown>;
  accountInfo?(): Promise<unknown>;
  /** The Agent SDK marks its usage request experimental. It may be absent. */
  usage?(): Promise<unknown>;
  close(): void;
}

export interface ClaudeAgentSdkDiscoveryOptions {
  configure(
    request: HarnessDiscoveryRequest,
  ): Promise<ClaudeAgentSdkDiscoveryConfiguration> | ClaudeAgentSdkDiscoveryConfiguration;
  /** How long a model catalog is served from cache. Defaults to ten minutes. */
  modelsTtlMs?: number;
  /** How long a limit snapshot is served from cache. Defaults to one minute. */
  limitsTtlMs?: number;
  /** Bound one probe, including process start. Defaults to fifteen seconds. */
  timeoutMs?: number;
  now?: () => Date;
  /** Receives private SDK stderr. */
  onStderr?(chunk: string): void;
  /** Deterministic injection seam. Production callers should omit it. */
  createQuery?(request: ClaudeAgentSdkQueryRequest): ClaudeAgentSdkDiscoveryQueryLike;
}

export interface ClaudeAgentSdkDiscovery {
  models(request: HarnessDiscoveryRequest): Promise<HarnessDiscovery<HarnessModelCatalog>>;
  limits(request: HarnessDiscoveryRequest): Promise<HarnessDiscovery<HarnessLimitSnapshot>>;
}

interface DiscoveryProbe {
  at: number;
  models: HarnessDiscovery<HarnessModelCatalog>;
  limits: HarnessDiscovery<HarnessLimitSnapshot>;
}

function sdkDiscoveryQuery(request: ClaudeAgentSdkQueryRequest): ClaudeAgentSdkDiscoveryQueryLike {
  const sdk = query({
    prompt: request.prompt as AsyncIterable<SDKUserMessage>,
    options: request.options as Options,
  });
  return {
    supportedModels: () => sdk.supportedModels(),
    accountInfo: () => sdk.accountInfo(),
    usage: () => sdk.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET(),
    close: () => sdk.close(),
  };
}

function signedOut(account: unknown): boolean {
  if (typeof account !== "object" || account === null) return false;
  const info = account as Record<string, unknown>;
  const provider = info.apiProvider ?? "firstParty";
  return provider === "firstParty" && info.tokenSource === "none" && !info.apiKeySource;
}

function duration(value: number | undefined, fallback: number, name: string): number {
  const resolved = value ?? fallback;
  if (!Number.isFinite(resolved) || resolved < 0) throw new Error(`${name} must not be negative`);
  return resolved;
}

/**
 * Live model and limit sources for `createClaudeAgentSdkAdapter`.
 *
 * One short-lived SDK process answers control requests and is closed. Its
 * input stream never yields, so no turn starts and no session is persisted.
 */
export function createClaudeAgentSdkDiscovery(
  options: ClaudeAgentSdkDiscoveryOptions,
): ClaudeAgentSdkDiscovery {
  const modelsTtlMs = duration(options.modelsTtlMs, 600_000, "modelsTtlMs");
  const limitsTtlMs = duration(options.limitsTtlMs, 60_000, "limitsTtlMs");
  const timeoutMs = duration(options.timeoutMs, 15_000, "timeoutMs");
  const now = options.now ?? (() => new Date());
  const createQuery = options.createQuery ?? sdkDiscoveryQuery;
  const cache = new Map<string, DiscoveryProbe>();
  const pending = new Map<string, Promise<DiscoveryProbe>>();

  const failure = (code: string, message: string): DiscoveryProbe => {
    const result = { status: "unavailable" as const, message, code, retryable: true };
    return { at: Number.NEGATIVE_INFINITY, models: result, limits: result };
  };

  const probe = async (request: HarnessDiscoveryRequest): Promise<DiscoveryProbe> => {
    const prompt = createPushableAsyncIterable<unknown>();
    const abortController = new AbortController();
    let sdk: ClaudeAgentSdkDiscoveryQueryLike | undefined;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const configured = await options.configure(request);
      sdk = createQuery({
        prompt,
        options: {
          ...(configured.extensions ?? {}),
          abortController,
          cwd: configured.cwd,
          env: { ...configured.env },
          tools: [],
          skills: [],
          settingSources: [],
          strictMcpConfig: true,
          mcpServers: {},
          permissionMode: "default",
          systemPrompt: "",
          persistSession: false,
          stderr: (chunk: string) => options.onStderr?.(chunk),
        },
      });
      const running = sdk;
      const answered = (async () => {
        const models = claudeAgentSdkModelCatalog(await running.supportedModels());
        const account = await running.accountInfo?.().catch(() => undefined);
        const usage = signedOut(account) ? undefined : await running.usage?.().catch(() => undefined);
        return { models, account, usage };
      })();
      const expired = new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("timeout")), timeoutMs);
      });
      answered.catch(() => undefined);
      const { models, account, usage } = await Promise.race([answered, expired]);
      if (signedOut(account)) {
        return failure(CLAUDE_AGENT_SDK_DISCOVERY_ERRORS.signedOut, "Claude Code is not signed in.");
      }
      if (models.models.length === 0) {
        return failure(CLAUDE_AGENT_SDK_DISCOVERY_ERRORS.failed, "Claude Code listed no models.");
      }
      const at = now();
      const limits = claudeAgentSdkUsageLimitSnapshot(usage);
      return {
        at: at.getTime(),
        models: { status: "available", value: models, fetchedAt: at.toISOString() },
        limits: limits
          ? {
              status: "available",
              value: limits,
              fetchedAt: at.toISOString(),
              expiresAt: new Date(at.getTime() + limitsTtlMs).toISOString(),
            }
          : { status: "unsupported", message: "This Claude account reports no plan limits." },
      };
    } catch {
      return failure(
        CLAUDE_AGENT_SDK_DISCOVERY_ERRORS.failed,
        "Claude Code did not answer discovery. Check that it is installed and signed in.",
      );
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      prompt.close();
      abortController.abort();
      try {
        sdk?.close();
      } catch {}
    }
  };

  const resolve = async (request: HarnessDiscoveryRequest, ttlMs: number): Promise<DiscoveryProbe> => {
    const key = request.accountId ?? "";
    const cached = cache.get(key);
    if (cached && now().getTime() - cached.at < ttlMs) return cached;
    let running = pending.get(key);
    if (!running) {
      running = probe(request).then((result) => {
        if (result.models.status === "available") cache.set(key, result);
        else cache.delete(key);
        return result;
      }).finally(() => pending.delete(key));
      pending.set(key, running);
    }
    return running;
  };

  return {
    models: async (request) => (await resolve(request, modelsTtlMs)).models,
    limits: async (request) => (await resolve(request, limitsTtlMs)).limits,
  };
}

function field(value: Record<string, unknown>, camel: string, snake: string): unknown {
  return value[camel] ?? value[snake];
}

/**
 * Convert one `account/rateLimits/read` response. The multi-bucket view is
 * preferred; the single-bucket view fills in any limit it does not name.
 */
export function codexAccountLimitSnapshot(response: unknown): HarnessLimitSnapshot | null {
  const envelope = record(response);
  if (envelope === null) return null;
  const buckets = record(field(envelope, "rateLimitsByLimitId", "rate_limits_by_limit_id")) ?? {};
  const snapshots = [...Object.values(buckets), field(envelope, "rateLimits", "rate_limits")]
    .map(codexLimitSnapshot)
    .filter((snapshot): snapshot is HarnessLimitSnapshot => snapshot !== null);
  if (snapshots.length === 0) return null;
  const limits = new Map<string, HarnessLimit>();
  for (const snapshot of snapshots) {
    for (const limit of snapshot.limits) if (!limits.has(limit.id)) limits.set(limit.id, limit);
  }
  const planLabel = snapshots.find((snapshot) => snapshot.planLabel)?.planLabel;
  return { ...(planLabel ? { planLabel } : {}), limits: [...limits.values()] };
}

export const CODEX_APP_SERVER_DISCOVERY_ERRORS = {
  failed: "CODEX_DISCOVERY_FAILED",
} as const;

export interface CodexAppServerDiscoveryConnectRequest {
  accountId?: string;
  /** Aborts when the probe has its answers or its time is up. */
  signal: AbortSignal;
}

export interface CodexAppServerDiscoveryOptions {
  clientInfo: CodexAppServerClientInfo;
  initialize?: Omit<CodexInitializeOptions, "clientInfo">;
  /** The host creates one short-lived provider connection for a probe. */
  connect(
    request: CodexAppServerDiscoveryConnectRequest,
  ): Promise<CodexAppServerConnection> | CodexAppServerConnection;
  /** How long a model catalog is served from cache. Defaults to ten minutes. */
  modelsTtlMs?: number;
  /** How long a limit snapshot is served from cache. Defaults to one minute. */
  limitsTtlMs?: number;
  /** Bound one probe, including process start. Defaults to fifteen seconds. */
  timeoutMs?: number;
  now?: () => Date;
}

export interface CodexAppServerDiscovery {
  models(request: HarnessDiscoveryRequest): Promise<HarnessDiscovery<HarnessModelCatalog>>;
  limits(request: HarnessDiscoveryRequest): Promise<HarnessDiscovery<HarnessLimitSnapshot>>;
}

interface CodexDiscoveryProbe {
  at: number;
  models: HarnessDiscovery<HarnessModelCatalog>;
  limits: HarnessDiscovery<HarnessLimitSnapshot>;
}

const MODEL_LIST_PAGES = 20;

function discoveryDuration(value: number | undefined, fallback: number, name: string): number {
  const resolved = value ?? fallback;
  if (!Number.isFinite(resolved) || resolved < 0) throw new Error(`${name} must not be negative`);
  return resolved;
}

/**
 * Live model and limit sources for `createCodexAppServerAdapter`.
 *
 * One short-lived App Server connection answers `model/list` and
 * `account/rateLimits/read`, then closes. No thread or turn is started.
 */
export function createCodexAppServerDiscovery(
  options: CodexAppServerDiscoveryOptions,
): CodexAppServerDiscovery {
  const modelsTtlMs = discoveryDuration(options.modelsTtlMs, 600_000, "modelsTtlMs");
  const limitsTtlMs = discoveryDuration(options.limitsTtlMs, 60_000, "limitsTtlMs");
  const timeoutMs = discoveryDuration(options.timeoutMs, 15_000, "timeoutMs");
  const now = options.now ?? (() => new Date());
  const cache = new Map<string, CodexDiscoveryProbe>();
  const pending = new Map<string, Promise<CodexDiscoveryProbe>>();

  const failure = (message: string): CodexDiscoveryProbe => {
    const result = {
      status: "unavailable" as const,
      message,
      code: CODEX_APP_SERVER_DISCOVERY_ERRORS.failed,
      retryable: true,
    };
    return { at: Number.NEGATIVE_INFINITY, models: result, limits: result };
  };

  const probe = async (request: HarnessDiscoveryRequest): Promise<CodexDiscoveryProbe> => {
    const abort = new AbortController();
    let connection: CodexAppServerConnection | undefined;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const expired = new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("timeout")), timeoutMs);
      });
      const answered = (async () => {
        connection = await options.connect({
          ...(request.accountId ? { accountId: request.accountId } : {}),
          signal: abort.signal,
        });
        const open = connection;
        if (abort.signal.aborted) {
          await Promise.resolve(open.close()).catch(() => undefined);
          throw new Error("timeout");
        }
        const client = createCodexAppServerClient({
          write: (line) => open.write(line),
          hooks: { notification() {} },
        });
        const decoder = new TextDecoder();
        const reading = (async () => {
          try {
            for await (const chunk of open.output) {
              client.text(typeof chunk === "string" ? chunk : decoder.decode(chunk, { stream: true }));
            }
          } catch {}
          client.end("the discovery connection closed");
        })();
        void reading;
        await client.initialize(codexInitializeParams({
          ...(options.initialize ?? {}),
          clientInfo: options.clientInfo,
        }));
        client.initialized();
        const rows: unknown[] = [];
        let cursor: unknown;
        for (let page = 0; page < MODEL_LIST_PAGES; page += 1) {
          const listed = await client.request("model/list", cursor ? { cursor } : {});
          const data = listed.data ?? listed.models;
          if (Array.isArray(data)) rows.push(...data);
          cursor = listed.nextCursor ?? listed.next_cursor;
          if (typeof cursor !== "string" || cursor === "") break;
        }
        const limits = await client.request("account/rateLimits/read").then(
          codexAccountLimitSnapshot,
          () => null,
        );
        return { models: codexModelCatalog({ data: rows }), limits };
      })();
      answered.catch(() => undefined);
      const { models, limits } = await Promise.race([answered, expired]);
      if (models.models.length === 0) return failure("Codex listed no models.");
      const at = now();
      return {
        at: at.getTime(),
        models: {
          status: "available",
          value: { selection: "optional", ...models },
          fetchedAt: at.toISOString(),
        },
        limits: limits
          ? {
              status: "available",
              value: limits,
              fetchedAt: at.toISOString(),
              expiresAt: new Date(at.getTime() + limitsTtlMs).toISOString(),
            }
          : { status: "unsupported", message: "This Codex account reports no limits." },
      };
    } catch {
      return failure("Codex did not answer discovery. Check that it is installed and signed in.");
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      abort.abort();
      await Promise.resolve(connection?.close()).catch(() => undefined);
    }
  };

  const resolve = async (request: HarnessDiscoveryRequest, ttlMs: number): Promise<CodexDiscoveryProbe> => {
    const key = request.accountId ?? "";
    const cached = cache.get(key);
    if (cached && now().getTime() - cached.at < ttlMs) return cached;
    let running = pending.get(key);
    if (!running) {
      running = probe(request).then((result) => {
        if (result.models.status === "available") cache.set(key, result);
        else cache.delete(key);
        return result;
      }).finally(() => pending.delete(key));
      pending.set(key, running);
    }
    return running;
  };

  return {
    models: async (request) => (await resolve(request, modelsTtlMs)).models,
    limits: async (request) => (await resolve(request, limitsTtlMs)).limits,
  };
}
