import { chmodSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { TestContext } from "node:test";

import type { Timing } from "../src/rate-limit";

/** Never let offline tests touch the real per-user cache. */
export function privateStateDir(t: TestContext): string {
	const directory = mkdtempSync(join(tmpdir(), "pi-firecrawl-test-"));
	chmodSync(directory, 0o700);
	t.after(() => rmSync(directory, { recursive: true, force: true }));
	return directory;
}

export class VirtualTiming implements Timing {
	readonly sleeps: number[] = [];
	constructor(public time = Date.UTC(2026, 0, 1), public jitter = 0) {}
	now(): number { return this.time; }
	random(): number { return this.jitter; }
	async sleep(ms: number, signal: AbortSignal): Promise<void> {
		signal.throwIfAborted();
		this.sleeps.push(ms);
		this.time += ms;
		await Promise.resolve();
		signal.throwIfAborted();
	}
}

export function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
	return new Response(JSON.stringify(body), {
		status: 200,
		headers: { "content-type": "application/json" },
		...init,
	});
}

export function success(): Response {
	return jsonResponse({ success: true, data: { web: [], markdown: "offline" } });
}

export function throttled(retryAfter?: string): Response {
	return jsonResponse({ success: false, error: "Rate limit exceeded" }, {
		status: 429,
		headers: retryAfter === undefined ? {} : { "retry-after": retryAfter },
	});
}
