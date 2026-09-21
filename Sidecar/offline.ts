import { createScriptedAdapter } from "@serhiitroinin/fold-harness/testing";
import type { HarnessAdapter, HarnessAdapterRunRequest, HarnessAdapterEvent } from "@serhiitroinin/fold-harness";
import type { HarnessToolResult } from "@serhiitroinin/fold-harness";

export const OFFLINE_ENGINE = "kit:offline";

interface Entry {
  name: string;
  path: string;
  kind: "file" | "folder";
  ext?: string;
  created?: string;
  modified?: string;
  itemCount?: number;
}

const BUCKETS: readonly [string, readonly string[]][] = [
  ["Documents", ["pdf", "doc", "docx", "pages", "txt", "md", "rtf", "csv", "xlsx", "numbers", "key", "pptx"]],
  ["Images", ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]],
  ["Archives", ["zip", "tar", "gz", "tgz", "7z", "rar"]],
  ["Installers", ["dmg", "pkg", "app"]],
  ["Media", ["mp4", "mov", "mp3", "m4a", "wav"]],
];

function bucketFor(entry: Entry): string {
  const ext = (entry.ext ?? "").toLowerCase();
  if (/screenshot|screen shot|cleanshot/i.test(entry.name)) return "Screenshots";
  for (const [bucket, extensions] of BUCKETS) {
    if (extensions.includes(ext)) return bucket;
  }
  return "Other";
}

function yearOf(entry: Entry): string {
  const stamp = entry.created ?? entry.modified;
  const year = stamp ? new Date(stamp).getUTCFullYear() : Number.NaN;
  return Number.isFinite(year) ? String(year) : "Undated";
}

function readText(result: HarnessToolResult): string {
  const part = result.content.find((item) => item.type === "text");
  if (!part || part.type !== "text") throw new Error("the offline engine expected a text tool result");
  if (result.isError) throw new Error(part.text);
  return part.text;
}

/** A copy such as "report (1).pdf" gets a plain name once it is filed. */
function tidyName(name: string): string | undefined {
  const match = /^(.*) \((\d+)\)(\.[^.]+)$/.exec(name);
  return match ? `${match[1]}-copy-${match[2]}${match[3]}` : undefined;
}

/**
 * The one change request the scripted engine understands: "Put the archives in
 * Attic." renames a bucket, so a revision really differs from the plan before.
 */
function rebucket(context: unknown): { from: string; to: string } | undefined {
  const text = JSON.stringify(context ?? "");
  const written = /The user writes:(?:\\+n)+(.*?)\\+n/.exec(text)?.[1] ?? "";
  const match = /put (?:the |my )?(\w+) in(?:to)? ([\w-]+)/i.exec(written);
  if (!match) return undefined;
  const from = BUCKETS.map(([bucket]) => bucket).concat("Screenshots", "Other")
    .find((bucket) => bucket.toLowerCase() === match[1]!.toLowerCase());
  return from ? { from, to: match[2]! } : undefined;
}

function planFrom(
  entries: readonly Entry[],
  change?: { from: string; to: string },
): { summary: string; operations: unknown[] } {
  const named = (bucket: string) => (change && bucket === change.from ? change.to : bucket);
  const folders = new Set<string>();
  const operations: unknown[] = [];
  const moves: unknown[] = [];
  const renames: unknown[] = [];
  const removals: unknown[] = [];
  for (const entry of entries) {
    if (entry.kind === "folder") {
      if (entry.itemCount === 0) {
        removals.push({
          op: "trash",
          path: entry.path,
          reason: `${entry.name} holds nothing at all, so it only adds noise.`,
        });
      }
      continue;
    }
    const destination = `${named(bucketFor(entry))}/${yearOf(entry)}`;
    folders.add(named(bucketFor(entry)));
    folders.add(destination);
    moves.push({
      op: "move",
      from: entry.path,
      to: `${destination}/${entry.name}`,
      reason: `${entry.name} is a ${bucketFor(entry).toLowerCase()} file from ${yearOf(entry)}.`,
    });
    const tidy = tidyName(entry.name);
    if (tidy) {
      renames.push({
        op: "rename",
        from: `${destination}/${entry.name}`,
        to: `${destination}/${tidy}`,
        reason: `${entry.name} is a copy; the plain name reads better.`,
      });
    }
  }
  for (const path of [...folders].sort()) operations.push({ op: "mkdir", path });
  if (change) {
    operations.push(...moves, ...renames, ...removals);
    return {
      summary: `Updated. The ${change.from.toLowerCase()} now go to ${change.to}, still by year. `
        + `Everything else is as it was: ${moves.length} files, ${folders.size} folders.`,
      operations,
    };
  }
  operations.push(...moves, ...renames, ...removals);
  return {
    summary: `The offline engine sorted ${moves.length} files into ${folders.size} folders by kind and year, `
      + `renamed ${renames.length}, and proposed ${removals.length} for the Trash.`,
    operations,
  };
}

/** A development delay, so the live activity can be seen and captured. */
const pause = () => new Promise((resolve) => {
  setTimeout(resolve, Number(process.env.BUTLER_OFFLINE_DELAY_MS ?? 0));
});

async function* script(request: HarnessAdapterRunRequest): AsyncIterable<HarnessAdapterEvent> {
  yield { kind: "thinking", text: "Reading the top level of the folder." };
  await pause();
  const listing = readText(await request.tools.call("list_folder", { path: ".", depth: 1 }));
  const entries = (JSON.parse(listing) as { entries?: Entry[] }).entries ?? [];
  yield { kind: "assistant-text", text: `I found ${entries.length} entries. ` };
  await pause();
  const plan = planFrom(entries, rebucket(request.context));
  await pause();
  const recorded = readText(await request.tools.call("propose_plan", plan));
  yield { kind: "assistant-text", text: recorded };
  yield { kind: "usage", usage: { inputTokens: 1234, outputTokens: 56, totalTokens: 1290 } };
}

/** Test-only adapter. The application offers it only when BUTLER_OFFLINE=1. */
export function createOfflineEngine(): HarnessAdapter {
  const { adapter } = createScriptedAdapter({ id: OFFLINE_ENGINE, script });
  return {
    ...adapter,
    profile: () => ({
      status: "available",
      value: {
        id: OFFLINE_ENGINE,
        label: "Offline (development)",
        modelSelection: "optional",
        permissions: {
          kind: "permission-mode",
          selectable: false,
          defaultModeId: "app-tools-only",
          modes: [{ id: "app-tools-only", label: "Application tools only", posture: "restricted" }],
        },
      },
    }),
    models: () => ({
      status: "available",
      value: {
        selection: "optional",
        defaultModelId: "scripted",
        models: [{ id: "scripted", label: "Scripted" }],
      },
    }),
    limits: () => ({ status: "unsupported", message: "The offline engine has no account." }),
  };
}
