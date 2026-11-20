import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Browser, type Frame, type Key, type Result } from "../browser.ts";
import { Doc } from "../motions.ts";

const lines = Array.from({ length: 40 }, (_, i) => (i % 10 === 0 ? "" : `  line ${i} word`));
lines[5] = "  find me here";
const frame = (top = 30, height = 10): Frame => ({ doc: new Doc(lines, () => 1), top, height });

function keys(b: Browser, input: string, f: Frame = frame()): Result {
	let result: Result = {};
	for (const char of input) {
		const key: Key =
			char === "\x1b" ? { type: "escape" } : char === "\r" ? { type: "enter" } : { type: "char", char };
		result = b.handle(key, f);
	}
	return result;
}

describe("Browser", () => {
	it("moves with counts and keeps the cursor visible", () => {
		const b = new Browser({ row: 39, col: 2 }, frame().doc);
		const result = keys(b, "12k");
		assert.deepEqual(b.cursor, { row: 27, col: 2 });
		assert.equal(result.top, 27);
	});

	it("remembers the column across short lines", () => {
		const b = new Browser({ row: 31, col: 10 }, frame().doc);
		keys(b, "jjjjjjjjj");
		assert.deepEqual(b.cursor, { row: 40 - 1, col: 10 });
		keys(b, "k".repeat(9));
		assert.deepEqual(b.cursor, { row: 30, col: 0 });
		keys(b, "k");
		assert.deepEqual(b.cursor, { row: 29, col: 10 });
	});

	it("gg, 5gg and G", () => {
		const b = new Browser({ row: 35, col: 0 }, frame().doc);
		assert.equal(keys(b, "gg").top, 0);
		assert.deepEqual(b.cursor, { row: 0, col: 0 });
		keys(b, "5gg");
		assert.deepEqual(b.cursor, { row: 4, col: 2 });
		const result = keys(b, "G");
		assert.deepEqual(b.cursor, { row: 39, col: 2 });
		assert.equal(result.follow, true);
	});

	it("0, ^ and $", () => {
		const b = new Browser({ row: 31, col: 5 }, frame().doc);
		keys(b, "0");
		assert.equal(b.cursor.col, 0);
		keys(b, "^");
		assert.equal(b.cursor.col, 2);
		keys(b, "$");
		assert.equal(b.cursor.col, 13);
		keys(b, "j");
		assert.equal(b.cursor.col, 13);
	});

	it("visual yank copies the ordered range and returns to normal", () => {
		const b = new Browser({ row: 32, col: 7 }, frame().doc);
		keys(b, "vkh");
		assert.equal(b.mode, "visual");
		const result = keys(b, "y");
		assert.deepEqual(result.yank, { start: { row: 31, col: 6 }, end: { row: 32, col: 7 }, linewise: false });
		assert.equal(b.mode, "normal");
		assert.deepEqual(b.cursor, { row: 31, col: 6 });
	});

	it("V selects whole lines; o swaps ends; Esc cancels", () => {
		const b = new Browser({ row: 32, col: 7 }, frame().doc);
		keys(b, "Vj");
		assert.deepEqual(b.selection(), { start: { row: 32, col: 7 }, end: { row: 33, col: 7 }, linewise: true });
		keys(b, "o");
		assert.deepEqual(b.cursor, { row: 32, col: 7 });
		keys(b, "\x1b");
		assert.equal(b.mode, "normal");
		assert.equal(keys(b, "y").yank, undefined);
	});

	it("incremental search moves the cursor, Esc restores it, n repeats", () => {
		const b = new Browser({ row: 35, col: 0 }, frame().doc);
		keys(b, "/find");
		assert.equal(b.searching?.query, "find");
		assert.deepEqual(b.cursor, { row: 5, col: 2 });
		assert.deepEqual(b.selection().end, { row: 5, col: 5 });
		assert.equal(keys(b, "\x1b").top, 30);
		assert.deepEqual(b.cursor, { row: 35, col: 0 });

		keys(b, "/word\r");
		assert.equal(b.searching, undefined);
		assert.deepEqual(b.cursor, { row: 35, col: 10 });
		keys(b, "n");
		assert.deepEqual(b.cursor, { row: 36, col: 10 });
		keys(b, "2N");
		assert.deepEqual(b.cursor, { row: 34, col: 10 });
	});

	it("search with no match reports it and stays put", () => {
		const b = new Browser({ row: 35, col: 0 }, frame().doc);
		keys(b, "/nope\r");
		assert.deepEqual(b.cursor, { row: 35, col: 0 });
		assert.equal(b.message, "Pattern not found: nope");
	});

	it("half page moves view and cursor together", () => {
		const b = new Browser({ row: 35, col: 2 }, frame().doc);
		const result = b.handle({ type: "ctrlU" }, frame());
		assert.equal(result.top, 25);
		assert.equal(b.cursor.row, 30);
	});

	it("q exits; Esc and Ctrl+C never do", () => {
		const b = new Browser({ row: 35, col: 0 }, frame().doc);
		assert.equal(b.handle({ type: "escape" }, frame()).exit, undefined);
		assert.equal(b.handle({ type: "ctrlC" }, frame()).exit, undefined);
		assert.equal(keys(b, "q").exit, true);
	});

	it("survives the transcript shrinking under the cursor", () => {
		const b = new Browser({ row: 39, col: 10 }, frame().doc);
		const short: Frame = { doc: new Doc(["one", "two"], () => 1), top: 0, height: 10 };
		keys(b, "h", short);
		assert.deepEqual(b.cursor, { row: 1, col: 1 });
	});
});
