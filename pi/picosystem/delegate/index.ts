import { join } from "node:path";
import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { discoverAgents, resolveLoadout } from "./src/agents.ts";
import { Runner, type Task } from "./src/run.ts";

interface Settings { subagents?: { concurrency?: unknown; inactivityTimeout?: unknown } }
type Update = ((result: { content: { type: "text"; text: string }[]; details: unknown }) => void) | undefined;

const positive = (value: unknown, fallback: number) => (typeof value === "number" && value > 0 ? value : fallback);

export default function delegate(pi: ExtensionAPI) {
  // Depth guard: a worker whose profile loads this extension anyway gets no subagent tools.
  if (process.env.PI_SUBAGENT === "1") return;
  let runner: Runner | undefined;
  let statusCtx: ExtensionContext | undefined;

  function runnerFor(ctx: ExtensionContext): Runner {
    statusCtx = ctx;
    const root = join(getAgentDir(), "subagents", ctx.sessionManager.getSessionId());
    if (runner?.root === root) return runner;
    runner?.dispose();
    const settings = (pi.getSettings() as Settings).subagents ?? {};
    runner = new Runner(root, Math.floor(positive(settings.concurrency, 8)), positive(settings.inactivityTimeout, 600) * 1000, (running, queued) =>
      statusCtx?.ui.setStatus("subagents", running + queued ? `agents ${running} running${queued ? ` · ${queued} queued` : ""}` : undefined));
    return runner;
  }

  async function run(r: Runner, task: Task, message: string, background: boolean | undefined, signal?: AbortSignal, onUpdate?: Update) {
    if (background) {
      void r.start(task, message).then((outcome) => {
        // After the parent session changed or ended, drop it: the worker's session file still has it.
        if (r.disposed) return;
        // Steer, not followUp: a follow-up waits for the parent's whole run to end, so a busy parent
        // never sees the result, asks the worker again, and then gets every result as its own turn.
        pi.sendMessage({ customType: "subagent-result", content: outcome.text, display: true, details: outcome.details },
          { deliverAs: "steer", triggerTurn: outcome.details.status !== "cancelled" });
      });
      return { content: [{ type: "text" as const, text: `Started ${task.name} in the background (${task.meta.status}). Its result arrives as a message when it finishes.` }], details: { name: task.name } };
    }
    const outcome = await r.start(task, message, { signal, onUpdate: (text) => onUpdate?.({ content: [{ type: "text", text: `${task.name}: ${text}` }], details: { name: task.name } }) });
    return { content: [{ type: "text" as const, text: outcome.text }], details: outcome.details, usage: outcome.usage, isError: !outcome.ok };
  }

  pi.on("session_start", (_event, ctx) => { statusCtx = ctx; });
  pi.on("session_shutdown", (_event, ctx) => {
    runner?.dispose();
    runner = undefined;
    ctx.ui.setStatus("subagents", undefined);
  });

  // Never executionMode "sequential": that would serialize the whole turn, and fan-out is the point.
  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description: "Run a headless worker from an agent profile (scout: read-only code search; worker: edits and tests; researcher: web). It sees only your task text and the checkout. By default the call waits and returns the worker's final answer; several calls in one turn run in parallel. background: true returns at once; the result arrives by itself between your later tool calls, or starts a turn when you are idle, so don't poll for it or redo the worker's task meanwhile. A blocked worker says what it needs; answer with subagent_continue. Workers cannot spawn workers.",
    parameters: Type.Object({
      agent: Type.String({ description: "Profile name, e.g. scout, worker, researcher" }),
      task: Type.String({ description: "Complete, self-contained instructions; the parent conversation is not copied" }),
      name: Type.Optional(Type.String({ description: "Task name, unique in this session; default <agent>-<n>" })),
      cwd: Type.Optional(Type.String({ description: "Working directory; default the parent's" })),
      model: Type.Optional(Type.String({ description: "provider/model, overriding the profile's" })),
      background: Type.Optional(Type.Boolean({ description: "Return at once; the result arrives later as a message" })),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      const { agents, warnings } = discoverAgents(ctx.cwd, ctx.isProjectTrusted());
      const agent = agents.find((a) => a.name === params.agent);
      if (!agent) {
        throw new Error(`Unknown profile '${params.agent}'. Available: ${agents.map((a) => a.name).join(", ") || "none"}.${warnings.length ? `\nBroken profiles:\n${warnings.join("\n")}` : ""}`);
      }
      const r = runnerFor(ctx);
      const task = r.create(params.name, resolveLoadout(agent, pi, ctx, params.cwd, params.model));
      return run(r, task, params.task, params.background, signal, onUpdate);
    },
  });

  pi.registerTool({
    name: "subagent_continue",
    label: "Continue subagent",
    description: "Send a finished worker a new message, resuming its session with the same profile, tools and model. Waits for its answer unless background is true.",
    parameters: Type.Object({
      name: Type.String({ description: "Task name from the subagent result" }),
      message: Type.String(),
      background: Type.Optional(Type.Boolean({ description: "Return at once; the result arrives later as a message" })),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      const r = runnerFor(ctx);
      return run(r, r.load(params.name), params.message, params.background, signal, onUpdate);
    },
  });

  pi.registerTool({
    name: "subagent_cancel",
    label: "Cancel subagent",
    description: "Kill a running background worker or remove a queued one.",
    parameters: Type.Object({ name: Type.String() }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      if (!runnerFor(ctx).cancel(params.name)) throw new Error(`No running or queued subagent named '${params.name}'.`);
      return { content: [{ type: "text", text: `Cancelled ${params.name}.` }], details: { name: params.name } };
    },
  });

  pi.registerCommand("subagents", {
    description: "List this session's subagents, or cancel one: /subagents cancel <name>",
    handler: async (args, ctx) => {
      const r = runnerFor(ctx);
      const [verb, name] = args.trim().split(/\s+/);
      if (verb === "cancel" && name) {
        ctx.ui.notify(r.cancel(name) ? `Cancelled ${name}` : `No running or queued subagent named ${name}`, "info");
        return;
      }
      const lines = r.list().map((t) => `${t.name}  ${t.meta.status}  (${t.meta.loadout.agent})\n  pi --session-dir ${join(t.dir, "session")} --session ${t.meta.sessionId}`);
      ctx.ui.notify(lines.join("\n") || "No subagents in this session.", "info");
    },
  });
}
