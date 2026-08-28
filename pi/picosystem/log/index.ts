import { uuidv7 } from "@earendil-works/pi-ai";
import { CONFIG_DIR_NAME, type ExtensionAPI, type ExtensionCommandContext, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, type AutocompleteItem } from "@earendil-works/pi-tui";
import { createHash, randomUUID } from "node:crypto";
import { readdirSync } from "node:fs";
import { appendFile, mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";

// Keep the old state type so active logs survive the extension rename.
const STATE_TYPE = "md-log-state";
const DEFAULT_LOG_DIR = join(CONFIG_DIR_NAME, "logs");
const SNAPSHOT_DIR = join(tmpdir(), "pi-log");
const COMPACTION_PROMPT = `Rewrite the supplied Markdown conversation log as concise, durable learning notes.

Use your judgment about organization; do not force the material into a fixed template. Preserve the important concepts, insights, explanations, corrections, conclusions, decisions, useful examples, formulas, references, changes in understanding, and unresolved questions. Capture how the user's understanding or the work progressed when that progression is useful.

Remove dialogue formatting, conversational filler, repetition, false starts, superseded ideas, and incidental details. Do not preserve recent messages verbatim. The result replaces the entire transcript, so make it self-contained. Do not include a document title. Return only the rewritten Markdown, without commentary or an outer code fence.`;

type State = {
	activePath?: string;
	directoryOverride?: string;
	seenEntryIds: string[];
};

type MessageEntry = {
	type: "message";
	id: string;
	message: {
		role: string;
		content: string | Array<{ type: string; text?: string }>;
	};
};

export default function log(pi: ExtensionAPI) {
	let state: State = { seenEntryIds: [] };
	let currentCwd = process.cwd();
	let globalDirectory: string | undefined;
	let projectDirectory: string | undefined;
	let pendingUserInputs: string[] = [];
	let animationTimer: ReturnType<typeof setInterval> | undefined;
	let requestRender: (() => void) | undefined;
	let operation = Promise.resolve();

	function enqueue(task: () => Promise<void>): Promise<void> {
		const next = operation.then(task, task);
		operation = next.catch(() => {});
		return next;
	}

	function persistState() {
		pi.appendEntry(STATE_TYPE, {
			activePath: state.activePath,
			directoryOverride: state.directoryOverride,
			seenEntryIds: state.seenEntryIds,
		});
	}

	function effectiveLogDir(): string {
		const configured = state.directoryOverride ?? projectDirectory ?? globalDirectory ?? DEFAULT_LOG_DIR;
		return isAbsolute(configured) ? configured : resolve(currentCwd, configured);
	}

	function displayPath(path: string): string {
		const fromProject = relative(currentCwd, path);
		return fromProject && !fromProject.startsWith("..") && !isAbsolute(fromProject)
			? fromProject
			: path;
	}

	function stopAnimation() {
		if (animationTimer) clearInterval(animationTimer);
		animationTimer = undefined;
		requestRender = undefined;
	}

	function updateIndicator(ctx: ExtensionContext, compacting = false) {
		stopAnimation();
		if (!state.activePath) {
			ctx.ui.setWidget("log", undefined);
			return;
		}

		const destination = displayPath(state.activePath);
		const spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
		let spinnerIndex = 0;
		ctx.ui.setWidget("log", (tui, theme) => {
			if (compacting) requestRender = () => tui.requestRender();
			return {
				render: (width) => [truncateToWidth(
					compacting
						? " " + theme.fg("accent", spinnerFrames[spinnerIndex])
							+ theme.fg("muted", ` Compacting: ${destination}`)
						: " " + theme.fg("error", "●")
							+ theme.fg("muted", ` Logging to: ${destination}`),
					width,
				)],
				invalidate: () => {},
			};
		});
		if (compacting) {
			animationTimer = setInterval(() => {
				spinnerIndex = (spinnerIndex + 1) % spinnerFrames.length;
				requestRender?.();
			}, 80);
		}
	}

	function textFrom(entry: MessageEntry, rawUserInput?: string): string | undefined {
		const { role, content } = entry.message;
		if (role !== "user" && role !== "assistant") return undefined;

		const text = role === "user" && rawUserInput !== undefined
			? rawUserInput
			: typeof content === "string"
				? content
				: content
					.filter((block) => block.type === "text" && typeof block.text === "string")
					.map((block) => block.text)
					.join("\n\n");

		if (!text.trim()) return undefined;
		const loggedText = role === "user" && rawUserInput === undefined
			? restoreSkillCommand(text.trim())
			: text.trim();
		const callout = role === "user"
			? "> [!QUESTION] User"
			: "> [!ABSTRACT] PI";
		const separator = role === "assistant" ? "---\n\n" : "";
		return `${callout}\n\n${normalizeMathDelimiters(loggedText)}\n\n${separator}`;
	}

	async function ensureLog(path: string) {
		await mkdir(dirname(path), { recursive: true });
		try {
			await readFile(path, "utf8");
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
			const title = basename(path, ".md");
			await writeFile(path, `# ${title}\n\n`, { flag: "wx" });
		}
	}

	async function sync(ctx: ExtensionContext) {
		if (!state.activePath) return;

		const seen = new Set(state.seenEntryIds);
		const additions: string[] = [];
		const chunks: string[] = [];

		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type !== "message" || seen.has(entry.id)) continue;
			const messageEntry = entry as MessageEntry;
			const rawUserInput = messageEntry.message.role === "user"
				? pendingUserInputs.shift()
				: undefined;
			const chunk = textFrom(messageEntry, rawUserInput);
			if (!chunk) continue;
			chunks.push(chunk);
			additions.push(entry.id);
		}

		if (chunks.length === 0) return;
		await ensureLog(state.activePath);
		await appendFile(state.activePath, chunks.join(""));
		state.seenEntryIds.push(...additions);
		persistState();
	}

	pi.on("session_start", async (_event, ctx) => {
		state = { seenEntryIds: [] };
		currentCwd = ctx.cwd;
		globalDirectory = await loadConfiguredDirectory(
			join(homedir(), CONFIG_DIR_NAME, "agent", "log.json"),
			ctx,
		);
		projectDirectory = ctx.isProjectTrusted()
			? await loadConfiguredDirectory(join(ctx.cwd, CONFIG_DIR_NAME, "log.json"), ctx)
			: undefined;
		pendingUserInputs = [];
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === STATE_TYPE) {
				const saved = entry.data as Partial<State> | undefined;
				state = {
					activePath: saved?.activePath,
					directoryOverride: typeof saved?.directoryOverride === "string"
						? saved.directoryOverride
						: undefined,
					seenEntryIds: Array.isArray(saved?.seenEntryIds) ? saved.seenEntryIds : [],
				};
			}
		}

		if (state.activePath) {
			if (basename(dirname(state.activePath)) === ".md-log") {
				state.activePath = join(dirname(dirname(state.activePath)), "md-log", basename(state.activePath));
				persistState();
			}
			updateIndicator(ctx);
			await enqueue(() => sync(ctx));
		} else {
			updateIndicator(ctx);
		}
	});

	pi.on("input", (event) => {
		if (state.activePath && event.source !== "extension") {
			pendingUserInputs.push(event.text);
		}
		return { action: "continue" };
	});

	pi.on("session_shutdown", () => {
		stopAnimation();
	});

	pi.on("agent_settled", async (_event, ctx) => {
		try {
			await enqueue(() => sync(ctx));
		} catch (error) {
			ctx.ui.notify(`log failed: ${error instanceof Error ? error.message : String(error)}`, "error");
		}
	});

	pi.registerCommand("log", {
		description: "Log conversation to Markdown; compact, redo, undo, or stop logging",
		getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
			const attachMatch = prefix.match(/^--attach(?:\s+(\S*))?$/);
			if (attachMatch) {
				const namePrefix = attachMatch[1] ?? "";
				let filenames: string[] = [];
				try {
					filenames = readdirSync(effectiveLogDir(), { withFileTypes: true })
						.filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
						.map((entry) => entry.name.slice(0, -3))
						.filter((name) => name.startsWith(namePrefix))
						.sort((a, b) => a.localeCompare(b));
				} catch {
					// The log directory is created lazily.
				}
				return filenames.length > 0
					? filenames.map((name) => ({
						value: `--attach ${name}`,
						label: name,
						description: displayPath(join(effectiveLogDir(), `${name}.md`)),
					}))
					: null;
			}

			const items: AutocompleteItem[] = [
				{ value: "--attach", label: "--attach", description: "Continue an existing log" },
				{ value: "--directory", label: "--directory", description: "Set this session's log directory" },
				{ value: "--directory-reset", label: "--directory-reset", description: "Use the project or global log directory" },
				{ value: "--prev", label: "--prev", description: "Include all previous exchanges; optionally add a count" },
				{ value: "--compact", label: "--compact", description: "Rewrite the log as concise learning notes" },
				{ value: "--redo-compact", label: "--redo-compact", description: "Regenerate from the pre-compaction snapshot" },
				{ value: "--undo-compact", label: "--undo-compact", description: "Restore and consume the pre-compaction snapshot" },
				{ value: "--stop", label: "--stop", description: "Stop logging" },
			];
			const matches = items.filter((item) => item.value.startsWith(prefix));
			return matches.length > 0 ? matches : null;
		},
		handler: async (rawArgs, ctx) => {
			const trimmedArgs = rawArgs.trim();
			const [action, ...promptParts] = trimmedArgs.split(/\s+/).filter(Boolean);

			if (action === "--directory" || action === "--directory-reset") {
				if (action === "--directory-reset") {
					if (promptParts.length > 0) {
						ctx.ui.notify("Usage: /log --directory-reset", "error");
						return;
					}
					state.directoryOverride = undefined;
				} else {
					const directory = trimmedArgs.slice("--directory".length).trim();
					if (!directory) {
						ctx.ui.notify("Usage: /log --directory <path>", "error");
						return;
					}
					state.directoryOverride = directory;
				}
				persistState();
				ctx.ui.notify(`Log directory: ${displayPath(effectiveLogDir())}`, "info");
				return;
			}

			if (action === "--compact" || action === "--redo-compact" || action === "--undo-compact") {
				if (!state.activePath) {
					ctx.ui.notify("Start logging before compacting", "error");
					return;
				}
				if (action === "--undo-compact" && promptParts.length > 0) {
					ctx.ui.notify("Usage: /log --undo-compact", "error");
					return;
				}

				await ctx.waitForIdle();
				const showCompacting = action !== "--undo-compact";
				if (showCompacting) updateIndicator(ctx, true);
				try {
					await enqueue(async () => {
						await sync(ctx);
						const snapshot = snapshotPath(state.activePath!);

						if (action === "--undo-compact") {
							const original = await readSnapshot(snapshot);
							await atomicWrite(state.activePath!, original);
							await unlink(snapshot);
							return;
						}

						const isRedo = action === "--redo-compact";
						const source = isRedo
							? await readSnapshot(snapshot)
							: await readFile(state.activePath!, "utf8");
						const compacted = await compactLog(source, promptParts.join(" "), ctx);

						if (!isRedo) await atomicWrite(snapshot, source);
						await atomicWrite(state.activePath!, compacted);
					});

					if (action === "--compact") {
						ctx.ui.notify("Log compacted", "info");
					} else if (action === "--redo-compact") {
						ctx.ui.notify("Compaction redone. Changes since the original compaction were discarded.", "info");
					} else {
						ctx.ui.notify("Compaction undone. Changes since the original compaction were discarded.", "info");
					}
				} catch (error) {
					const message = error instanceof Error ? error.message : String(error);
					ctx.ui.notify(`log failed: ${message}`, "error");
				} finally {
					if (showCompacting) updateIndicator(ctx);
				}
				return;
			}

			const args = trimmedArgs.split(/\s+/).filter(Boolean);
			if (args.includes("--stop")) {
				if (args.length !== 1) {
					ctx.ui.notify("Usage: /log --stop", "error");
					return;
				}
				state = { directoryOverride: state.directoryOverride, seenEntryIds: [] };
				pendingUserInputs = [];
				persistState();
				updateIndicator(ctx);
				return;
			}

			const includePrevious = args.includes("--prev");
			const attach = args.includes("--attach");
			if (args.filter((arg) => arg === "--prev").length > 1 || args.filter((arg) => arg === "--attach").length > 1) {
				ctx.ui.notify("Use --prev and --attach at most once", "error");
				return;
			}

			let previousLimit: number | undefined;
			const consumed = new Set<number>();
			for (let index = 0; index < args.length; index++) {
				if (args[index] === "--prev") {
					consumed.add(index);
					const count = args[index + 1];
					if (count && /^-?\d+$/.test(count)) {
						previousLimit = Number(count);
						consumed.add(index + 1);
						if (!Number.isSafeInteger(previousLimit) || previousLimit < 1) {
							ctx.ui.notify("--prev count must be a positive integer", "error");
							return;
						}
					}
				} else if (args[index] === "--attach") {
					consumed.add(index);
				}
			}
			const names = args.filter((_arg, index) => !consumed.has(index));
			if (
				names.length > 1
				|| names.some((name) => name.startsWith("--"))
				|| (attach && names.length !== 1)
			) {
				ctx.ui.notify("Usage: /log [name] [--prev [count]] | /log --attach <name> [--prev [count]]", "error");
				return;
			}

			let name = names[0] ?? timestampName();
			if (name.endsWith(".md")) name = name.slice(0, -3);
			if (!name || name === "." || name === ".." || basename(name) !== name) {
				ctx.ui.notify("Log name must be a simple filename", "error");
				return;
			}

			const path = join(effectiveLogDir(), `${name}.md`);
			try {
				await enqueue(async () => {
					if (attach) {
						await readFile(path, "utf8");
					} else {
						await mkdir(dirname(path), { recursive: true });
						await writeFile(path, `# ${name}\n\n`, { flag: "wx" });
					}
					const messageEntries = ctx.sessionManager.getBranch()
						.filter((entry) => entry.type === "message");
					const eligibleIds = messageEntries.map((entry) => entry.id);
					let seenEntryIds = eligibleIds;
					if (includePrevious) {
						seenEntryIds = [];
						if (previousLimit !== undefined) {
							const userPositions = messageEntries
								.map((entry, index) => entry.message.role === "user" ? index : -1)
								.filter((index) => index !== -1);
							const firstIncludedUser = userPositions[Math.max(0, userPositions.length - previousLimit)];
							seenEntryIds = firstIncludedUser === undefined
								? eligibleIds
								: messageEntries.slice(0, firstIncludedUser).map((entry) => entry.id);
						}
					}
					state = {
						activePath: path,
						directoryOverride: state.directoryOverride,
						seenEntryIds,
					};
					pendingUserInputs = [];
					if (includePrevious) await sync(ctx);
					else persistState();
				});
			} catch (error) {
				const code = (error as NodeJS.ErrnoException).code;
				const message = code === "EEXIST"
					? `Log already exists; use /log --attach ${name}`
					: code === "ENOENT"
						? `Log does not exist: ${displayPath(path)}`
						: error instanceof Error ? error.message : String(error);
				ctx.ui.notify(message, "error");
				return;
			}

			updateIndicator(ctx);
		},
	});
}

async function loadConfiguredDirectory(
	path: string,
	ctx: ExtensionContext,
): Promise<string | undefined> {
	try {
		const parsed = JSON.parse(await readFile(path, "utf8")) as { directory?: unknown };
		if (typeof parsed.directory !== "string" || !parsed.directory.trim()) {
			throw new Error('expected a non-empty "directory" string');
		}
		return parsed.directory;
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
		const message = error instanceof Error ? error.message : String(error);
		ctx.ui.notify(`Ignoring invalid log config ${path}: ${message}`, "warning");
		return undefined;
	}
}

function snapshotPath(logPath: string): string {
	const canonical = resolve(logPath);
	const key = createHash("sha256").update(canonical).digest("hex");
	return join(SNAPSHOT_DIR, `${key}.md`);
}

async function readSnapshot(path: string): Promise<string> {
	try {
		return await readFile(path, "utf8");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") {
			throw new Error("No compaction to undo or redo");
		}
		throw error;
	}
}

async function atomicWrite(path: string, content: string): Promise<void> {
	await mkdir(dirname(path), { recursive: true });
	const temporary = join(dirname(path), `.${basename(path)}.${randomUUID()}.tmp`);
	try {
		await writeFile(temporary, content, "utf8");
		await rename(temporary, path);
	} catch (error) {
		await unlink(temporary).catch(() => {});
		throw error;
	}
}

async function compactLog(
	markdown: string,
	userInstructions: string,
	ctx: ExtensionCommandContext,
): Promise<string> {
	if (!markdown.trim()) throw new Error("The active log is empty");
	const model = ctx.model;
	if (!model) throw new Error("No active model");
	if (!ctx.modelRegistry.hasConfiguredAuth(model)) {
		throw new Error(`No authentication configured for ${model.provider}/${model.id}`);
	}

	const prompt = [
		COMPACTION_PROMPT,
		userInstructions ? `\nAdditional user instructions:\n${userInstructions}` : "",
		"\n<log>",
		markdown,
		"</log>",
	].join("\n");
	const response = await ctx.modelRegistry.complete(
		model,
		{
			messages: [{
				role: "user",
				content: [{ type: "text", text: prompt }],
				timestamp: Date.now(),
			}],
		},
		{
			reasoningEffort: "high",
			cacheRetention: "none",
			sessionId: uuidv7(),
		},
	);
	let result = response.content
		.filter((block): block is { type: "text"; text: string } => block.type === "text")
		.map((block) => block.text)
		.join("\n")
		.trim();
	const fenced = result.match(/^```(?:markdown|md)?\s*\n([\s\S]*?)\n```$/i);
	if (fenced) result = fenced[1].trim();
	if (!result) throw new Error("The model returned an empty compaction");
	return formatCompactionCallout(normalizeMathDelimiters(result));
}

function formatCompactionCallout(markdown: string): string {
	const lines = markdown.trim().split("\n");
	if (lines[0]?.match(/^#\s+.+$/)) lines.shift();
	while (lines[0]?.trim() === "") lines.shift();
	return `> [!Summary] Compaction\n\n${lines.join("\n")}\n\n---\n\n`;
}

function restoreSkillCommand(text: string): string {
	const match = text.match(
		/^<skill name="([^"]+)" location="[^"]+">\n[\s\S]*?\n<\/skill>(?:\n\n([\s\S]+))?$/,
	);
	if (!match) return text;

	const command = `/skill:${match[1]}`;
	const args = match[2]?.trim();
	return args ? `${command} ${args}` : command;
}

function normalizeMathDelimiters(markdown: string): string {
	let fence: { marker: string; length: number } | undefined;
	let displayMath = false;

	return markdown.split("\n").map((line) => {
		const fenceMatch = line.match(/^\s*(`{3,}|~{3,})/);
		if (fenceMatch) {
			const run = fenceMatch[1];
			if (!fence) {
				fence = { marker: run[0], length: run.length };
			} else if (run[0] === fence.marker && run.length >= fence.length) {
				fence = undefined;
			}
			return line;
		}
		if (fence) return line;

		const trimmedLine = line.trim();
		if (trimmedLine.startsWith("$$")) {
			const delimiters = trimmedLine.match(/\$\$/g)?.length ?? 0;
			if (delimiters % 2 === 1) displayMath = !displayMath;
			return line;
		}
		if (displayMath) return line;

		let result = "";
		let position = 0;
		while (position < line.length) {
			if (line[position] === "`") {
				let endOfRun = position + 1;
				while (line[endOfRun] === "`") endOfRun++;
				const delimiter = line.slice(position, endOfRun);
				const closing = line.indexOf(delimiter, endOfRun);
				if (closing !== -1) {
					result += line.slice(position, closing + delimiter.length);
					position = closing + delimiter.length;
					continue;
				}
			}

			if (
				line[position] === "$"
				&& line[position - 1] !== "\\"
				&& line[position - 1] !== "$"
				&& line[position + 1] !== "$"
			) {
				let closing = position + 1;
				while (closing < line.length) {
					if (
						line[closing] === "$"
						&& line[closing - 1] !== "\\"
						&& line[closing - 1] !== "$"
						&& line[closing + 1] !== "$"
					) break;
					closing++;
				}
				if (closing < line.length) {
					const content = line.slice(position + 1, closing);
					if (content.trim()) {
						result += `$${content.trim()}$`;
						position = closing + 1;
						continue;
					}
				}
			}

			const pair = line.slice(position, position + 2);
			if (pair === "\\(" || pair === "\\)") {
				result += "$";
				position += 2;
			} else if (pair === "\\[" || pair === "\\]") {
				result += "$$";
				position += 2;
			} else {
				result += line[position];
				position++;
			}
		}
		return result;
	}).join("\n");
}

function timestampName(date = new Date()): string {
	const pad = (value: number) => String(value).padStart(2, "0");
	return [
		date.getFullYear(),
		pad(date.getMonth() + 1),
		pad(date.getDate()),
	].join("-") + `-${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
}
