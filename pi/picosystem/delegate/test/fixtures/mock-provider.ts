import { setTimeout as delay } from "node:timers/promises";
import { createAssistantMessageEventStream, getCurrentSystemPrompt, type AssistantMessage, type ToolCall } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Offline provider for the worker tests, loaded into real pi workers with -e. It echoes the user
 * messages; the last one picks other behavior: ERROR, EXIT3, HANG, WAIT, SLEEP, HUGE, PROMPT_CHECK, SPAWN.
 * A first message BUSY plays a parent that keeps working while a background worker runs.
 */
export default function (pi: ExtensionAPI) {
  pi.registerProvider("subagent-test", {
    api: "subagent-test-api", apiKey: "test-only", baseUrl: "http://unused.invalid",
    models: [{
      id: "mock", name: "Offline mock", reasoning: false, input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 128000, maxTokens: 1000,
    }],
    streamSimple(model, context, options) {
      const stream = createAssistantMessageEventStream();
      const users = context.messages.filter((m) => m.role === "user").map((m) =>
        typeof m.content === "string" ? m.content : m.content.filter((p) => p.type === "text").map((p) => p.text).join("\n"));
      const last = users.at(-1) ?? "";
      const output: AssistantMessage = {
        role: "assistant", content: [{ type: "text", text: "" }],
        api: model.api, provider: model.provider, model: model.id, timestamp: Date.now(), stopReason: "pending",
        usage: { input: 10, output: 2, cacheRead: 0, cacheWrite: 0, totalTokens: 12, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0.001 } },
      };
      const respond = async () => {
        stream.push({ type: "start", partial: output });
        if (last === "EXIT3") process.exit(3);
        await delay(last === "HANG" ? 60_000 : last === "WAIT" ? 400 : 20, undefined, { signal: options?.signal });
        if (last === "ERROR") throw new Error("Deliberate mock failure.");
        if (last === "PROMPT_CHECK") {
          const prompt = getCurrentSystemPrompt(context.messages);
          if (!prompt.includes("MOCK_PROFILE_BODY") || !prompt.includes("No human reads this session")) throw new Error("prompt.md was not appended.");
        }
        const toolResult = context.messages.at(-1)?.role === "toolResult" ? context.messages.at(-1) : undefined;
        const busy = users[0] === "BUSY";
        const calls = context.messages.filter((m) => m.role === "toolResult").length;
        const seen = users.some((u) => u.includes("Echo: inner"));
        let toolCall: ToolCall | undefined;
        if (busy && calls === 0) toolCall = { type: "toolCall", id: "bg-call", name: "subagent", arguments: { agent: "mock", task: "inner", background: true } };
        else if (busy && !seen && calls <= 20) toolCall = { type: "toolCall", id: `nap-${calls}`, name: "bash", arguments: { command: "sleep 0.5" } };
        else if (!busy && (last === "SLEEP" || last === "SPAWN") && !toolResult) {
          toolCall = last === "SLEEP"
            ? { type: "toolCall", id: "sleep-call", name: "bash", arguments: { command: "sleep 47.31" } }
            : { type: "toolCall", id: "spawn-call", name: "subagent", arguments: { agent: "mock", task: "inner" } };
        }
        if (toolCall) {
          output.content = [toolCall];
          stream.push({ type: "toolcall_start", contentIndex: 0, partial: output });
          stream.push({ type: "toolcall_end", contentIndex: 0, toolCall, partial: output });
          output.stopReason = "toolUse";
          stream.push({ type: "done", reason: "toolUse", message: output });
          return;
        }
        const answer = busy ? (seen ? "Saw the result mid-run" : "Never saw the result")
          : last === "HUGE" ? Array.from({ length: 3000 }, (_, i) => `line ${i + 1}`).join("\n")
          : toolResult?.role === "toolResult" ? `Tool said: ${toolResult.content.map((p) => (p.type === "text" ? p.text : "")).join("")}`
          : `Echo: ${users.join(" | ")}`;
        stream.push({ type: "text_start", contentIndex: 0, partial: output });
        output.content[0] = { type: "text", text: answer };
        stream.push({ type: "text_delta", contentIndex: 0, delta: answer, partial: output });
        stream.push({ type: "text_end", contentIndex: 0, content: answer, partial: output });
        output.stopReason = "stop";
        stream.push({ type: "done", reason: "stop", message: output });
      };
      void respond().catch((error) => {
        output.stopReason = options?.signal?.aborted ? "aborted" : "error";
        output.errorMessage = error instanceof Error ? error.message : String(error);
        stream.push({ type: "error", reason: output.stopReason, error: output });
      }).finally(() => stream.end());
      return stream;
    },
  });
}
