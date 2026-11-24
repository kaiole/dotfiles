import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, afterEach, test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import delegate from "../index.ts";
import { discoverAgents } from "../src/agents.ts";

// Real pi workers with the offline mock provider, in a throwaway agent dir (read lazily by getAgentDir).
const home = mkdtempSync(join(tmpdir(), "delegate-test-"));
const agentDir = join(home, "agent");
const workdir = join(home, "work");
process.env.PI_CODING_AGENT_DIR = agentDir;
mkdirSync(join(agentDir, "agents"), { recursive: true });
mkdirSync(workdir);
after(() => rmSync(home, { recursive: true, force: true }));

const fixture = fileURLToPath(new URL("./fixtures/mock-provider.ts", import.meta.url));
function profile(name: string, tools = "read", extra = "") {
  writeFileSync(join(agentDir, "agents", `${name}.md`),
    `---\nname: ${name}\ndescription: Test profile.\ntools: ${tools}\nextensions: [${fixture}]\nmodel: subagent-test/mock\nthinking: off\n${extra}---\nMOCK_PROFILE_BODY\n`);
}
profile("mock");
profile("sleeper", "bash");
profile("cont");
profile("nested", "read, subagent");
profile("old", "read", "isolation: worktree\n");
writeFileSync(join(agentDir, "agents", "scout.md"), "---\nname: scout\ndescription: Broken override.\ntools: read\nisolation: worktree\n---\n");

let sessions = 0;
const open: (() => Promise<void>)[] = [];
afterEach(async () => { for (const shutdown of open.splice(0)) await shutdown(); });

function setup(settings: Record<string, unknown> = {}, sessionId = `parent-${++sessions}`) {
  const tools = new Map<string, any>();
  const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
  const sent: { message: any; options: any }[] = [];
  const statuses: (string | undefined)[] = [];
  const pi = {
    registerTool: (tool: any) => tools.set(tool.name, tool),
    registerCommand: () => {},
    on: (event: string, handler: any) => handlers.set(event, handler),
    sendMessage: (message: any, options: any) => sent.push({ message, options }),
    getAllTools: () => [],
    getCommands: () => [],
    getThinkingLevel: () => "off",
    getSettings: () => ({ subagents: settings }),
  };
  delegate(pi as any);
  const ctx = {
    cwd: workdir, model: undefined, thinkingLevel: "off", hasUI: false, isProjectTrusted: () => false,
    ui: { setStatus: (_key: string, text?: string) => statuses.push(text), notify: () => {} },
    sessionManager: { getSessionId: () => sessionId },
  };
  const call = (name: string, params: Record<string, unknown>, opts: { signal?: AbortSignal; onUpdate?: (text: string) => void } = {}) =>
    tools.get(name).execute("call-id", params, opts.signal, (update: any) => opts.onUpdate?.(update.content[0].text), ctx);
  const shutdown = async () => { await handlers.get("session_shutdown")?.({ type: "session_shutdown", reason: "quit" }, ctx); };
  open.push(shutdown);
  return { tools, sent, statuses, call, sessionId, shutdown };
}

async function until(check: () => boolean, ms: number) {
  for (const end = Date.now() + ms; !check(); await sleep(50)) if (Date.now() > end) assert.fail("timed out");
}

const pgrep = (pattern: string) => { try { execFileSync("pgrep", ["-f", pattern]); return true; } catch { return false; } };
const taskDir = (sessionId: string, name: string) => join(agentDir, "subagents", sessionId, name);

test("the worker's final answer is the result, with its usage and files", async () => {
  const { call, sessionId } = setup();
  const result = await call("subagent", { agent: "mock", task: "PROMPT_CHECK" });
  assert.equal(result.isError, false, result.content[0].text);
  assert.match(result.content[0].text, /^Echo: PROMPT_CHECK\n\n\[subagent mock-1 · done · 12 tokens · \$0\.0010\]$/);
  assert.equal(result.usage.totalTokens, 12);
  const dir = taskDir(sessionId, "mock-1");
  const meta = JSON.parse(readFileSync(join(dir, "meta.json"), "utf8"));
  assert.equal(meta.status, "done");
  assert.equal(meta.loadout.model, "subagent-test/mock");
  assert.ok(readdirSync(join(dir, "session")).some((file) => file.includes(meta.sessionId)));
  assert.equal(readFileSync(join(dir, "result.md"), "utf8"), "Echo: PROMPT_CHECK\n");
});

test("a task starting with @ reaches the worker as text", async () => {
  const result = await setup().call("subagent", { agent: "mock", task: "@nofile here" });
  assert.equal(result.isError, false, result.content[0].text);
  assert.match(result.content[0].text, /^Echo: +@nofile here/);
});

test("an error stop reason fails although pi exits 0", async () => {
  const result = await setup().call("subagent", { agent: "mock", task: "ERROR" });
  assert.equal(result.isError, true);
  assert.equal(result.details.status, "failed");
  assert.match(result.content[0].text, /^Subagent mock-1 failed: stop reason error \(Deliberate mock failure\.\)/);
});

test("a non-zero exit fails", async () => {
  const result = await setup().call("subagent", { agent: "mock", task: "EXIT3" });
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /failed: exit code 3/);
});

test("inactivity kills the worker as failed", async () => {
  const started = Date.now();
  const result = await setup({ inactivityTimeout: 1.5 }).call("subagent", { agent: "mock", task: "HANG" });
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /failed: no event for 1\.5 s \(inactivity timeout\)/);
  assert.ok(Date.now() - started < 10_000);
});

test("the queue runs at most N at once and starts them in order", async () => {
  const { call, statuses } = setup({ concurrency: 2 });
  const started: string[] = [];
  const updates: string[] = [];
  const results = await Promise.all([0, 1, 2, 3, 4].map((i) => call("subagent", { agent: "mock", task: "WAIT", name: `q${i}` }, {
    onUpdate: (text) => { updates.push(text); if (text === `q${i}: running`) started.push(`q${i}`); },
  })));
  assert.ok(results.every((result) => !result.isError));
  assert.deepEqual(started, ["q0", "q1", "q2", "q3", "q4"]);
  assert.ok(updates.includes("q4: queued (2 ahead)"));
  assert.ok(statuses.includes("agents 2 running · 3 queued"));
  assert.equal(Math.max(...statuses.map((s) => Number(s?.match(/agents (\d+) running/)?.[1] ?? 0))), 2);
  assert.equal(statuses.at(-1), undefined);
});

test("abort kills the worker and the sleep its bash runs", async () => {
  const controller = new AbortController();
  const pending = setup().call("subagent", { agent: "sleeper", task: "SLEEP" }, { signal: controller.signal });
  await until(() => pgrep("sleep 47.31"), 15_000);
  controller.abort();
  const result = await pending;
  assert.equal(result.details.status, "cancelled");
  await until(() => !pgrep("sleep 47.31") && !pgrep(result.details.sessionId), 6000);
});

test("a background result is steered into the parent", async () => {
  const { call, sent } = setup();
  const started = await call("subagent", { agent: "mock", task: "bg", background: true });
  assert.match(started.content[0].text, /^Started mock-1 in the background \(running\)/);
  await until(() => sent.length === 1, 15_000);
  assert.equal(sent[0]!.message.customType, "subagent-result");
  assert.match(sent[0]!.message.content, /^Echo: bg/);
  assert.deepEqual(sent[0]!.options, { deliverAs: "steer", triggerTurn: true });
});

test("session shutdown kills background workers and drops their results", async () => {
  const { call, sent, shutdown, statuses } = setup();
  await call("subagent", { agent: "mock", task: "HANG", background: true });
  await until(() => pgrep("subagent-test/mock.*HANG"), 15_000);
  await shutdown();
  await until(() => !pgrep("subagent-test/mock.*HANG"), 6000);
  await sleep(200);
  assert.equal(sent.length, 0);
  assert.equal(statuses.at(-1), undefined);
});

test("cancel removes a queued task before it starts", async () => {
  const { call, sent, sessionId } = setup({ concurrency: 1 });
  await call("subagent", { agent: "mock", task: "WAIT", name: "first", background: true });
  const queued = await call("subagent", { agent: "mock", task: "never", name: "second", background: true });
  assert.match(queued.content[0].text, /\(queued\)/);
  assert.match((await call("subagent_cancel", { name: "second" })).content[0].text, /^Cancelled second/);
  await until(() => sent.length === 2, 15_000);
  const dir = taskDir(sessionId, "second");
  assert.equal(JSON.parse(readFileSync(join(dir, "meta.json"), "utf8")).status, "cancelled");
  assert.deepEqual(readdirSync(join(dir, "session")), []);
  assert.equal(sent.find((s) => s.message.details.name === "second")!.options.triggerTurn, false);
  await assert.rejects(call("subagent_cancel", { name: "second" }), /No running or queued subagent/);
});

test("subagent_continue reuses the session and loadout, also after a reload", async () => {
  const first = setup();
  assert.match((await first.call("subagent", { agent: "cont", task: "one" })).content[0].text, /^Echo: one\n/);
  assert.match((await first.call("subagent_continue", { name: "cont-1", message: "two" })).content[0].text, /^Echo: one \| two\n/);
  // A reload is a new extension instance; it must work from meta.json, not the profile.
  rmSync(join(agentDir, "agents", "cont.md"));
  const reloaded = setup({}, first.sessionId);
  const third = await reloaded.call("subagent_continue", { name: "cont-1", message: "three" });
  assert.match(third.content[0].text, /^Echo: one \| two \| three\n/);
  assert.equal(readdirSync(join(taskDir(first.sessionId, "cont-1"), "session")).length, 1);
  await assert.rejects(reloaded.call("subagent_continue", { name: "missing", message: "x" }), /No subagent named 'missing'/);
});

test("truncation saves the full result and returns its path", async () => {
  const result = await setup().call("subagent", { agent: "mock", task: "HUGE" });
  const match = result.content[0].text.match(/\[Truncated to 2000 of 3000 lines\. Full result: (\S+result\.md)\]/);
  assert.ok(match, "truncation notice");
  assert.equal(readFileSync(match[1], "utf8").trimEnd().split("\n").length, 3000);
});

// A real pi parent with this extension and the mock model, run on one prompt; its JSON events.
function parent(prompt: string): any[] {
  const out = execFileSync("pi", ["--mode", "json", "--no-extensions", "-e", fileURLToPath(new URL("../index.ts", import.meta.url)),
    "-e", fixture, "--model", "subagent-test/mock", "--thinking", "off", "--no-session", "--", prompt],
  { cwd: workdir, encoding: "utf8", env: { ...process.env, PI_SUBAGENT: "" } });
  return out.split("\n").filter(Boolean).map((line) => JSON.parse(line));
}
const answers = (events: any[]) => events.filter((e) => e.type === "message_end" && e.message.role === "assistant")
  .map((e) => e.message.content.map((p: any) => (p.type === "text" ? p.text : "")).join(""));

test("a real pi parent loads the extension and gets the worker's answer", async () => {
  const events = parent("SPAWN");
  const end = events.find((e) => e.type === "tool_execution_end" && e.toolName === "subagent");
  assert.equal(end.result.usage.totalTokens, 12);
  assert.match(answers(events).at(-1)!, /^Tool said: Echo: inner\n/);
});

test("a busy parent sees a background result between its tool calls", async () => {
  // The mock parent starts a background worker, then naps in bash until the result is in its context.
  const said = answers(parent("BUSY"));
  assert.ok(!said.includes("Never saw the result"), "the result waited for the parent's run to end");
  assert.equal(said.at(-1), "Saw the result mid-run");
});

test("depth guard: subagent tools are refused in profiles, and nothing registers in a worker", async () => {
  await assert.rejects(setup().call("subagent", { agent: "nested", task: "x" }), /workers cannot use 'subagent'/);
  process.env.PI_SUBAGENT = "1";
  try { assert.equal(setup().tools.size, 0); } finally { delete process.env.PI_SUBAGENT; }
});

test("a profile with an unknown key is rejected, and a broken override hides the bundled one", async () => {
  const { agents, warnings } = discoverAgents(workdir, false);
  const names = agents.map((agent) => agent.name);
  assert.ok(!names.includes("old") && !names.includes("scout"));
  assert.ok(names.includes("worker") && names.includes("researcher"));
  assert.ok(warnings.some((w) => w.includes("old.md: Unknown key: isolation")));
  await assert.rejects(setup().call("subagent", { agent: "old", task: "x" }), /Unknown profile 'old'[\s\S]*Unknown key: isolation/);
});
