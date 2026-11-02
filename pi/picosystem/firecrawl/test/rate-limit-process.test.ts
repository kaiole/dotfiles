import assert from "node:assert/strict";
import { fork, type ChildProcess } from "node:child_process";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import test, { type TestContext } from "node:test";
import { fileURLToPath } from "node:url";

import { FirecrawlClient } from "../src/client";
import { SharedRateLimiter, realTiming } from "../src/rate-limit";
import { privateStateDir, success } from "./support";

interface WorkerMessage { event: string; text?: string; message?: string; pid?: number; result?: unknown }

class Worker {
	readonly child: ChildProcess;
	private messages: WorkerMessage[] = [];
	private stderr = "";
	private failure?: Error;
	private listeners = new Set<() => void>();
	readonly exited: Promise<void>;

	constructor(config: Record<string, unknown>) {
		this.child = fork(fileURLToPath(new URL("./fixtures/rate-limit-worker.ts", import.meta.url)), [JSON.stringify(config)], {
			execArgv: ["--import", "tsx"],
			stdio: ["ignore", "ignore", "pipe", "ipc"],
		});
		this.child.stderr!.on("data", (chunk) => { this.stderr += String(chunk); });
		this.child.on("message", (message) => {
			this.messages.push(message as WorkerMessage);
			if ((message as WorkerMessage).event === "failed") this.failure = new Error((message as WorkerMessage).message);
			for (const notify of this.listeners) notify();
		});
		this.exited = new Promise((resolve) => {
			this.child.on("error", (error) => {
				this.failure = error;
				for (const notify of this.listeners) notify();
				resolve();
			});
			this.child.on("exit", (code, signal) => {
				this.failure ??= new Error(`Worker exited (${code ?? signal}): ${this.stderr}`);
				for (const notify of this.listeners) notify();
				resolve();
			});
		});
	}

	wait(predicate: (message: WorkerMessage) => boolean, timeoutMs = 10_000): Promise<WorkerMessage> {
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => finish(new Error(`Worker IPC timeout. Messages: ${JSON.stringify(this.messages)}. ${this.stderr}`)), timeoutMs);
			const finish = (error?: Error, message?: WorkerMessage) => {
				clearTimeout(timer);
				this.listeners.delete(check);
				if (error) reject(error); else resolve(message!);
			};
			const check = () => {
				const message = this.messages.find(predicate);
				if (message) finish(undefined, message);
				else if (this.failure) finish(this.failure);
			};
			this.listeners.add(check);
			check();
		});
	}

	async start(): Promise<void> {
		await this.wait((message) => message.event === "ready");
		this.child.send("start");
	}

	async stop(): Promise<void> {
		if (this.child.exitCode === null && this.child.signalCode === null) this.child.kill("SIGKILL");
		await this.exited;
	}
}

async function localServer(t: TestContext, handler: (req: IncomingMessage, res: ServerResponse) => void): Promise<string> {
	const server = createServer(handler);
	await new Promise<void>((resolve, reject) => {
		server.once("error", reject);
		server.listen(0, "127.0.0.1", resolve);
	});
	t.after(async () => {
		server.closeAllConnections();
		await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
	});
	const address = server.address();
	assert.ok(address && typeof address !== "string");
	return `http://127.0.0.1:${address.port}`;
}

function respond(res: ServerResponse, status = 200, retryAfter?: string): void {
	res.writeHead(status, { "content-type": "application/json", ...(retryAfter ? { "retry-after": retryAfter } : {}) });
	res.end(JSON.stringify(status === 429 ? { success: false, error: "offline throttle" } : { success: true, data: { web: [] } }));
}

test("two actual OS processes coordinate shared cooldown and stagger recovery requests", { timeout: 20_000 }, async (t) => {
	const stateDir = privateStateDir(t);
	const arrivals: number[] = [];
	const requests: { path?: string; authorization?: string }[] = [];
	const apiUrl = await localServer(t, (req, res) => {
		arrivals.push(performance.now());
		requests.push({ path: req.url, authorization: req.headers.authorization });
		req.resume();
		respond(res, arrivals.length === 1 ? 429 : 200, arrivals.length === 1 ? "1" : undefined);
	});
	const first = new Worker({ mode: "client", stateDir, apiUrl, name: "first", maxAttempts: 2 });
	const second = new Worker({ mode: "client", stateDir, apiUrl, name: "second" });
	try {
		await Promise.all([first.wait((message) => message.event === "ready"), second.wait((message) => message.event === "ready")]);
		assert.notEqual(first.child.pid, second.child.pid);
		assert.notEqual(first.child.pid, process.pid);
		await first.start();
		// This progress notification is emitted only after the cooldown transaction commits.
		await first.wait((message) => message.event === "progress" && /429; shared cooldown/.test(message.text ?? ""));
		await second.start();
		await second.wait((message) => message.event === "progress" && /Waiting for Firecrawl shared cooldown/.test(message.text ?? ""));
		const done = await Promise.all([first.wait((message) => message.event === "done"), second.wait((message) => message.event === "done")]);
		assert.ok(done.every((message) => message.pid !== process.pid));
		assert.equal(arrivals.length, 3, "one throttle and two successful requests");
		assert.ok(arrivals[1]! - arrivals[0]! >= 850, `cooldown was not shared: ${arrivals}`);
		assert.ok(arrivals[2]! - arrivals[1]! >= 850, `recovery requests were not staggered: ${arrivals}`);
		assert.ok(requests.every((request) => request.path === "/v2/search" && request.authorization === "Bearer fc-shared-offline-process-credential"));
	} finally {
		await Promise.all([first.stop(), second.stop()]);
	}
});

test("two actual OS processes coordinate configured pacing without any 429", { timeout: 15_000 }, async (t) => {
	const stateDir = privateStateDir(t);
	const arrivals: number[] = [];
	const apiUrl = await localServer(t, (req, res) => { arrivals.push(performance.now()); req.resume(); respond(res); });
	const first = new Worker({ mode: "client", stateDir, apiUrl, name: "first", searchRpm: 120 });
	const second = new Worker({ mode: "client", stateDir, apiUrl, name: "second", searchRpm: 120 });
	try {
		await Promise.all([first.start(), second.start()]);
		await Promise.all([first.wait((message) => message.event === "done"), second.wait((message) => message.event === "done")]);
		assert.equal(arrivals.length, 2);
		assert.ok(arrivals[1]! - arrivals[0]! >= 400, `cross-process pacing was not enforced: ${arrivals}`);
	} finally {
		await Promise.all([first.stop(), second.stop()]);
	}
});

test("cancellation is prompt under a SQLite write lock, and killing its owner releases the lock", { timeout: 15_000 }, async (t) => {
	const stateDir = privateStateDir(t);
	const apiUrl = "https://firecrawl.test";
	const initializer = new SharedRateLimiter("offline-key", apiUrl, { stateDir });
	try { await initializer.admit("/v2/search", new AbortController().signal, Date.now() + 5_000); }
	finally { initializer.close(); }
	const holder = new Worker({ mode: "lock", stateDir });
	try {
		await holder.wait((message) => message.event === "locked");
		const controller = new AbortController();
		const reason = new Error("cancel while database locked");
		let busySleeps = 0;
		let networkCalls = 0;
		const client = new FirecrawlClient({
			apiKey: "offline-key", apiUrl, rateLimit: { stateDir },
			timing: {
				...realTiming,
				async sleep(ms, signal) {
					busySleeps++;
					assert.ok(ms <= 50, "busy polling does not synchronously wait for the lock");
					controller.abort(reason);
					await realTiming.sleep(ms, signal);
				},
			},
			fetchImpl: async () => { networkCalls++; return success(); },
		});
		const started = performance.now();
		await assert.rejects(client.search("offline", { limit: 1 }, controller.signal), (error: unknown) => error === reason);
		assert.ok(performance.now() - started < 1_000, "cancellation should not wait for SQLite lock ownership");
		assert.ok(busySleeps > 0, "actually encountered the live child process's lock");
		assert.equal(networkCalls, 0);
		await holder.stop(); // SIGKILL while BEGIN IMMEDIATE is still held.
		const recovered = new FirecrawlClient({ apiKey: "offline-key", apiUrl, rateLimit: { stateDir }, overallTimeoutMs: 2_000, fetchImpl: async () => { networkCalls++; return success(); } });
		const recoveryStart = performance.now();
		await recovered.search("after process death", { limit: 1 });
		assert.equal(networkCalls, 1);
		assert.ok(performance.now() - recoveryStart < 1_000, "dead process must not leave a stale coordination lock");
		const db = new DatabaseSync(join(stateDir, "rate-limits.sqlite"));
		try {
			assert.equal(db.prepare("SELECT scope FROM buckets WHERE scope = ?").get("uncommitted-crash-marker"), undefined, "SQLite rolls back the killed writer's transaction");
		} finally { db.close(); }
	} finally { await holder.stop(); }
});
