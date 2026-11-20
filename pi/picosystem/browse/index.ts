import type { ExtensionAPI, ExtensionContext, Theme } from "@earendil-works/pi-coding-agent";
import {
	type Component,
	decodeKittyPrintable,
	isKeyRelease,
	matchesKey,
	stripTerminalSequences,
	type TUI,
	truncateToWidth,
	visibleWidth,
} from "@earendil-works/pi-tui";
import { Browser, type Key, type Range } from "./browser.ts";
import { cellAt, Doc, firstNonBlank, type Pos } from "./motions.ts";
import { Viewport } from "./viewport.ts";

const PASTE_START = "\x1b[200~";
const PASTE_END = "\x1b[201~";

interface Session {
	readonly viewport: Viewport;
	browser: Browser;
	/** Component focused on entry; input passes through while something else has focus. */
	readonly focus: Component | null;
}

function toDoc(lines: readonly string[]): Doc {
	return new Doc(
		lines.map((line) => stripTerminalSequences(line).trimEnd()),
		visibleWidth,
	);
}

function decode(data: string): Key[] {
	if (data.startsWith(PASTE_START)) {
		const text = data.slice(PASTE_START.length);
		return [{ type: "paste", text: text.endsWith(PASTE_END) ? text.slice(0, -PASTE_END.length) : text }];
	}
	if (matchesKey(data, "escape")) return [{ type: "escape" }];
	if (matchesKey(data, "ctrl+c")) return [{ type: "ctrlC" }];
	if (matchesKey(data, "ctrl+u")) return [{ type: "ctrlU" }];
	if (matchesKey(data, "ctrl+d")) return [{ type: "ctrlD" }];
	if (matchesKey(data, "enter")) return [{ type: "enter" }];
	if (matchesKey(data, "backspace")) return [{ type: "backspace" }];
	const printable = decodeKittyPrintable(data);
	if (printable !== undefined) return [{ type: "char", char: printable }];
	if (/[\x00-\x1f\x7f]/.test(data)) return [];
	return Array.from(data, (char) => ({ type: "char", char }));
}

/** Initial cursor: the last one if still on screen, else the last visible non-empty row. */
function initialCursor(doc: Doc, top: number, height: number, last: Pos | undefined): Pos {
	const bottom = Math.min(doc.rows, top + height) - 1;
	if (last && last.row >= top && last.row <= bottom) return last;
	for (let row = bottom; row >= top; row--) {
		const line = doc.line(row);
		if (line.graphemes.length > 0) return { row, col: firstNonBlank(line) };
	}
	return { row: Math.max(0, bottom), col: 0 };
}

export default function browse(pi: ExtensionAPI): void {
	let tui: TUI | undefined;
	let theme: Theme | undefined;
	let session: Session | undefined;
	let lastCursor: Pos | undefined;
	let stopListening: (() => void) | undefined;

	const modeLine: Component = {
		render(width: number): readonly string[] {
			if (!session || !theme) return [];
			const { browser, viewport } = session;
			const search = browser.searching;
			let left: string;
			if (search) left = theme.fg("accent", `/${search.query}`) + theme.inverse(" ");
			else {
				const mode = { normal: "BROWSE", visual: "VISUAL", visualLine: "VISUAL LINE" }[browser.mode];
				left = theme.bold(theme.fg("accent", `-- ${mode} --`));
				if (browser.message) left += `  ${theme.fg("warning", browser.message)}`;
			}
			const rows = viewport.lines().length;
			const right = theme.fg("dim", `${browser.pending}  ${browser.cursor.row + 1}/${rows}  q quit`);
			const gap = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
			return [truncateToWidth(left + " ".repeat(gap) + right, width)];
		},
		invalidate(): void {},
	};

	function show(viewport: Viewport, doc: Doc, range: Range): void {
		const { start, end } = range;
		const endLine = doc.line(end.row);
		if (range.linewise) {
			viewport.select(start.row, 0, end.row, Math.max(1, endLine.width));
			return;
		}
		const endCol = cellAt(doc, end) + Math.max(1, endLine.widths[end.col] ?? 1);
		viewport.select(start.row, cellAt(doc, start), end.row, endCol);
	}

	function exit(): void {
		if (!session) return;
		const { viewport, browser } = session;
		lastCursor = browser.cursor;
		session = undefined;
		viewport.clearSelection();
		// Leave the transcript where it is, but follow output again if it is at the end.
		if (viewport.top >= viewport.lines().length - viewport.height) viewport.scrollTo(viewport.top, true);
		viewport.requestRender();
	}

	function enter(ctx: ExtensionContext): void {
		if (session || !tui) return;
		const viewport = Viewport.of(tui);
		if (!viewport) {
			ctx.ui.notify('browse needs tuiMode "fullscreen"', "warning");
			return;
		}
		if (viewport.lines().length === 0) return;
		// The mode line takes a row from the transcript: lay out with it first, while
		// follow still keeps the end in view, then stop following and place the cursor.
		const origin = { row: 0, col: 0 };
		session = { viewport, browser: new Browser(origin, toDoc([])), focus: viewport.focused() };
		viewport.renderNow();
		viewport.scrollTo(viewport.top, false);
		const doc = toDoc(viewport.lines());
		session.browser = new Browser(initialCursor(doc, viewport.top, viewport.height, lastCursor), doc);
		show(viewport, doc, session.browser.selection());
	}

	function step(current: Session, key: Key): void {
		const { viewport, browser } = current;
		const frame = { doc: toDoc(viewport.lines()), top: viewport.top, height: viewport.height };
		if (frame.doc.rows === 0) return;
		const result = browser.handle(key, frame);
		if (result.exit) {
			exit();
			return;
		}
		if (result.yank) {
			show(viewport, frame.doc, result.yank);
			void viewport.copySelection();
		}
		if (result.follow) viewport.scrollTo(result.top ?? frame.top, true);
		else if (result.top !== undefined && result.top !== frame.top) viewport.scrollTo(result.top, false);
		show(viewport, frame.doc, browser.selection());
	}

	function onInput(data: string): { consume: boolean } | undefined {
		const current = session;
		if (!current) return undefined;
		const { viewport } = current;
		if (viewport.hasOverlay() || viewport.focused() !== current.focus) return undefined;
		if (isKeyRelease(data)) return { consume: true };
		for (const key of decode(data)) {
			if (session !== current) break;
			step(current, key);
		}
		return { consume: true };
	}

	pi.on("session_start", (_event, ctx) => {
		exit();
		lastCursor = undefined;
		stopListening?.();
		if (!ctx.hasUI) return;
		ctx.ui.setWidget(
			"browse",
			(widgetTui, widgetTheme) => {
				tui = widgetTui;
				theme = widgetTheme;
				return modeLine;
			},
			{ placement: "belowEditor" },
		);
		stopListening = ctx.ui.onTerminalInput(onInput);
	});

	pi.on("session_shutdown", () => {
		exit();
		stopListening?.();
		stopListening = undefined;
	});

	pi.registerShortcut("ctrl+b", {
		description: "Browse the transcript with vim keys (fullscreen)",
		handler: (ctx) => enter(ctx),
	});
}
