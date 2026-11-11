import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";

// pi's side of the `notifi` command (scripts/notifi), which does the work:
// this only says when pi finished and when the notification went stale.

const STATE_ENTRY = "notifi-state";

/** Runs `notifi`; resolves to its output, or to `failed: <why>`. */
const notifi = (...args: string[]) =>
	new Promise<string>((resolve) => {
		execFile("notifi", args, { encoding: "utf8", timeout: 10_000 }, (error, stdout, stderr) =>
			resolve(error ? `failed: ${stderr.trim() || error.message}` : stdout.trim()),
		);
	});

const eventOf = (messages: unknown[]): string => {
	const last = messages.findLast((message) => (message as { role?: string })?.role === "assistant");
	const reason = (last as { stopReason?: string } | undefined)?.stopReason;
	return reason === "error" || reason === "aborted" ? reason : "finished";
};

export default function (pi: ExtensionAPI) {
	let enabled = true;

	/** Returns notifi's outcome: `sent`, `visible`, `blocked` or `failed: <why>`. */
	const show = async (ctx: ExtensionContext, event: string, force = false): Promise<string> => {
		const outcome = await notifi("show", "--app", "pi", "--event", event, "-v", ...(force ? ["--force"] : []));
		if (outcome.startsWith("failed")) ctx.ui.notify(`notifi ${outcome}`, "warning");
		return outcome;
	};
	const dismiss = () => notifi("dismiss", "--app", "pi");

	pi.on("session_start", async (_event, ctx) => {
		for (const entry of ctx.sessionManager.getEntries()) {
			const custom = entry as { type?: string; customType?: string; data?: { enabled?: unknown } };
			if (custom.type === "custom" && custom.customType === STATE_ENTRY && typeof custom.data?.enabled === "boolean") {
				enabled = custom.data.enabled;
			}
		}
	});

	// You're back at pi, or it is going away: the notification is stale.
	pi.on("agent_start", async () => void (await dismiss()));
	pi.on("session_shutdown", async () => void (await dismiss()));

	pi.on("agent_end", async (event, ctx) => {
		// Queued steering/follow-up messages mean pi isn't idle yet.
		if (!ctx.hasUI || !enabled || ctx.hasPendingMessages()) return;
		await show(ctx, eventOf(event.messages));
	});

	pi.registerCommand("notifi", {
		description: "Desktop notifications when pi finishes: status | test | on | off",
		handler: async (args, ctx) => {
			const subcommand = args.trim().toLowerCase() || "status";
			if (subcommand === "on" || subcommand === "off") {
				enabled = subcommand === "on";
				pi.appendEntry(STATE_ENTRY, { enabled });
				ctx.ui.notify(`notifi ${enabled ? "enabled" : "disabled"}`, "info");
			} else if (subcommand === "test") {
				const outcome = await show(ctx, "finished", true);
				ctx.ui.notify(`notifi test: ${outcome}`, "info");
			} else {
				ctx.ui.notify(`notifi is ${enabled ? "enabled" : "disabled"}; desktop delivery ${await notifi("status")}`, "info");
			}
		},
	});
}
