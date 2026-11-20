import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Doc, search, wordBackward, wordEnd, wordForward, type Pos } from "../motions.ts";

const width = (g: string): number => (/\p{Script=Han}/u.test(g) ? 2 : 1);
const doc = (...lines: string[]): Doc => new Doc(lines, width);
const walk = (d: Doc, motion: (d: Doc, p: Pos) => Pos, from: Pos, n: number): Pos[] => {
	const out: Pos[] = [];
	let p = from;
	for (let i = 0; i < n; i++) out.push((p = motion(d, p)));
	return out;
};

describe("word motions", () => {
	const d = doc("foo.bar  baz", "", "  qux_1 (x)");

	it("w stops at word/punct starts and empty lines", () => {
		assert.deepEqual(walk(d, wordForward, { row: 0, col: 0 }, 6), [
			{ row: 0, col: 3 },
			{ row: 0, col: 4 },
			{ row: 0, col: 9 },
			{ row: 1, col: 0 },
			{ row: 2, col: 2 },
			{ row: 2, col: 8 },
		]);
	});

	it("e skips empty lines and lands on word ends", () => {
		assert.deepEqual(walk(d, wordEnd, { row: 0, col: 0 }, 5), [
			{ row: 0, col: 2 },
			{ row: 0, col: 3 },
			{ row: 0, col: 6 },
			{ row: 0, col: 11 },
			{ row: 2, col: 6 },
		]);
	});

	it("b is w backwards", () => {
		assert.deepEqual(walk(d, wordBackward, { row: 2, col: 8 }, 6), [
			{ row: 2, col: 2 },
			{ row: 1, col: 0 },
			{ row: 0, col: 9 },
			{ row: 0, col: 4 },
			{ row: 0, col: 3 },
			{ row: 0, col: 0 },
		]);
	});

	it("stops at document ends", () => {
		assert.deepEqual(wordForward(d, { row: 2, col: 10 }), { row: 2, col: 10 });
		assert.deepEqual(wordBackward(d, { row: 0, col: 0 }), { row: 0, col: 0 });
	});
});

describe("measuring", () => {
	it("maps graphemes to cells", () => {
		const line = doc("a漢b👍🏽c").line(0);
		assert.deepEqual(line.graphemes, ["a", "漢", "b", "👍🏽", "c"]);
		assert.deepEqual(line.starts, [0, 1, 3, 4, 5]);
	});
});

describe("search", () => {
	const d = doc("Alpha beta", "gamma alpha", "beta");

	it("finds the next match after the cursor, smartcase", () => {
		assert.deepEqual(search(d, "alpha", { row: 0, col: 0 }, true)?.start, { row: 1, col: 6 });
		assert.deepEqual(search(d, "Alpha", { row: 0, col: 0 }, true)?.start, { row: 0, col: 0 });
	});

	it("wraps both ways and reports it", () => {
		const fwd = search(d, "alpha", { row: 1, col: 6 }, true);
		assert.deepEqual(fwd?.start, { row: 0, col: 0 });
		assert.equal(fwd?.wrapped, true);
		const back = search(d, "beta", { row: 0, col: 6 }, false);
		assert.deepEqual(back?.start, { row: 2, col: 0 });
		assert.equal(back?.wrapped, true);
	});

	it("matches a lone occurrence at the cursor after wrapping", () => {
		assert.deepEqual(search(d, "gamma", { row: 1, col: 0 }, true)?.start, { row: 1, col: 0 });
	});

	it("treats the query literally and returns the match end", () => {
		const m = search(doc("a.b (c) a*b"), "(c)", { row: 0, col: 0 }, true);
		assert.deepEqual([m?.start, m?.end], [{ row: 0, col: 4 }, { row: 0, col: 6 }]);
		assert.equal(search(doc("abc"), "a.c", { row: 0, col: 0 }, true), undefined);
	});
});
