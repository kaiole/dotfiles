import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, afterEach, test } from "node:test";
import extension from "../index.ts";

// `notifi` is a stub on PATH that records its arguments and prints a canned
// outcome; the command itself is tested in scripts/notifi.
const root = mkdtempSync(join(tmpdir(), "pi-notifi-test-"));
const log = join(root, "calls.log");
mkdirSync(join(root, "bin"));
writeFileSync(
	join(root, "bin", "notifi"),
	`#!/bin/sh
echo "$*" >> "${log}"
if [ -n "$NOTIFI_TEST_FAIL" ]; then echo "notify-send is missing" >&2; exit 1; fi
case "$1" in show) echo sent ;; status) echo allowed ;; esac
`,
	{ mode: 0o755 },
);
process.env.PATH = `${join(root, "bin")}:${process.env.PATH}`;

const calls = () => (existsSync(log) ? readFileSync(log, "utf8").trim().split("\n") : []);

function harness(entries: unknown[] = []) {
	const handlers = new Map<string, (event: unknown, ctx: unknown) => Promise<void> | void>();
	let command!: (args: string, ctx: unknown) => Promise<void>;
	const ui: string[] = [];
	const ctx = {
		hasUI: true,
		pending: false,
		hasPendingMessages: () => ctx.pending,
		ui: { notify: (message: string) => ui.push(message) },
		sessionManager: { getEntries: () => entries },
	};
	extension({
		on: (name: string, handler: never) => handlers.set(name, handler),
		registerCommand: (_name: string, options: { handler: typeof command }) => (command = options.handler),
		appendEntry: (customType: string, data: unknown) => entries.push({ type: "custom", customType, data }),
	} as never);
	const fire = (name: string, event: unknown = {}) => handlers.get(name)!(event, ctx);
	return {
		ui,
		ctx,
		fire,
		end: (stopReason = "stop") => fire("agent_end", { messages: [{ role: "assistant", stopReason }] }),
		command: (args: string) => command(args, ctx),
	};
}

afterEach(() => {
	rmSync(log, { force: true });
	delete process.env.NOTIFI_TEST_FAIL;
});
after(() => rmSync(root, { recursive: true, force: true }));

test("the end of a run notifies with the event for its stop reason", async () => {
	const h = harness();
	for (const reason of ["stop", "error", "aborted"]) await h.end(reason);
	assert.deepEqual(calls(), [
		"show --app pi --event finished -v",
		"show --app pi --event error -v",
		"show --app pi --event aborted -v",
	]);
});

test("nothing is sent with queued messages, without a UI, or after /notifi off", async () => {
	const h = harness();
	h.ctx.pending = true;
	await h.end();
	h.ctx.pending = false;
	h.ctx.hasUI = false;
	await h.end();
	h.ctx.hasUI = true;
	await h.command("off");
	await h.end();
	assert.deepEqual(calls(), ["dismiss --app pi"]);
	rmSync(log);

	// The choice is saved in the session and restored by the next pi.
	const entries = [{ type: "custom", customType: "notifi-state", data: { enabled: false } }];
	const resumed = harness(entries);
	await resumed.fire("session_start");
	await resumed.end();
	assert.deepEqual(calls(), []);
	await resumed.command("on");
	await resumed.end();
	assert.equal(calls().length, 1);
});

test("a run starts the agent, and shutdown dismisses it", async () => {
	const h = harness();
	await h.fire("agent_start");
	await h.fire("session_shutdown");
	assert.deepEqual(calls(), ["start --app pi", "dismiss --app pi"]);
});

test("a run that will not notify at its end only dismisses", async () => {
	const h = harness();
	h.ctx.hasUI = false;
	await h.fire("agent_start");
	h.ctx.hasUI = true;
	await h.command("off");
	await h.fire("agent_start");
	assert.deepEqual(calls(), ["dismiss --app pi", "dismiss --app pi", "dismiss --app pi"]);
});

test("/notifi test forces a notification and /notifi status reports delivery", async () => {
	const h = harness();
	await h.command("test");
	await h.command("");
	assert.deepEqual(calls(), ["show --app pi --event finished -v --force", "status"]);
	assert.deepEqual(h.ui, ["notifi test: sent", "notifi is enabled; desktop delivery allowed"]);
});

test("a failing notifi command shows a warning in pi", async () => {
	process.env.NOTIFI_TEST_FAIL = "1";
	const h = harness();
	await h.end();
	assert.deepEqual(h.ui, ["notifi failed: notify-send is missing"]);
});
