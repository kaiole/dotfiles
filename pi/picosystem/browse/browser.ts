import {
	cellAt,
	clampPos,
	colAtCell,
	comparePos,
	type Doc,
	firstNonBlank,
	lastCol,
	lastRow,
	type Match,
	type Pos,
	search,
	wordBackward,
	wordEnd,
	wordForward,
} from "./motions.ts";

export type Key =
	| { readonly type: "char"; readonly char: string }
	| { readonly type: "paste"; readonly text: string }
	| { readonly type: "escape" | "ctrlC" | "ctrlU" | "ctrlD" | "enter" | "backspace" };

/** What the browser sees of the viewport when a key arrives. */
export interface Frame {
	readonly doc: Doc;
	readonly top: number;
	readonly height: number;
}

/** Inclusive range of graphemes; linewise ranges cover whole rows. */
export interface Range {
	readonly start: Pos;
	readonly end: Pos;
	readonly linewise: boolean;
}

export interface Result {
	readonly exit?: true;
	/** Copy this range, then show the cursor again. */
	readonly yank?: Range;
	/** Scroll the transcript so this row is at the top. */
	readonly top?: number;
	/** Follow new output again. */
	readonly follow?: true;
}

export type Mode = "normal" | "visual" | "visualLine";

interface Search {
	readonly forward: boolean;
	readonly origin: Pos;
	readonly originTop: number;
	query: string;
	match: Match | undefined;
}

/** Vim-style browse state: cursor, visual selection, counts and search. */
export class Browser {
	mode: Mode = "normal";
	cursor: Pos;
	anchor: Pos;
	message: string | undefined;
	#search: Search | undefined;
	#lastSearch: { readonly query: string; readonly forward: boolean } | undefined;
	/** Cell column that j/k aim for; Infinity after `$`. */
	#want: number;
	#count = "";
	#pendingG: number | undefined;

	constructor(cursor: Pos, doc: Doc) {
		this.cursor = cursor;
		this.anchor = cursor;
		this.#want = cellAt(doc, cursor);
	}

	get searching(): Search | undefined {
		return this.#search;
	}

	/** Count and operator typed so far, for the mode line. */
	get pending(): string {
		return this.#count + (this.#pendingG === undefined ? "" : "g");
	}

	/** What the transcript should highlight now. */
	selection(): Range {
		const match = this.#search?.match;
		if (match && this.mode === "normal") return { start: match.start, end: match.end, linewise: false };
		if (this.mode === "normal") return { start: this.cursor, end: this.cursor, linewise: false };
		const [start, end] = comparePos(this.anchor, this.cursor) <= 0 ? [this.anchor, this.cursor] : [this.cursor, this.anchor];
		return { start, end, linewise: this.mode === "visualLine" };
	}

	handle(key: Key, frame: Frame): Result {
		this.message = undefined;
		this.cursor = clampPos(frame.doc, this.cursor);
		this.anchor = clampPos(frame.doc, this.anchor);
		if (this.#search) return this.#handleSearch(key, frame);
		switch (key.type) {
			case "escape":
			case "ctrlC":
				if (this.#count || this.#pendingG !== undefined) this.#clearPending();
				else this.mode = "normal";
				return {};
			case "ctrlD":
			case "ctrlU":
				return this.#halfPage(key.type === "ctrlD" ? 1 : -1, frame);
			case "char":
				return this.#handleChar(key.char, frame);
			default:
				return {};
		}
	}

	#clearPending(): void {
		this.#count = "";
		this.#pendingG = undefined;
	}

	#takeCount(): number | undefined {
		const count = this.#count ? Number.parseInt(this.#count, 10) : undefined;
		this.#count = "";
		return count;
	}

	#handleChar(char: string, frame: Frame): Result {
		const { doc } = frame;
		if (this.#pendingG !== undefined) {
			const count = this.#pendingG || undefined;
			this.#clearPending();
			if (char === "g") return this.#goToRow((count ?? 1) - 1, frame);
			return {};
		}
		if (/^[1-9]$/.test(char) || (char === "0" && this.#count)) {
			this.#count += char;
			return {};
		}
		const count = this.#takeCount();
		const times = count ?? 1;
		const { row, col } = this.cursor;
		const line = doc.line(row);
		switch (char) {
			case "h":
				return this.#moveTo({ row, col: Math.max(0, col - times) }, frame);
			case "l":
				return this.#moveTo({ row, col: Math.min(lastCol(line), col + times) }, frame);
			case "j":
				return this.#moveVertical(row + times, frame);
			case "k":
				return this.#moveVertical(row - times, frame);
			case "w":
			case "b":
			case "e": {
				const motion = char === "w" ? wordForward : char === "b" ? wordBackward : wordEnd;
				let pos = this.cursor;
				for (let i = 0; i < times; i++) pos = motion(doc, pos);
				return this.#moveTo(pos, frame);
			}
			case "0":
				return this.#moveTo({ row, col: 0 }, frame);
			case "^":
				return this.#moveTo({ row, col: firstNonBlank(line) }, frame);
			case "$": {
				const target = Math.min(lastRow(doc), row + times - 1);
				const result = this.#moveTo({ row: target, col: lastCol(doc.line(target)) }, frame);
				this.#want = Number.POSITIVE_INFINITY;
				return result;
			}
			case "g":
				this.#pendingG = count ?? 0;
				return {};
			case "G":
				if (count !== undefined) return this.#goToRow(count - 1, frame);
				this.#goToRow(lastRow(doc), frame);
				return { top: Math.max(0, doc.rows - frame.height), follow: true };
			case "/":
				this.#search = { forward: true, origin: this.cursor, originTop: frame.top, query: "", match: undefined };
				return {};
			case "n":
			case "N":
				return this.#repeatSearch(char === "n", times, frame);
			case "v":
			case "V": {
				const mode = char === "v" ? "visual" : "visualLine";
				if (this.mode === mode) this.mode = "normal";
				else {
					if (this.mode === "normal") this.anchor = this.cursor;
					this.mode = mode;
				}
				return {};
			}
			case "o":
				if (this.mode !== "normal") [this.anchor, this.cursor] = [this.cursor, this.anchor];
				return this.#reveal(frame);
			case "y": {
				if (this.mode === "normal") return {};
				const range = this.selection();
				this.mode = "normal";
				this.cursor = range.linewise ? { row: range.start.row, col: Math.min(this.cursor.col, this.anchor.col) } : range.start;
				this.cursor = clampPos(doc, this.cursor);
				this.#want = cellAt(doc, this.cursor);
				return { ...this.#reveal(frame), yank: range };
			}
			case "q":
				return { exit: true };
			default:
				return {};
		}
	}

	#moveTo(pos: Pos, frame: Frame): Result {
		this.cursor = clampPos(frame.doc, pos);
		this.#want = cellAt(frame.doc, this.cursor);
		return this.#reveal(frame);
	}

	#moveVertical(row: number, frame: Frame): Result {
		const target = Math.max(0, Math.min(lastRow(frame.doc), row));
		this.cursor = { row: target, col: colAtCell(frame.doc.line(target), this.#want) };
		return this.#reveal(frame);
	}

	#goToRow(row: number, frame: Frame): Result {
		const target = Math.max(0, Math.min(lastRow(frame.doc), row));
		return this.#moveTo({ row: target, col: firstNonBlank(frame.doc.line(target)) }, frame);
	}

	#halfPage(direction: 1 | -1, frame: Frame): Result {
		const amount = this.#takeCount() ?? Math.max(1, Math.floor(frame.height / 2));
		const maxTop = Math.max(0, frame.doc.rows - frame.height);
		const top = Math.max(0, Math.min(maxTop, frame.top + direction * amount));
		const row = Math.max(0, Math.min(lastRow(frame.doc), this.cursor.row + direction * amount));
		this.cursor = { row, col: colAtCell(frame.doc.line(row), this.#want) };
		return this.#reveal({ ...frame, top });
	}

	/** Scroll just enough to show the cursor. */
	#reveal(frame: Frame): Result {
		const { row } = this.cursor;
		if (row < frame.top) return { top: row };
		if (row >= frame.top + frame.height) return { top: row - frame.height + 1 };
		return { top: frame.top };
	}

	#handleSearch(key: Key, frame: Frame): Result {
		const active = this.#search;
		if (!active) return {};
		switch (key.type) {
			case "escape":
			case "ctrlC":
				this.#search = undefined;
				this.cursor = active.origin;
				return { top: active.originTop };
			case "enter": {
				this.#search = undefined;
				if (!active.query) {
					this.cursor = active.origin;
					return { top: active.originTop };
				}
				this.#lastSearch = { query: active.query, forward: active.forward };
				if (!active.match) {
					this.message = `Pattern not found: ${active.query}`;
					this.cursor = active.origin;
					return { top: active.originTop };
				}
				if (active.match.wrapped) this.message = "Search wrapped";
				return this.#moveTo(active.match.start, frame);
			}
			case "backspace":
				if (!active.query) return this.#handleSearch({ type: "escape" }, frame);
				active.query = Array.from(active.query).slice(0, -1).join("");
				break;
			case "ctrlU":
				active.query = "";
				break;
			case "char":
				active.query += key.char;
				break;
			case "paste":
				active.query += key.text.replace(/[\r\n]+/g, " ");
				break;
			default:
				return {};
		}
		active.match = search(frame.doc, active.query, active.origin, active.forward);
		this.cursor = active.match ? active.match.start : active.origin;
		if (!active.match) return { top: active.originTop };
		return this.#reveal(frame);
	}

	#repeatSearch(sameDirection: boolean, times: number, frame: Frame): Result {
		const last = this.#lastSearch;
		if (!last) {
			this.message = "No previous search";
			return {};
		}
		const forward = sameDirection === last.forward;
		let pos = this.cursor;
		let wrapped = false;
		for (let i = 0; i < times; i++) {
			const match = search(frame.doc, last.query, pos, forward);
			if (!match) {
				this.message = `Pattern not found: ${last.query}`;
				return {};
			}
			wrapped ||= match.wrapped;
			pos = match.start;
		}
		if (wrapped) this.message = forward ? "Search hit bottom, continued at top" : "Search hit top, continued at bottom";
		return this.#moveTo(pos, frame);
	}
}
