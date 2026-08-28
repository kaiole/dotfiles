const DEFAULT_API_URL = "https://api.firecrawl.dev";
const DEFAULT_REQUEST_TIMEOUT_MS = 125_000;

export interface FirecrawlDocumentMetadata {
	title?: string;
	description?: string;
	url?: string;
	sourceURL?: string;
	statusCode?: number;
	contentType?: string;
	creditsUsed?: number;
	[key: string]: unknown;
}

export interface FirecrawlDocument {
	markdown?: string;
	summary?: string;
	warning?: string;
	metadata?: FirecrawlDocumentMetadata;
}

export interface FirecrawlWebResult {
	url?: string;
	title?: string;
	description?: string;
	position?: number;
	markdown?: string;
	metadata?: FirecrawlDocumentMetadata;
}

export interface FirecrawlSearchData {
	web?: FirecrawlWebResult[];
}

export interface FirecrawlSearchOptions {
	limit: number;
	includeDomains?: string[];
	excludeDomains?: string[];
}

export interface FirecrawlClientOptions {
	apiKey: string;
	apiUrl?: string;
	fetchImpl?: typeof fetch;
	requestTimeoutMs?: number;
}

interface FirecrawlEnvelope<T> {
	success?: boolean;
	data?: T;
	error?: unknown;
	message?: unknown;
	code?: unknown;
}

function errorText(payload: FirecrawlEnvelope<unknown> | undefined, fallback: string): string {
	for (const candidate of [payload?.error, payload?.message]) {
		if (typeof candidate === "string" && candidate.trim()) return candidate.trim();
		if (candidate && typeof candidate === "object") {
			try {
				return JSON.stringify(candidate);
			} catch {
				// Fall through to the HTTP status text.
			}
		}
	}
	return fallback;
}

function retryAfterSeconds(value: string | null): number | undefined {
	if (!value) return undefined;
	const seconds = Number(value);
	if (Number.isFinite(seconds) && seconds >= 0) return seconds;
	const date = new Date(value);
	if (Number.isNaN(date.getTime())) return undefined;
	return Math.max(0, Math.ceil((date.getTime() - Date.now()) / 1000));
}

export class FirecrawlApiError extends Error {
	readonly status: number;
	readonly retryAfterSeconds?: number;

	constructor(message: string, status: number, retryAfter?: number) {
		super(message);
		this.name = "FirecrawlApiError";
		this.status = status;
		this.retryAfterSeconds = retryAfter;
	}
}

export class FirecrawlClient {
	private readonly apiKey: string;
	private readonly apiUrl: string;
	private readonly fetchImpl: typeof fetch;
	private readonly requestTimeoutMs: number;

	constructor(options: FirecrawlClientOptions) {
		this.apiKey = options.apiKey.trim();
		if (!this.apiKey) throw new Error("FIRECRAWL_API_KEY is not set. Add it to the environment that launches Pi, then reload Pi.");

		const apiUrl = (options.apiUrl ?? DEFAULT_API_URL).replace(/\/+$/, "");
		const parsed = new URL(apiUrl);
		if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
			throw new Error("FIRECRAWL_API_URL must use HTTP or HTTPS.");
		}
		this.apiUrl = parsed.toString().replace(/\/+$/, "");
		this.fetchImpl = options.fetchImpl ?? globalThis.fetch;
		this.requestTimeoutMs = options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
	}

	async search(query: string, options: FirecrawlSearchOptions, signal?: AbortSignal): Promise<FirecrawlSearchData> {
		return this.post<FirecrawlSearchData>(
			"/v2/search",
			{
				query,
				sources: ["web"],
				limit: options.limit,
				highlights: true,
				timeout: Math.max(1_000, Math.min(120_000, this.requestTimeoutMs - 5_000)),
				...(options.includeDomains?.length ? { includeDomains: options.includeDomains } : {}),
				...(options.excludeDomains?.length ? { excludeDomains: options.excludeDomains } : {}),
			},
			signal,
		);
	}

	async fetchPage(url: string, onlyMainContent: boolean, signal?: AbortSignal): Promise<FirecrawlDocument> {
		return this.post<FirecrawlDocument>(
			"/v2/scrape",
			{
				url,
				formats: ["markdown"],
				onlyMainContent,
				removeBase64Images: true,
				timeout: Math.max(1_000, Math.min(120_000, this.requestTimeoutMs - 5_000)),
			},
			signal,
		);
	}

	private async post<T>(path: string, body: Record<string, unknown>, signal?: AbortSignal): Promise<T> {
		const timeoutSignal = AbortSignal.timeout(this.requestTimeoutMs);
		const requestSignal = signal ? AbortSignal.any([signal, timeoutSignal]) : timeoutSignal;
		let response: Response;
		try {
			response = await this.fetchImpl(`${this.apiUrl}${path}`, {
				method: "POST",
				headers: {
					Accept: "application/json",
					Authorization: `Bearer ${this.apiKey}`,
					"Content-Type": "application/json",
				},
				body: JSON.stringify(body),
				signal: requestSignal,
			});
		} catch (error) {
			if (timeoutSignal.aborted && !signal?.aborted) {
				throw new Error(`Firecrawl request timed out after ${Math.round(this.requestTimeoutMs / 1000)} seconds.`);
			}
			throw error;
		}

		const raw = await response.text();
		let payload: FirecrawlEnvelope<T> | undefined;
		if (raw) {
			try {
				payload = JSON.parse(raw) as FirecrawlEnvelope<T>;
			} catch {
				if (response.ok) throw new Error("Firecrawl returned a malformed JSON response.");
			}
		}

		if (!response.ok || payload?.success !== true || payload.data === undefined) {
			const retryAfter = retryAfterSeconds(response.headers.get("retry-after"));
			let message = `Firecrawl request failed (${response.status}): ${errorText(payload, response.statusText || "Unknown error")}`;
			if (retryAfter !== undefined) message += ` Retry after ${retryAfter} seconds.`;
			throw new FirecrawlApiError(message, response.status, retryAfter);
		}
		return payload.data;
	}
}

export function createFirecrawlClient(env: NodeJS.ProcessEnv = process.env): FirecrawlClient {
	return new FirecrawlClient({
		apiKey: env.FIRECRAWL_API_KEY ?? "",
		apiUrl: env.FIRECRAWL_API_URL,
	});
}
