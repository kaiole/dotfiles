import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import { dirname } from "node:path";
import test from "node:test";

import { registerWebTools } from "../src/tools";

function mockPi() {
	const tools = new Map<string, any>();
	const pi = {
		registerTool(definition: any) {
			tools.set(definition.name, definition);
		},
	} as any;
	return { pi, tools };
}

const context = { cwd: process.cwd() } as any;

test("registers web_search and web_fetch", () => {
	const mock = mockPi();
	registerWebTools(mock.pi, () => ({ search: async () => ({}), fetchPage: async () => ({}) }));
	assert.deepEqual([...mock.tools.keys()].sort(), ["web_fetch", "web_search"]);
	assert.match(mock.tools.get("web_search").description, /Firecrawl/);
	assert.match(mock.tools.get("web_fetch").promptGuidelines.join(" "), /untrusted data/);
});

test("web_search returns cited results without fetching each page", async () => {
	const mock = mockPi();
	let received: unknown;
	registerWebTools(mock.pi, () => ({
		async search(query, options) {
			received = { query, options };
			return { web: [{ title: "Example", url: "https://example.com/page", description: "A useful result" }] };
		},
		async fetchPage() { throw new Error("not expected"); },
	}));

	const result = await mock.tools.get("web_search").execute(
		"id",
		{ query: "  example query  ", limit: 3, includeDomains: ["example.com"] },
		undefined,
		undefined,
		context,
	);
	assert.deepEqual(received, { query: "example query", options: { limit: 3, includeDomains: ["example.com"], excludeDomains: undefined } });
	assert.match(result.content[0].text, /untrusted web data/);
	assert.match(result.content[0].text, /https:\/\/example\.com\/page/);
	assert.equal(result.details.resultCount, 1);
});

test("both tools forward cancellation and publish client wait/retry progress", async () => {
	const mock = mockPi();
	const signal = new AbortController().signal;
	let factories = 0;
	registerWebTools(mock.pi, () => {
		factories++;
		return {
			async search(_query, _options, receivedSignal, onProgress) {
				assert.equal(receivedSignal, signal);
				onProgress?.("Waiting for Firecrawl shared cooldown (7s).");
				onProgress?.("Sending Firecrawl request (attempt 2/4).");
				return { web: [] };
			},
			async fetchPage(_url, _mainContent, receivedSignal, onProgress) {
				assert.equal(receivedSignal, signal);
				onProgress?.("Waiting for Firecrawl request pacing (1s).");
				return { markdown: "page" };
			},
		};
	});
	for (const [name, params] of [["web_search", { query: "test" }], ["web_fetch", { url: "https://example.com" }]] as const) {
		const updates: string[] = [];
		const result = await mock.tools.get(name).execute("id", params, signal,
			(update: any) => updates.push(update.content[0].text), context);
		assert.match(updates[1]!, /Waiting for Firecrawl/);
		if (name === "web_search") assert.match(updates[2]!, /attempt 2\/4/);
		assert.match(result.content[0].text, /untrusted web data/);
	}
	assert.equal(factories, 2);
});

test("web_search rejects conflicting domain filters", async () => {
	const mock = mockPi();
	registerWebTools(mock.pi, () => ({ search: async () => ({}), fetchPage: async () => ({}) }));
	await assert.rejects(
		mock.tools.get("web_search").execute("id", { query: "test", includeDomains: ["a.com"], excludeDomains: ["b.com"] }, undefined, undefined, context),
		/cannot both be provided/,
	);
});

test("web_fetch labels content and forwards main-content preference", async () => {
	const mock = mockPi();
	let received: unknown;
	registerWebTools(mock.pi, () => ({
		async search() { return {}; },
		async fetchPage(url, onlyMainContent) {
			received = { url, onlyMainContent };
			return { markdown: "# Page\n\nBody", metadata: { title: "Page", sourceURL: url, statusCode: 200, creditsUsed: 1 } };
		},
	}));

	const result = await mock.tools.get("web_fetch").execute("id", { url: "https://example.com/docs", onlyMainContent: false }, undefined, undefined, context);
	assert.deepEqual(received, { url: "https://example.com/docs", onlyMainContent: false });
	assert.match(result.content[0].text, /Security notice/);
	assert.match(result.content[0].text, /Source URL: https:\/\/example\.com\/docs/);
	assert.match(result.content[0].text, /# Page/);
	assert.equal(result.details.creditsUsed, 1);
});

test("web_fetch truncates oversized pages and preserves the full output", async () => {
	const mock = mockPi();
	registerWebTools(mock.pi, () => ({
		async search() { return {}; },
		async fetchPage() { return { markdown: "\\".repeat(70_000), metadata: { sourceURL: "https://example.com/large" } }; },
	}));

	const result = await mock.tools.get("web_fetch").execute("id", { url: "https://example.com/large" }, undefined, undefined, context);
	try {
		assert.equal(result.details.truncated, true);
		assert.ok(result.details.fullOutputPath);
		assert.ok(Buffer.byteLength(JSON.stringify(result)) < 50_000);
		assert.match(result.content[0].text, /Output truncated/);
	} finally {
		if (result.details.fullOutputPath) await rm(dirname(result.details.fullOutputPath), { recursive: true, force: true });
	}
});

test("web_fetch rejects non-web and credential-bearing URLs", async () => {
	const mock = mockPi();
	registerWebTools(mock.pi, () => ({ search: async () => ({}), fetchPage: async () => ({}) }));
	const tool = mock.tools.get("web_fetch");
	await assert.rejects(tool.execute("id", { url: "file:///etc/passwd" }, undefined, undefined, context), /HTTP and HTTPS/);
	await assert.rejects(tool.execute("id", { url: "https://user:secret@example.com" }, undefined, undefined, context), /credentials embedded/);
});
