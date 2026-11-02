import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { IdleInhibitor } from "./inhibitor.ts";

export default function woke(pi: ExtensionAPI) {
	let working = false;
	let compacting = false;
	let waiting = false;
	let closed = false;
	let context: ExtensionContext | undefined;
	let lastError: string | undefined;
	const inhibitor = new IdleInhibitor((message) => {
		lastError = message;
		const warning = `woke: automatic sleep is not inhibited. ${message}`;
		if (context?.hasUI) context.ui.notify(warning, "warning");
		else process.stderr.write(`${warning}\n`);
	});

	async function sync(ctx: ExtensionContext) {
		context = ctx;
		if (!closed && (working || compacting) && !waiting) {
			lastError = undefined;
			await inhibitor.acquire();
		} else {
			inhibitor.release();
		}
	}

	pi.on("agent_start", async (_event, ctx) => {
		working = true;
		await sync(ctx);
	});
	// agent_end is too early: retries, compaction, or follow-ups may remain.
	pi.on("agent_settled", async (_event, ctx) => {
		working = !ctx.isIdle();
		await sync(ctx);
	});
	pi.on("session_before_compact", async (_event, ctx) => {
		compacting = true;
		await sync(ctx);
	});
	const compactFinished = async (_event: unknown, ctx: ExtensionContext) => {
		compacting = false;
		await sync(ctx);
	};
	pi.on("session_compact", compactFinished);
	pi.on("session_compact_failed", compactFinished);
	pi.on("ui_prompt_start", async (_event, ctx) => {
		waiting = true;
		await sync(ctx);
	});
	pi.on("ui_prompt_end", async (_event, ctx) => {
		waiting = false;
		await sync(ctx);
	});
	pi.on("session_shutdown", () => {
		closed = true;
		working = compacting = waiting = false;
		inhibitor.release();
		context = undefined;
	});
	pi.registerCommand("woke", {
		description: "Show automatic sleep inhibition status",
		handler: async (_args, ctx) => {
			const status = inhibitor.active ? "keeping the computer awake"
				: lastError ? `not inhibiting sleep: ${lastError}`
				: waiting ? "waiting for input; normal sleep allowed"
				: "idle; normal sleep allowed";
			ctx.ui.notify(`woke: ${status}`, lastError ? "warning" : "info");
		},
	});
}
