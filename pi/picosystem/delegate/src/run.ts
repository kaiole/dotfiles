import { spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { DEFAULT_MAX_BYTES, DEFAULT_MAX_LINES, truncateHead } from "@earendil-works/pi-coding-agent";
import type { AssistantMessage, Usage } from "@earendil-works/pi-ai";
import { NAME, type Loadout } from "./agents.ts";
import { renderPreloadedSkills } from "./skills.ts";

const RULES = "You are a subagent. No human reads this session. Your final message is returned to the parent agent as your result. If you are blocked, state exactly what you need and stop. You share the checkout with the parent and possibly other workers: edit only files your task concerns, and do not commit, stash, checkout, reset or rebase.";
const CANCELLED = "cancelled";

export type Status = "queued" | "running" | "done" | "failed" | "cancelled";
export interface Meta { name: string; loadout: Loadout; sessionId: string; status: Status }
export interface Task { name: string; dir: string; meta: Meta; child?: ChildProcess; cause?: string }
export interface Outcome { ok: boolean; text: string; usage: Usage; details: Record<string, unknown> }
export interface Hooks { signal?: AbortSignal; onUpdate?: (text: string) => void }
interface Entry { task: Task; message: string; hooks: Hooks; resolve: (outcome: Outcome) => void }

/** The same pi that runs the parent, also when it was started as `node cli.js`. */
export function piInvocation(args: string[]): string[] {
  const script = process.argv[1];
  if (script && !script.startsWith("/$bunfs/") && existsSync(script) && /(?:^|\/)cli\.(?:js|ts)$/.test(script)) {
    return [process.execPath, script, ...args];
  }
  if (!/^(node|bun)(\.exe)?$/i.test(basename(process.execPath))) return [process.execPath, ...args];
  return ["pi", ...args];
}

export function workerArgs(dir: string, l: Loadout, sessionId: string, message: string): string[] {
  return [
    "--mode", "json", "--no-extensions", ...l.extensions.flatMap((e) => ["-e", e]), "--no-prompt-templates",
    "--tools", l.tools.join(","), "--thinking", l.thinking, ...(l.model ? ["--model", l.model] : []),
    "--session-dir", join(dir, "session"), "--session-id", sessionId,
    "--append-system-prompt", join(dir, "prompt.md"), l.approveProject ? "--approve" : "--no-approve",
    // pi reads a message starting with @ as a file to attach, even after --.
    "--", message.startsWith("@") ? ` ${message}` : message,
  ];
}

/** SIGTERM the worker's group; pi's handler then kills its detached bash children. SIGKILL if it hangs. */
function kill(child: ChildProcess): void {
  const pid = child.pid;
  if (!pid) return;
  const send = (signal: NodeJS.Signals) => { try { process.kill(-pid, signal); } catch { /* already gone */ } };
  send("SIGTERM");
  setTimeout(() => send("SIGKILL"), 5000).unref();
}

function emptyUsage(): Usage {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
}

function addUsage(sum: Usage, usage: Usage | undefined): void {
  if (!usage) return;
  for (const key of ["input", "output", "cacheRead", "cacheWrite", "totalTokens"] as const) sum[key] += usage[key] ?? 0;
  for (const key of ["input", "output", "cacheRead", "cacheWrite", "total"] as const) sum.cost[key] += usage.cost?.[key] ?? 0;
}

function summarize(args: unknown): string {
  const a = (args ?? {}) as Record<string, unknown>;
  const value = a.command ?? a.path ?? a.pattern ?? a.query ?? a.url ?? Object.values(a).find((v) => typeof v === "string") ?? "";
  const text = String(value).replace(/\s+/g, " ").trim();
  return text.length > 60 ? `${text.slice(0, 59)}…` : text;
}

/** One parent session's workers: at most `concurrency` run, the rest wait in FIFO order. */
export class Runner {
  readonly root: string;
  disposed = false;
  private concurrency: number;
  private inactivityMs: number;
  private onChange: (running: number, queued: number) => void;
  private tasks = new Map<string, Task>();
  private queue: Entry[] = [];
  private live = new Map<Task, Entry>();
  private onExit = () => { for (const task of this.live.keys()) if (task.child?.pid) try { process.kill(-task.child.pid, "SIGTERM"); } catch { /* gone */ } };

  constructor(root: string, concurrency: number, inactivityMs: number, onChange: (running: number, queued: number) => void) {
    this.root = root;
    this.concurrency = concurrency;
    this.inactivityMs = inactivityMs;
    this.onChange = onChange;
    process.on("exit", this.onExit);
  }

  private exists(name: string): boolean { return this.tasks.has(name) || existsSync(join(this.root, name)); }

  create(name: string | undefined, loadout: Loadout): Task {
    if (name === undefined) {
      let n = 1;
      while (this.exists(`${loadout.agent}-${n}`)) n++;
      name = `${loadout.agent}-${n}`;
    } else if (!NAME.test(name)) {
      throw new Error(`Invalid name '${name}': use up to 64 letters, digits, '.', '_' or '-'.`);
    } else if (this.exists(name)) {
      throw new Error(`A subagent named '${name}' already exists in this session. Use subagent_continue to message it.`);
    }
    const dir = join(this.root, name);
    mkdirSync(join(dir, "session"), { recursive: true, mode: 0o700 });
    writeFileSync(join(dir, "prompt.md"), [loadout.systemPrompt, renderPreloadedSkills(loadout.skills), RULES].filter(Boolean).join("\n\n") + "\n");
    const task: Task = { name, dir, meta: { name, loadout, sessionId: randomUUID(), status: "queued" } };
    this.tasks.set(name, task);
    this.save(task);
    return task;
  }

  /** A finished task of this session, from memory or from its meta.json after a reload or resume. */
  load(name: string): Task {
    let task = this.tasks.get(name);
    if (!task) {
      const file = join(this.root, name, "meta.json");
      if (basename(name) !== name || name.startsWith(".") || !existsSync(file)) throw new Error(`No subagent named '${name}' in this session.`);
      task = { name, dir: join(this.root, name), meta: JSON.parse(readFileSync(file, "utf8")) as Meta };
      this.tasks.set(name, task);
    }
    if (this.live.has(task) || this.queue.some((entry) => entry.task === task)) {
      throw new Error(`Subagent '${name}' is still ${task.meta.status}. Wait for its result or cancel it.`);
    }
    return task;
  }

  list(): Task[] {
    return (existsSync(this.root) ? readdirSync(this.root) : []).flatMap((name) => {
      try { return [this.tasks.get(name) ?? { name, dir: join(this.root, name), meta: JSON.parse(readFileSync(join(this.root, name, "meta.json"), "utf8")) as Meta }]; }
      catch { return []; }
    });
  }

  start(task: Task, message: string, hooks: Hooks = {}): Promise<Outcome> {
    return new Promise((resolve) => {
      const abort = () => this.cancel(task.name);
      task.cause = undefined;
      this.setStatus(task, "queued");
      this.queue.push({ task, message, hooks, resolve: (outcome) => { hooks.signal?.removeEventListener("abort", abort); resolve(outcome); } });
      if (hooks.signal?.aborted) abort();
      else hooks.signal?.addEventListener("abort", abort, { once: true });
      this.pump();
    });
  }

  /** A queued task is just removed; a running one is killed. */
  cancel(name: string): boolean {
    const index = this.queue.findIndex((entry) => entry.task.name === name);
    if (index >= 0) {
      this.finish(this.queue.splice(index, 1)[0]!, CANCELLED);
      this.pump();
      return true;
    }
    const task = [...this.live.keys()].find((t) => t.name === name);
    if (!task?.child) return false;
    task.cause ??= CANCELLED;
    kill(task.child);
    return true;
  }

  dispose(): void {
    this.disposed = true;
    this.onChange = () => {};
    for (const entry of this.queue.splice(0)) this.finish(entry, CANCELLED);
    for (const task of this.live.keys()) this.cancel(task.name);
    process.off("exit", this.onExit);
  }

  private pump(): void {
    while (!this.disposed && this.live.size < this.concurrency && this.queue.length) this.launch(this.queue.shift()!);
    this.queue.forEach((entry, i) => entry.hooks.onUpdate?.(`queued (${i} ahead)`));
    this.onChange(this.live.size, this.queue.length);
  }

  private launch(entry: Entry): void {
    const { task, message, hooks } = entry;
    const [command, ...args] = piInvocation(workerArgs(task.dir, task.meta.loadout, task.meta.sessionId, message));
    const child = spawn(command!, args, {
      cwd: task.meta.loadout.cwd, detached: true, stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, PI_SUBAGENT: "1" },
    });
    task.child = child;
    this.live.set(task, entry);
    this.setStatus(task, "running");
    hooks.onUpdate?.("running");
    const began = Date.now();
    const usage = emptyUsage();
    let last: AssistantMessage | undefined;
    let aborted: boolean | undefined;
    let stdout = "";
    let stderr = "";
    let timer: NodeJS.Timeout | undefined;
    const arm = () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        task.cause ??= `no event for ${this.inactivityMs / 1000} s (inactivity timeout)`;
        kill(child);
      }, this.inactivityMs);
    };
    const onLine = (line: string) => {
      let event: { type?: string; [key: string]: any };
      try { event = JSON.parse(line); } catch { return; } // stdout is JSONL; skip anything else
      arm();
      if (event.type === "message_end" && event.message?.role === "assistant") {
        last = event.message;
        addUsage(usage, event.message.usage);
      } else if (event.type === "agent_settled") {
        aborted = event.aborted;
      } else if (event.type === "tool_execution_start") {
        hooks.onUpdate?.(`${event.toolName} ${summarize(event.args)} · ${Math.round((Date.now() - began) / 1000)}s · ${usage.totalTokens} tokens`);
      }
    };
    arm();
    child.stdout!.setEncoding("utf8");
    child.stdout!.on("data", (chunk: string) => {
      stdout += chunk;
      for (let i = stdout.indexOf("\n"); i >= 0; i = stdout.indexOf("\n")) {
        onLine(stdout.slice(0, i));
        stdout = stdout.slice(i + 1);
      }
    });
    child.stderr!.setEncoding("utf8");
    child.stderr!.on("data", (chunk: string) => {
      stderr = (stderr + chunk).slice(-64_000);
      appendFileSync(join(task.dir, "stderr.log"), chunk);
    });
    let ended = false;
    const end = (code: number | null, signal: NodeJS.Signals | null) => {
      if (ended) return;
      ended = true;
      if (stdout) onLine(stdout);
      clearTimeout(timer);
      this.live.delete(task);
      task.child = undefined;
      const text = (last?.content ?? []).flatMap((part) => (part.type === "text" ? [part.text] : [])).join("\n").trim();
      const stop = last?.stopReason;
      const cause = task.cause
        ?? (code !== 0 ? `exit code ${code ?? signal}` : undefined)
        ?? (!last ? "no reply from the model" : undefined)
        ?? (stop === "error" || stop === "aborted" || stop === "length" ? `stop reason ${stop}${last?.errorMessage ? ` (${last.errorMessage})` : ""}` : undefined)
        ?? (aborted !== false ? "the run did not settle" : undefined)
        ?? (!text ? "the final message has no text" : undefined);
      this.finish(entry, cause, usage, text, stderr);
      this.pump();
    };
    child.on("error", (error) => {
      task.cause ??= `could not start pi: ${error.message}`;
      if (child.pid === undefined) end(null, null);
    });
    child.on("close", end);
  }

  private finish(entry: Entry, cause: string | undefined, usage = emptyUsage(), text = "", stderr = ""): void {
    const { task } = entry;
    const status: Status = !cause ? "done" : cause === CANCELLED ? "cancelled" : "failed";
    const tail = stderr.trimEnd().split("\n").slice(-40).join("\n");
    const full = !cause ? text : [
      `Subagent ${task.name} ${status === "cancelled" ? "was cancelled" : `failed: ${cause}`}.`,
      text && `Its last message:\n${text}`,
      tail && `stderr (last 40 lines):\n${tail}`,
    ].filter(Boolean).join("\n\n");
    const resultFile = join(task.dir, "result.md");
    writeFileSync(resultFile, full + "\n");
    const cut = truncateHead(full, { maxLines: DEFAULT_MAX_LINES, maxBytes: DEFAULT_MAX_BYTES });
    const body = cut.truncated ? `${cut.content}\n\n[Truncated to ${cut.outputLines} of ${cut.totalLines} lines. Full result: ${resultFile}]` : full;
    this.setStatus(task, status);
    entry.resolve({
      ok: !cause,
      usage,
      text: `${body}\n\n[subagent ${task.name} · ${status} · ${usage.totalTokens} tokens · $${usage.cost.total.toFixed(4)}]`,
      details: { name: task.name, agent: task.meta.loadout.agent, status, cause, usage, sessionDir: join(task.dir, "session"), sessionId: task.meta.sessionId, resultFile },
    });
  }

  private setStatus(task: Task, status: Status): void {
    task.meta.status = status;
    this.save(task);
  }

  private save(task: Task): void {
    const file = join(task.dir, "meta.json");
    writeFileSync(`${file}.tmp`, JSON.stringify(task.meta, null, 2) + "\n", { mode: 0o600 });
    renameSync(`${file}.tmp`, file);
  }
}
