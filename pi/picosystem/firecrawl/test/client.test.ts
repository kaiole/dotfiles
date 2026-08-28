import assert from "node:assert/strict";
import test from "node:test";

import { FirecrawlApiError, FirecrawlClient, createFirecrawlClient } from "../src/client";

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
	return new Response(JSON.stringify(body), {
		status: 200,
		headers: { "content-type": "application/json" },
		...init,
	});
}

test("search sends an authenticated v2 request without scraping results", async () => {
	let requestUrl = "";
	let requestInit: RequestInit | undefined;
	const client = new FirecrawlClient({
		apiKey: "fc-test",
		apiUrl: "https://firecrawl.test/",
		fetchImpl: async (input, init) => {
			requestUrl = String(input);
			requestInit = init;
			return jsonResponse({ success: true, data: { web: [{ url: "https://example.com" }] } });
		},
	});

	const result = await client.search("test query", { limit: 3, includeDomains: ["example.com"] });
	assert.equal(result.web?.[0]?.url, "https://example.com");
	assert.equal(requestUrl, "https://firecrawl.test/v2/search");
	assert.equal(new Headers(requestInit?.headers).get("authorization"), "Bearer fc-test");
	const body = JSON.parse(String(requestInit?.body));
	assert.deepEqual(body.sources, ["web"]);
	assert.equal(body.limit, 3);
	assert.deepEqual(body.includeDomains, ["example.com"]);
	assert.equal(body.scrapeOptions, undefined);
});

test("fetchPage requests Markdown and strips base64 images", async () => {
	let body: Record<string, unknown> = {};
	const client = new FirecrawlClient({
		apiKey: "fc-test",
		fetchImpl: async (_input, init) => {
			body = JSON.parse(String(init?.body));
			return jsonResponse({ success: true, data: { markdown: "hello" } });
		},
	});

	const result = await client.fetchPage("https://example.com", false);
	assert.equal(result.markdown, "hello");
	assert.deepEqual(body.formats, ["markdown"]);
	assert.equal(body.onlyMainContent, false);
	assert.equal(body.removeBase64Images, true);
});

test("API failures include status and retry guidance", async () => {
	const client = new FirecrawlClient({
		apiKey: "fc-test",
		fetchImpl: async () => jsonResponse(
			{ success: false, error: "Rate limit exceeded" },
			{ status: 429, headers: { "content-type": "application/json", "retry-after": "7" } },
		),
	});

	await assert.rejects(
		client.search("test", { limit: 1 }),
		(error: unknown) => error instanceof FirecrawlApiError
			&& error.status === 429
			&& error.retryAfterSeconds === 7
			&& /Retry after 7 seconds/.test(error.message),
	);
});

test("missing credentials fail before a network request", () => {
	assert.throws(() => createFirecrawlClient({}), /FIRECRAWL_API_KEY is not set/);
});
