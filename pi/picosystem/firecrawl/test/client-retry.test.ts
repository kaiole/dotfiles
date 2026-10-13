import assert from "node:assert/strict";
import test from "node:test";

import { FirecrawlApiError, FirecrawlClient, retryAfterSeconds, type FirecrawlClientOptions } from "../src/client";
import { jsonResponse, privateStateDir, success, throttled, VirtualTiming } from "./support";

const search = (client: FirecrawlClient, signal?: AbortSignal, progress?: (message: string) => void) =>
	client.search("offline query", { limit: 1 }, signal, progress);

function clientOptions(stateDir: string, timing: VirtualTiming, fetchImpl: typeof fetch): FirecrawlClientOptions {
	return { apiKey: "fc-offline", apiUrl: "https://firecrawl.test", rateLimit: { stateDir }, timing, fetchImpl };
}

test("Retry-After parsing accepts seconds and HTTP dates, not malformed numeric dates", () => {
	const now = Date.UTC(2026, 0, 1);
	for (const [value, expected] of [
		[null, undefined], ["", undefined], [" 2.5 ", 2.5], ["0", 0], ["-1", undefined],
		["NaN", undefined], ["Infinity", undefined], ["1e3", undefined], ["123garbage", undefined],
		["Thu, 01 Jan 2026 00:00:03 GMT", 3], ["Wed, 31 Dec 2025 23:59:59 GMT", 0],
		["Thursday, 01-Jan-26 00:00:03 GMT", 3], ["Thu Jan  1 00:00:03 2026", 3],
		["Thu, invalid date", undefined], ["9".repeat(400), undefined],
	] as const) assert.equal(retryAfterSeconds(value, now), expected, String(value));
	assert.equal(retryAfterSeconds("Thu, 01 Jan 2026 00:00:03 GMT", now + 100), 3, "round up partial seconds");
});

test("numeric Retry-After retries successfully with bounded jitter and progress", async (t) => {
	const timing = new VirtualTiming(undefined, 0.5);
	const start = timing.now();
	const starts: number[] = [];
	const messages: string[] = [];
	const client = new FirecrawlClient(clientOptions(privateStateDir(t), timing, async () => {
		starts.push(timing.now());
		return starts.length === 1 ? throttled("2") : success();
	}));
	assert.deepEqual(await search(client, undefined, (message) => messages.push(message)), { web: [], markdown: "offline" });
	assert.deepEqual(starts.map((time) => time - start), [0, 2_125]);
	assert.ok(timing.sleeps.every((ms) => ms <= 1_000));
	assert.match(messages.join("\n"), /429; shared cooldown/);
	assert.match(messages.join("\n"), /attempt 2\/4/);
	assert.match(messages.join("\n"), /Waiting for Firecrawl shared cooldown/);
});

for (const [name, header, wait] of [
	["HTTP date", "Thu, 01 Jan 2026 00:00:03 GMT", 3_000],
	["fractional seconds", "1.5", 1_500],
	["missing", undefined, 1_000], ["invalid", "nonsense", 1_000],
	["negative", "-1", 1_000], ["zero", "0", 1_000],
	["past HTTP date", "Wed, 31 Dec 2025 23:59:59 GMT", 1_000],
] as const) {
	test(`${name} Retry-After uses guidance or a nonzero fallback`, async (t) => {
		const timing = new VirtualTiming();
		const start = timing.now();
		let calls = 0;
		const client = new FirecrawlClient(clientOptions(privateStateDir(t), timing, async () => ++calls === 1 ? throttled(header) : success()));
		await search(client);
		assert.equal(calls, 2);
		assert.equal(timing.now() - start, wait);
	});
}

test("repeated 429s use exponential backoff and stop at the attempt limit", async (t) => {
	const timing = new VirtualTiming();
	const start = timing.now();
	const starts: number[] = [];
	const client = new FirecrawlClient({
		...clientOptions(privateStateDir(t), timing, async () => { starts.push(timing.now() - start); return throttled(); }),
		maxAttempts: 4,
	});
	await assert.rejects(search(client), (error: unknown) => error instanceof FirecrawlApiError
		&& error.status === 429 && /retry limit exhausted after 4 attempts/.test(error.message));
	assert.deepEqual(starts, [0, 1_000, 3_000, 7_000]);
	assert.equal(timing.now() - start, 7_000, "last cooldown is published, not waited out");
});

for (const [name, header, budget] of [
	["excessive server guidance", "999999999", 5_000],
	["cooldown equal to remaining budget", "1", 1_000],
	["cooldown greater than remaining budget", undefined, 500],
] as const) {
	test(`${name} fails without another network attempt`, async (t) => {
		const timing = new VirtualTiming();
		let calls = 0;
		const client = new FirecrawlClient({
			...clientOptions(privateStateDir(t), timing, async () => { calls++; return throttled(header); }),
			overallTimeoutMs: budget,
		});
		await assert.rejects(search(client), (error: unknown) => error instanceof FirecrawlApiError
			&& error.status === 429 && /time budget/.test(error.message) && /Last response:.*Rate limit exceeded/.test(error.message));
		assert.equal(calls, 1);
		assert.deepEqual(timing.sleeps, []);
	});
}

test("time budget includes prior attempts and waits", async (t) => {
	const timing = new VirtualTiming();
	const start = timing.now();
	let calls = 0;
	const client = new FirecrawlClient({
		...clientOptions(privateStateDir(t), timing, async () => { calls++; timing.time += 200; return throttled(); }),
		overallTimeoutMs: 2_500,
	});
	await assert.rejects(search(client), /time budget/);
	assert.equal(calls, 2);
	assert.equal(timing.now() - start, 1_400);
});

for (const status of [400, 401, 403, 408, 500, 502, 503]) {
	test(`HTTP ${status} is never automatically retried`, async (t) => {
		const timing = new VirtualTiming();
		let calls = 0;
		const client = new FirecrawlClient(clientOptions(privateStateDir(t), timing, async () => {
			calls++;
			return jsonResponse({ success: false, error: "terminal" }, { status, headers: { "retry-after": "2" } });
		}));
		await assert.rejects(search(client), (error: unknown) => error instanceof FirecrawlApiError && error.status === status);
		assert.equal(calls, 1);
		assert.deepEqual(timing.sleeps, []);
	});
}

for (const [name, response] of [
	["unsuccessful success-status envelope", () => jsonResponse({ success: false, error: "failure" })],
	["missing data", () => jsonResponse({ success: true })],
	["malformed JSON", () => new Response("not JSON")],
] as const) {
	test(`${name} is not retried`, async (t) => {
		let calls = 0;
		const client = new FirecrawlClient(clientOptions(privateStateDir(t), new VirtualTiming(), async () => { calls++; return response(); }));
		await assert.rejects(search(client));
		assert.equal(calls, 1);
	});
}

test("network failure is propagated unchanged without retry", async (t) => {
	const failure = new TypeError("offline network failure");
	let calls = 0;
	const client = new FirecrawlClient(clientOptions(privateStateDir(t), new VirtualTiming(), async () => { calls++; throw failure; }));
	await assert.rejects(search(client), (error: unknown) => error === failure);
	assert.equal(calls, 1);
});

test("separate client instances share cooldown after even a final 429", async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming();
	const start = timing.now();
	const first = new FirecrawlClient({ ...clientOptions(stateDir, timing, async () => throttled("2")), maxAttempts: 1 });
	await assert.rejects(search(first), /retry limit exhausted/);
	const second = new FirecrawlClient(clientOptions(stateDir, timing, async () => {
		assert.equal(timing.now() - start, 2_000);
		return success();
	}));
	await search(second);
});

test("separate client instances share configured pacing, while endpoints use their own rpm", async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming();
	const start = timing.now();
	const options = {
		...clientOptions(stateDir, timing, async () => success()),
		rateLimit: { stateDir, searchRpm: 120, scrapeRpm: 60 },
	};
	await search(new FirecrawlClient(options));
	await search(new FirecrawlClient(options));
	assert.equal(timing.now() - start, 500);
	await new FirecrawlClient(options).fetchPage("https://example.test", true);
	assert.equal(timing.now() - start, 500, "scrape does not wait for search pacing");
	await new FirecrawlClient(options).fetchPage("https://example.test", true);
	assert.equal(timing.now() - start, 1_500);
});

test("team scope coordinates different client credentials", async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming();
	const start = timing.now();
	const options = { ...clientOptions(stateDir, timing, async () => success()), rateLimit: { stateDir, teamScope: "offline-team", searchRpm: 60 } };
	await search(new FirecrawlClient({ ...options, apiKey: "key-one" }));
	await search(new FirecrawlClient({ ...options, apiKey: "key-two" }));
	assert.equal(timing.now() - start, 1_000);
});

test("abort before admission prevents network access", async (t) => {
	const reason = new Error("cancelled before start");
	const signal = AbortSignal.abort(reason);
	let calls = 0;
	const client = new FirecrawlClient(clientOptions(privateStateDir(t), new VirtualTiming(), async () => { calls++; return success(); }));
	await assert.rejects(search(client, signal), (error: unknown) => error === reason);
	assert.equal(calls, 0);
});

test("cancellation during shared cooldown prevents retry and preserves the caller's reason", async (t) => {
	const controller = new AbortController();
	const reason = new Error("cancel cooldown");
	let calls = 0;
	const client = new FirecrawlClient(clientOptions(privateStateDir(t), new VirtualTiming(), async () => { calls++; return throttled("2"); }));
	await assert.rejects(search(client, controller.signal, (message) => {
		if (message.startsWith("Waiting for")) controller.abort(reason);
	}), (error: unknown) => error === reason);
	assert.equal(calls, 1);
});

for (const stage of ["network", "body"] as const) {
	test(`cancellation during ${stage} propagates the reason without retry`, { timeout: 3_000 }, async (t) => {
		const controller = new AbortController();
		const reason = new Error(`cancel ${stage}`);
		let calls = 0;
		const client = new FirecrawlClient(clientOptions(privateStateDir(t), new VirtualTiming(), async (_input, init) => {
			calls++;
			const signal = init!.signal!;
			if (stage === "network") {
				return new Promise<Response>((_resolve, reject) => {
					signal.addEventListener("abort", () => reject(signal.reason), { once: true });
					controller.abort(reason);
				});
			}
			return new Response(new ReadableStream({
				start(stream) {
					stream.enqueue(new TextEncoder().encode('{"success":'));
					signal.addEventListener("abort", () => stream.error(signal.reason), { once: true });
					setImmediate(() => controller.abort(reason));
				},
			}));
		}));
		await assert.rejects(search(client, controller.signal), (error: unknown) => error === reason);
		assert.equal(calls, 1);
	});
}

for (const stage of ["network", "body"] as const) {
	test(`request timeout during ${stage} is not retried`, { timeout: 3_000 }, async (t) => {
		let calls = 0;
		const client = new FirecrawlClient({
			...clientOptions(privateStateDir(t), new VirtualTiming(), async (_input, init) => {
				calls++;
				const signal = init!.signal!;
				if (stage === "network") return new Promise<Response>((_resolve, reject) => {
					signal.addEventListener("abort", () => reject(signal.reason), { once: true });
				});
				return new Response(new ReadableStream({ start(stream) {
					signal.addEventListener("abort", () => stream.error(signal.reason), { once: true });
				} }));
			}),
			requestTimeoutMs: 30,
		});
		await assert.rejects(search(client), /request timed out/);
		assert.equal(calls, 1);
	});
}

for (const stage of ["network", "body"] as const) {
	test(`overall budget aborts a pending ${stage}, without retry`, { timeout: 3_000 }, async (t) => {
		let calls = 0;
		const client = new FirecrawlClient({
			...clientOptions(privateStateDir(t), new VirtualTiming(), async (_input, init) => {
				calls++;
				const signal = init!.signal!;
				if (stage === "network") return new Promise<Response>((_resolve, reject) => {
					signal.addEventListener("abort", () => reject(signal.reason), { once: true });
				});
				return new Response(new ReadableStream({ start(stream) {
					signal.addEventListener("abort", () => stream.error(signal.reason), { once: true });
				} }));
			}),
			requestTimeoutMs: 1_000,
			overallTimeoutMs: 30,
		});
		await assert.rejects(search(client), /overall time budget exhausted/);
		assert.equal(calls, 1);
	});
}

test("exponential fallback is capped at 30 seconds, not unbounded", async (t) => {
	const timing = new VirtualTiming();
	const start = timing.now();
	const starts: number[] = [];
	const client = new FirecrawlClient({
		...clientOptions(privateStateDir(t), timing, async () => { starts.push(timing.now() - start); return throttled(); }),
		maxAttempts: 10,
		overallTimeoutMs: 400_000,
	});
	await assert.rejects(search(client), /retry limit exhausted after 10 attempts/);
	assert.deepEqual(starts, [0, 1_000, 3_000, 7_000, 15_000, 31_000, 61_000, 91_000, 121_000, 151_000]);
});

test("excessive guidance is shared, not clamped to a shorter retry wait", async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming(undefined, 0.9);
	const first = new FirecrawlClient({
		...clientOptions(stateDir, timing, async () => throttled("1" + "0".repeat(305))),
		maxAttempts: 1,
	});
	await assert.rejects(search(first), /retry limit exhausted/);
	let calls = 0;
	const second = new FirecrawlClient({
		...clientOptions(stateDir, timing, async () => { calls++; return success(); }),
		overallTimeoutMs: 60_000,
	});
	await assert.rejects(search(second), /exceeds.*time budget/);
	assert.equal(calls, 0);
	assert.deepEqual(timing.sleeps, []);
});

test("cancelling a pacing waiter does not reserve an extra start slot", async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming();
	const start = timing.now();
	let calls = 0;
	const options = {
		...clientOptions(stateDir, timing, async () => { calls++; return success(); }),
		rateLimit: { stateDir, searchRpm: 120 },
	};
	await search(new FirecrawlClient(options));
	const controller = new AbortController();
	const reason = new Error("cancel pacing");
	await assert.rejects(search(new FirecrawlClient(options), controller.signal, (message) => {
		if (/Waiting for.*request pacing/.test(message)) controller.abort(reason);
	}), (error: unknown) => error === reason);
	assert.equal(calls, 1);
	await search(new FirecrawlClient(options));
	assert.equal(calls, 2);
	assert.equal(timing.now() - start, 500);
});

for (const payload of [
	{ error: "echo fc-offline twice: fc-offline" },
	{ error: { credential: "fc-offline" } },
	{ message: "message contains fc-offline" },
]) {
	test(`API errors redact the credential from ${JSON.stringify(payload)}`, async (t) => {
		const client = new FirecrawlClient(clientOptions(privateStateDir(t), new VirtualTiming(), async () => jsonResponse({ success: false, ...payload }, { status: 403 })));
		await assert.rejects(search(client), (error: unknown) => error instanceof FirecrawlApiError
			&& !error.message.includes("fc-offline") && error.message.includes("[redacted]"));
	});
}

for (const apiUrl of ["ftp://firecrawl.test", "https://user:secret@firecrawl.test", "https://firecrawl.test?secret=1", "https://firecrawl.test#fragment"]) {
	test(`rejects unsafe service URL ${apiUrl}`, (t) => {
		assert.throws(() => new FirecrawlClient({ ...clientOptions(privateStateDir(t), new VirtualTiming(), async () => success()), apiUrl }), /FIRECRAWL_API_URL/);
	});
}

test("simultaneous calls from separate same-process clients share request pacing", { timeout: 5_000 }, async (t) => {
	const stateDir = privateStateDir(t);
	const starts: number[] = [];
	const options: FirecrawlClientOptions = {
		apiKey: "fc-offline-concurrent",
		apiUrl: "https://firecrawl.test",
		rateLimit: { stateDir, searchRpm: 300 },
		fetchImpl: async () => { starts.push(performance.now()); return success(); },
	};
	const clients = Array.from({ length: 3 }, () => new FirecrawlClient(options));
	await Promise.all(clients.map((client) => search(client)));
	assert.equal(starts.length, 3);
	for (let i = 1; i < starts.length; i++) {
		assert.ok(starts[i]! - starts[i - 1]! >= 150, `concurrent request pacing was not enforced: ${starts}`);
	}
});

test("429 headers publish shared cooldown even when its body stalls and times out", { timeout: 3_000 }, async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming();
	const start = timing.now();
	let firstCalls = 0;
	const first = new FirecrawlClient({
		...clientOptions(stateDir, timing, async (_input, init) => {
			firstCalls++;
			const signal = init!.signal!;
			return new Response(new ReadableStream({ start(stream) {
				signal.addEventListener("abort", () => stream.error(signal.reason), { once: true });
			} }), { status: 429, headers: { "retry-after": "2" } });
		}),
		requestTimeoutMs: 30,
	});
	await assert.rejects(search(first), /request timed out/);
	assert.equal(firstCalls, 1, "a body timeout is not retried even if the headers were 429");
	let secondCalls = 0;
	const second = new FirecrawlClient({
		...clientOptions(stateDir, timing, async () => { secondCalls++; return success(); }),
		overallTimeoutMs: 1_000,
	});
	await assert.rejects(search(second), /exceeds.*time budget/);
	assert.equal(secondCalls, 0, "fresh client cannot send inside the known shared cooldown");
	const third = new FirecrawlClient(clientOptions(stateDir, timing, async () => {
		assert.equal(timing.now() - start, 2_000);
		return success();
	}));
	await search(third);
});

test("retry and timeout configuration reject invalid numeric settings", (t) => {
	const options = clientOptions(privateStateDir(t), new VirtualTiming(), async () => success());
	for (const maxAttempts of [0, -1, 1.5, 11, Infinity, Number.NaN]) {
		assert.throws(() => new FirecrawlClient({ ...options, maxAttempts }), /maxAttempts/);
	}
	for (const value of [0, -1, 0.5, 2_147_483_648, Infinity, Number.NaN]) {
		assert.throws(() => new FirecrawlClient({ ...options, requestTimeoutMs: value }), /timeout/);
		assert.throws(() => new FirecrawlClient({ ...options, overallTimeoutMs: value }), /timeout/);
	}
});
