import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { SessionEntry, SessionHeader } from "@earendil-works/pi-coding-agent";
import { publishSessionSnapshot } from "../session-file.ts";

const header: SessionHeader = {
	type: "session",
	version: 3,
	id: "session-id",
	timestamp: "2025-01-02T03:04:05.678Z",
	cwd: "/project",
};
const entry: SessionEntry = {
	type: "custom",
	id: "leaf",
	parentId: null,
	timestamp: "2025-01-02T03:04:06.000Z",
	customType: "immortalize.anchor",
};

async function temporaryDirectory(): Promise<string> {
	return mkdtemp(join(tmpdir(), "immortalize-"));
}

test("publishes the snapshot as JSONL and removes its temporary file", async (t) => {
	const directory = await temporaryDirectory();
	t.after(() => rm(directory, { recursive: true, force: true }));
	let validated = "";
	const path = await publishSessionSnapshot(header, [entry], {
		sessionDir: directory,
		validate: (candidate) => { validated = candidate; },
		random: () => "nonce",
	});

	assert.equal(validated, path);
	assert.deepEqual((await readFile(path, "utf8")).trim().split("\n").map((line) => JSON.parse(line)), [header, entry]);
	assert.deepEqual(await readdir(directory), ["2025-01-02T03-04-05-678Z_session-id.jsonl"]);
});

test("does not overwrite a colliding session filename", async (t) => {
	const directory = await temporaryDirectory();
	t.after(() => rm(directory, { recursive: true, force: true }));
	const original = join(directory, "2025-01-02T03-04-05-678Z_session-id.jsonl");
	await writeFile(original, "original");

	const path = await publishSessionSnapshot(header, [entry], {
		sessionDir: directory,
		validate: () => {},
		now: () => 42,
		random: () => "nonce",
	});
	assert.equal(await readFile(original, "utf8"), "original");
	assert.match(path, /_42-1\.jsonl$/);
});

test("removes target and temporary file when validation fails", async (t) => {
	const directory = await temporaryDirectory();
	t.after(() => rm(directory, { recursive: true, force: true }));

	await assert.rejects(
		publishSessionSnapshot(header, [entry], {
			sessionDir: directory,
			validate: () => { throw new Error("invalid"); },
			random: () => "nonce",
		}),
		/invalid/,
	);
	assert.deepEqual(await readdir(directory), []);
});
