/**
 * Vim motions over the transcript's text. Pure: rows are content rows of the
 * transcript's scroll view, columns are grapheme indexes within a row.
 */

export interface Pos {
	readonly row: number;
	readonly col: number;
}

export interface Line {
	readonly text: string;
	readonly graphemes: readonly string[];
	/** Cell where each grapheme starts. */
	readonly starts: readonly number[];
	/** Cells each grapheme covers. */
	readonly widths: readonly number[];
	readonly width: number;
}

export interface Match {
	readonly start: Pos;
	readonly end: Pos;
	readonly wrapped: boolean;
}

type CharClass = "blank" | "word" | "punct" | "empty";

const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });

export function measureLine(text: string, cellWidth: (grapheme: string) => number): Line {
	const graphemes: string[] = [];
	const starts: number[] = [];
	const widths: number[] = [];
	let cell = 0;
	for (const { segment } of segmenter.segment(text)) {
		const width = cellWidth(segment);
		graphemes.push(segment);
		starts.push(cell);
		widths.push(width);
		cell += width;
	}
	return { text, graphemes, starts, widths, width: cell };
}

/** The transcript as text lines, measured lazily. */
export class Doc {
	readonly #texts: readonly string[];
	readonly #cellWidth: (grapheme: string) => number;
	readonly #lines = new Map<number, Line>();

	constructor(texts: readonly string[], cellWidth: (grapheme: string) => number) {
		this.#texts = texts;
		this.#cellWidth = cellWidth;
	}

	get rows(): number {
		return this.#texts.length;
	}

	text(row: number): string {
		return this.#texts[row] ?? "";
	}

	line(row: number): Line {
		let line = this.#lines.get(row);
		if (!line) {
			line = measureLine(this.text(row), this.#cellWidth);
			this.#lines.set(row, line);
		}
		return line;
	}
}

export function lastRow(doc: Doc): number {
	return Math.max(0, doc.rows - 1);
}

export function lastCol(line: Line): number {
	return Math.max(0, line.graphemes.length - 1);
}

export function clampPos(doc: Doc, pos: Pos): Pos {
	const row = Math.max(0, Math.min(lastRow(doc), pos.row));
	return { row, col: Math.max(0, Math.min(lastCol(doc.line(row)), pos.col)) };
}

export function comparePos(a: Pos, b: Pos): number {
	return a.row - b.row || a.col - b.col;
}

/** Start cell of the grapheme at pos. */
export function cellAt(doc: Doc, pos: Pos): number {
	return doc.line(pos.row).starts[pos.col] ?? 0;
}

/** Grapheme covering the given cell, or the last one when the line is shorter. */
export function colAtCell(line: Line, cell: number): number {
	for (let col = 0; col < line.graphemes.length; col++) {
		if (line.starts[col] + Math.max(1, line.widths[col]) > cell) return col;
	}
	return lastCol(line);
}

export function firstNonBlank(line: Line): number {
	const col = line.graphemes.findIndex((g) => !/^\s+$/u.test(g));
	return col === -1 ? lastCol(line) : col;
}

function classOf(doc: Doc, pos: Pos): CharClass {
	const grapheme = doc.line(pos.row).graphemes[pos.col];
	if (grapheme === undefined) return "empty";
	if (/^\s+$/u.test(grapheme)) return "blank";
	if (/^[\p{L}\p{N}_]/u.test(grapheme)) return "word";
	return "punct";
}

function next(doc: Doc, pos: Pos): Pos | undefined {
	if (pos.col < lastCol(doc.line(pos.row))) return { row: pos.row, col: pos.col + 1 };
	return pos.row < lastRow(doc) ? { row: pos.row + 1, col: 0 } : undefined;
}

function prev(doc: Doc, pos: Pos): Pos | undefined {
	if (pos.col > 0) return { row: pos.row, col: pos.col - 1 };
	return pos.row > 0 ? { row: pos.row - 1, col: lastCol(doc.line(pos.row - 1)) } : undefined;
}

function docEnd(doc: Doc): Pos {
	const row = lastRow(doc);
	return { row, col: lastCol(doc.line(row)) };
}

/** `w`: start of the next word; an empty line counts as a word. */
export function wordForward(doc: Doc, pos: Pos): Pos {
	const start = classOf(doc, pos);
	let q = next(doc, pos);
	if (start === "word" || start === "punct") {
		while (q && q.row === pos.row && classOf(doc, q) === start) q = next(doc, q);
	}
	while (q && classOf(doc, q) === "blank") q = next(doc, q);
	return q ?? docEnd(doc);
}

/** `e`: end of the current or next word. */
export function wordEnd(doc: Doc, pos: Pos): Pos {
	let q = next(doc, pos);
	while (q && (classOf(doc, q) === "blank" || classOf(doc, q) === "empty")) q = next(doc, q);
	if (!q) return docEnd(doc);
	const cls = classOf(doc, q);
	for (let n = next(doc, q); n && n.row === q.row && classOf(doc, n) === cls; n = next(doc, n)) q = n;
	return q;
}

/** `b`: start of the current or previous word; an empty line counts as a word. */
export function wordBackward(doc: Doc, pos: Pos): Pos {
	let q = prev(doc, pos);
	while (q && classOf(doc, q) === "blank") q = prev(doc, q);
	if (!q) return { row: 0, col: 0 };
	const cls = classOf(doc, q);
	if (cls === "empty") return q;
	for (let p = prev(doc, q); p && p.row === q.row && classOf(doc, p) === cls; p = prev(doc, p)) q = p;
	return q;
}

function escapeRegExp(text: string): string {
	return text.replace(/[\\^$.*+?()[\]{}|/]/g, "\\$&");
}

/** Grapheme index containing the UTF-16 offset. */
function colAtOffset(line: Line, offset: number): number {
	let at = 0;
	for (let col = 0; col < line.graphemes.length; col++) {
		at += line.graphemes[col].length;
		if (at > offset) return col;
	}
	return lastCol(line);
}

function matchesIn(doc: Doc, row: number, pattern: RegExp): { start: number; end: number }[] {
	const text = doc.text(row);
	const found: { start: number; end: number }[] = [];
	pattern.lastIndex = 0;
	for (let m = pattern.exec(text); m; m = pattern.exec(text)) {
		const line = doc.line(row);
		found.push({ start: colAtOffset(line, m.index), end: colAtOffset(line, m.index + m[0].length - 1) });
		if (m[0].length === 0) pattern.lastIndex++;
	}
	return found;
}

/**
 * Next match of a literal query strictly after (or before) pos, wrapping around
 * the document. Case-insensitive unless the query has an uppercase letter.
 */
export function search(doc: Doc, query: string, from: Pos, forward: boolean): Match | undefined {
	if (query.length === 0 || doc.rows === 0) return undefined;
	const pattern = new RegExp(escapeRegExp(query), /\p{Lu}/u.test(query) ? "gu" : "giu");
	const rows = doc.rows;
	for (let i = 0; i <= rows; i++) {
		const step = forward ? i : -i;
		const row = (((from.row + step) % rows) + rows) % rows;
		const wrapped = forward ? from.row + i >= rows : from.row - i < 0;
		const found = matchesIn(doc, row, pattern);
		const candidates = forward ? found : found.reverse();
		for (const m of candidates) {
			if (i === 0 && forward && m.start <= from.col) continue;
			if (i === 0 && !forward && m.start >= from.col) continue;
			if (i === rows && forward && m.start > from.col) continue;
			if (i === rows && !forward && m.start < from.col) continue;
			return { start: { row, col: m.start }, end: { row, col: m.end }, wrapped: wrapped || i === rows };
		}
	}
	return undefined;
}
