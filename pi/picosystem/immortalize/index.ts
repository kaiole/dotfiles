import { SessionManager, type ExtensionAPI, type SessionHeader } from "@earendil-works/pi-coding-agent";
import { publishSessionSnapshot } from "./session-file.ts";

const ANCHOR_TYPE = "immortalize.anchor";

function describeSession(name: string | undefined, id: string, path: string): string {
	return [`Session saved${name ? ` as \"${name}\"` : ""}`, `ID: ${id}`, `Path: ${path}`].join("\n");
}

export default function immortalize(pi: ExtensionAPI) {
	pi.registerCommand("immortalize", {
		description: "Save an ephemeral conversation as a normal session (usage: /immortalize [name])",
		handler: async (args, ctx) => {
			await ctx.waitForIdle();
			const requestedName = args.trim();
			const existingPath = ctx.sessionManager.getSessionFile();

			if (existingPath) {
				if (requestedName) pi.setSessionName(requestedName);
				const name = requestedName || ctx.sessionManager.getSessionName();
				ctx.ui.notify(
					requestedName
						? describeSession(name, ctx.sessionManager.getSessionId(), existingPath)
						: `Session is already saved.\nID: ${ctx.sessionManager.getSessionId()}\nPath: ${existingPath}`,
					"info",
				);
				return;
			}

			try {
				if (requestedName) pi.setSessionName(requestedName);
				// Session files encode no leaf pointer. Making the active leaf the final
				// physical entry ensures SessionManager.open() restores the same branch.
				pi.appendEntry(ANCHOR_TYPE);

				const header = ctx.sessionManager.getHeader() as SessionHeader | null;
				if (!header) throw new Error("The current session has no header");
				const sessionDir = SessionManager.create(ctx.cwd).getSessionDir();
				const targetPath = await publishSessionSnapshot(header, ctx.sessionManager.getEntries(), {
					sessionDir,
					validate: (path) => {
						const opened = SessionManager.open(path);
						if (opened.getSessionId() !== header.id) throw new Error("Saved session ID did not validate");
					},
				});

				const result = await ctx.switchSession(targetPath, {
					withSession: async (freshCtx) => {
						freshCtx.ui.notify(
							describeSession(freshCtx.sessionManager.getSessionName(), freshCtx.sessionManager.getSessionId(), targetPath),
							"info",
						);
					},
				});
				if (result.cancelled) {
					ctx.ui.notify(`Session was saved, but switching to it was cancelled.\nPath: ${targetPath}`, "warning");
				}
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Could not save session: ${message}`, "error");
			}
		},
	});
}
