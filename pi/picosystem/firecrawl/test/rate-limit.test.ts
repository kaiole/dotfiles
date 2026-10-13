import assert from "node:assert/strict";
import { chmodSync, linkSync, mkdirSync, readFileSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

import { RateLimitBudgetError, SharedRateLimiter } from "../src/rate-limit";
import { privateStateDir, VirtualTiming } from "./support";

const signal = new AbortController().signal;
const bucket = "/v2/search";

test("cooldowns are monotonic across limiter instances and recovery starts are staggered", async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming();
	const start = timing.now();
	const first = new SharedRateLimiter("offline-key", "https://firecrawl.test", { stateDir }, timing);
	const second = new SharedRateLimiter("offline-key", "https://firecrawl.test", { stateDir }, timing);
	t.after(() => { first.close(); second.close(); });
	await first.cooldown(bucket, 3_000, signal, start + 20_000);
	await second.cooldown(bucket, 1_000, signal, start + 20_000);
	await second.admit(bucket, signal, start + 20_000);
	assert.equal(timing.now() - start, 3_000, "shorter cooldown cannot shorten existing guidance");
	await first.admit(bucket, signal, start + 20_000);
	assert.equal(timing.now() - start, 4_000, "recovery prevents retry herd without configured rpm");
	timing.time = start + 63_000;
	await first.admit(bucket, signal, start + 70_000);
	await second.admit(bucket, signal, start + 70_000);
	assert.equal(timing.now() - start, 63_000, "recovery pacing expires after one minute");
});

test("cooldown extension during sleep is re-read rather than reserving an obsolete start", async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming();
	const start = timing.now();
	const first = new SharedRateLimiter("key", "https://firecrawl.test", { stateDir }, timing);
	const second = new SharedRateLimiter("key", "https://firecrawl.test", { stateDir }, timing);
	t.after(() => { first.close(); second.close(); });
	await first.cooldown(bucket, 2_000, signal, start + 20_000);
	const originalSleep = timing.sleep.bind(timing);
	let extended = false;
	timing.sleep = async (ms, abort) => {
		await originalSleep(ms, abort);
		if (!extended) {
			extended = true;
			await second.cooldown(bucket, 4_000, abort, start + 20_000);
		}
	};
	await first.admit(bucket, signal, start + 20_000);
	assert.equal(timing.now() - start, 5_000);
});

test("credential, service URL, endpoint and team scopes are isolated", async (t) => {
	const stateDir = privateStateDir(t);
	const timing = new VirtualTiming();
	const start = timing.now();
	const make = (key: string, url = "https://firecrawl.test", teamScope?: string) => {
		const limiter = new SharedRateLimiter(key, url, { stateDir, teamScope }, timing);
		t.after(() => limiter.close());
		return limiter;
	};
	await make("key-one").cooldown(bucket, 5_000, signal, start + 20_000);
	await make("key-two").admit(bucket, signal, start + 20_000);
	await make("key-one", "https://other-service.test").admit(bucket, signal, start + 20_000);
	await make("key-one", "https://firecrawl.test/base").admit(bucket, signal, start + 20_000);
	await make("key-one").admit("/v2/scrape", signal, start + 20_000);
	await make("key-one", undefined, "team-a").admit(bucket, signal, start + 20_000);
	assert.equal(timing.now(), start);
	await make("key-one", undefined, "team-a").cooldown(bucket, 2_000, signal, start + 20_000);
	await make("key-one", undefined, "team-b").admit(bucket, signal, start + 20_000);
	assert.equal(timing.now(), start, "different named teams remain independent");
	await make("key-two", undefined, "team-a").admit(bucket, signal, start + 20_000);
	assert.equal(timing.now() - start, 2_000, "explicit same team overrides credential isolation");
});

test("pacing budget failures do not reserve future slots", async (t) => {
	const timing = new VirtualTiming();
	const start = timing.now();
	const limiter = new SharedRateLimiter("key", "https://firecrawl.test", { stateDir: privateStateDir(t), searchRpm: 60 }, timing);
	t.after(() => limiter.close());
	await limiter.admit(bucket, signal, start + 10_000);
	await assert.rejects(limiter.admit(bucket, signal, start + 500), RateLimitBudgetError);
	await limiter.admit(bucket, signal, start + 10_000);
	assert.equal(timing.now() - start, 1_000);
});

test("admission with an already exhausted budget makes no request reservation", async (t) => {
	const timing = new VirtualTiming();
	const limiter = new SharedRateLimiter("key", "https://firecrawl.test", { stateDir: privateStateDir(t), searchRpm: 60 }, timing);
	t.after(() => limiter.close());
	await assert.rejects(limiter.admit(bucket, signal, timing.now()), RateLimitBudgetError);
	await limiter.admit(bucket, signal, timing.now() + 10_000);
	assert.deepEqual(timing.sleeps, []);
});

test("private state stores hashed scopes, never raw credentials or team identifiers", async (t) => {
	const stateDir = privateStateDir(t);
	const credential = "fc-sensitive-offline-test-key";
	const team = "sensitive-offline-team";
	for (const teamScope of [undefined, team]) {
		const limiter = new SharedRateLimiter(credential, "https://firecrawl.test", { stateDir, teamScope }, new VirtualTiming());
		try { await limiter.admit(bucket, signal, Date.UTC(2027, 0, 1)); } finally { limiter.close(); }
	}
	assert.equal(statSync(stateDir).mode & 0o777, 0o700);
	const path = join(stateDir, "rate-limits.sqlite");
	assert.equal(statSync(path).mode & 0o777, 0o600);
	const content = readFileSync(path).toString("utf8");
	assert.ok(!content.includes(credential));
	assert.ok(!content.includes(team));
});

for (const kind of ["public directory", "symlink directory", "public database", "symlink database", "hard-linked database"] as const) {
	test(`refuses unsafe state: ${kind}`, async (t) => {
		const root = privateStateDir(t);
		let stateDir = join(root, "store");
		mkdirSync(stateDir, { mode: 0o700 });
		const dbPath = join(stateDir, "rate-limits.sqlite");
		if (kind === "public directory") chmodSync(stateDir, 0o755);
		if (kind === "symlink directory") { const alias = join(root, "alias"); symlinkSync(stateDir, alias); stateDir = alias; }
		if (kind === "public database") { writeFileSync(dbPath, "", { mode: 0o600 }); chmodSync(dbPath, 0o644); }
		if (kind === "symlink database" || kind === "hard-linked database") {
			const target = join(root, "target");
			writeFileSync(target, "", { mode: 0o600 });
			if (kind === "symlink database") symlinkSync(target, dbPath);
			else linkSync(target, dbPath);
		}
		const limiter = new SharedRateLimiter("key", "https://firecrawl.test", { stateDir }, new VirtualTiming());
		try { await assert.rejects(limiter.admit(bucket, signal, Date.UTC(2027, 0, 1)), /private, user-owned/); }
		finally { limiter.close(); }
	});
}

test("rejects relative state directories so processes cannot silently use different stores", () => {
	assert.throws(() => new SharedRateLimiter("offline-key", "https://firecrawl.test", { stateDir: "relative-cache" }), /must be absolute/);
});

for (const rpm of [0, -1, Number.NaN, Infinity]) {
	test(`rejects invalid rpm ${rpm}`, (t) => {
		const stateDir = privateStateDir(t);
		for (const setting of ["searchRpm", "scrapeRpm"]) {
			assert.throws(() => new SharedRateLimiter("key", "https://firecrawl.test", { stateDir, [setting]: rpm }), /finite positive/);
		}
	});
}
