import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";
import woke from "../index.ts";
import { IdleInhibitor } from "../inhibitor.ts";

function locks(): number {
	return execFileSync("systemd-inhibit", ["--list", "--no-pager", "--no-legend"], { encoding: "utf8" })
		.split("\n").filter(line => /^woke\s/.test(line)).length;
}
async function eventually(check: () => boolean) {
	for (let i = 0; i < 100; i++) {
		if (check()) return;
		await delay(30);
	}
	assert.ok(check(), "condition did not become true");
}

test("real systemd locks: independent holders and idempotent release", async () => {
	const base = locks();
	const errors: string[] = [];
	const a = new IdleInhibitor(e => errors.push(e));
	const b = new IdleInhibitor(e => errors.push(e));
	try {
		await Promise.all([a.acquire(), a.acquire(), b.acquire()]);
		assert.equal(a.active, true);
		assert.equal(locks(), base + 2);
		a.release(); a.release();
		await eventually(() => locks() === base + 1);
		assert.equal(b.active, true);
	} finally { a.release(); b.release(); }
	await eventually(() => locks() === base);
	assert.deepEqual(errors, []);
});

test("lifecycle: retry spans, input prompts, compaction, shutdown", async () => {
	const base = locks();
	const handlers = new Map<string, Function>();
	let idle = false;
	const warnings: string[] = [];
	const ctx = { isIdle: () => idle, hasUI: true, ui: { notify: (s: string) => warnings.push(s) } };
	woke({ on: (name: string, handler: Function) => handlers.set(name, handler), registerCommand() {} } as any);
	const emit = async (name: string) => { await handlers.get(name)?.({}, ctx); };
	try {
		assert.equal(locks(), base);
		await emit("agent_start");
		assert.equal(locks(), base + 1);
		await emit("agent_end");
		assert.equal(locks(), base + 1);
		await emit("agent_start");
		assert.equal(locks(), base + 1);
		await emit("ui_prompt_start");
		await eventually(() => locks() === base);
		await emit("ui_prompt_end");
		assert.equal(locks(), base + 1);
		idle = true;
		await emit("agent_settled");
		await eventually(() => locks() === base);
		for (const outcome of ["session_compact", "session_compact_failed"]) {
			await emit("session_before_compact");
			assert.equal(locks(), base + 1);
			await emit(outcome);
			await eventually(() => locks() === base);
		}
		await emit("agent_start");
		await emit("session_shutdown");
		await emit("ui_prompt_end"); // Late UI completion cannot reopen the lock.
		await eventually(() => locks() === base);
	} finally { await emit("session_shutdown"); }
	assert.deepEqual(warnings, []);
});

test("SIGKILL of the owning process releases its lock", async () => {
	const base = locks();
	const url = new URL("../inhibitor.ts", import.meta.url).href;
	const child = spawn(process.execPath, ["--input-type=module", "-e", `
		import { IdleInhibitor } from ${JSON.stringify(url)};
		const lock = new IdleInhibitor(e => { console.error(e); process.exit(1); });
		await lock.acquire();
		console.log('ready');
	`], { stdio: ["ignore", "pipe", "pipe"] });
	try {
		await Promise.race([once(child.stdout, "data"), delay(5000).then(() => { throw Error("child not ready"); })]);
		assert.equal(locks(), base + 1);
		const exited = once(child, "exit");
		child.kill("SIGKILL");
		await exited;
		await eventually(() => locks() === base);
	} finally { child.kill("SIGKILL"); }
});

test("missing systemd-inhibit reports failure without throwing", async () => {
	const previous = process.env.PATH;
	const errors: string[] = [];
	const lock = new IdleInhibitor(e => errors.push(e));
	try {
		process.env.PATH = "/nonexistent-woke-test";
		await lock.acquire();
		assert.equal(lock.active, false);
		assert.equal(errors.length, 1);
	} finally { process.env.PATH = previous; lock.release(); }
});
