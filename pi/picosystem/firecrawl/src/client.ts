import { RateLimitBudgetError, SharedRateLimiter, realTiming, type RateLimitOptions, type Timing } from "./rate-limit";

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
	overallTimeoutMs?: number;
	maxAttempts?: number;
	rateLimit?: RateLimitOptions;
	/** Injectable clock/sleeper for offline tests. */
	timing?: Timing;
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

export function retryAfterSeconds(value: string | null, now = Date.now()): number | undefined {
	const text = value?.trim();
	if (!text) return undefined;
	if (/^\d+(?:\.\d+)?$/.test(text)) {
		const seconds = Number(text);
		return Number.isFinite(seconds) ? seconds : undefined;
	}
	// HTTP recipients accept all three HTTP-date forms. The obsolete asctime
	// form has no timezone suffix, but HTTP still defines it as GMT, not local.
	// Restrict syntax so Date.parse cannot reinterpret malformed numbers/dates.
	const standard = /^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d{2} [A-Za-z]{3} \d{4} \d{2}:\d{2}:\d{2} GMT$/i.test(text);
	const obsolete = /^(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), \d{2}-[A-Za-z]{3}-\d{2} \d{2}:\d{2}:\d{2} GMT$/i.test(text);
	const asctime = /^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) [A-Za-z]{3} {1,2}\d{1,2} \d{2}:\d{2}:\d{2} \d{4}$/i.test(text);
	if (!standard && !obsolete && !asctime) return undefined;
	const date = Date.parse(asctime ? `${text} GMT` : text);
	if (!Number.isFinite(date)) return undefined;
	return Math.max(0, Math.ceil((date - now) / 1000));
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
	private readonly overallTimeoutMs: number;
	private readonly maxAttempts: number;
	private readonly rateLimit: RateLimitOptions;
	private readonly timing: Timing;

	constructor(options: FirecrawlClientOptions) {
		this.apiKey = options.apiKey.trim();
		if (!this.apiKey) throw new Error("FIRECRAWL_API_KEY is not set. Add it to the environment that launches Pi, then reload Pi.");

		const apiUrl = (options.apiUrl ?? DEFAULT_API_URL).replace(/\/+$/, "");
		const parsed = new URL(apiUrl);
		if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
			throw new Error("FIRECRAWL_API_URL must use HTTP or HTTPS.");
		}
		if (parsed.username || parsed.password || parsed.search || parsed.hash) {
			throw new Error("FIRECRAWL_API_URL must not contain credentials, a query, or a fragment.");
		}
		this.apiUrl = parsed.toString().replace(/\/+$/, "");
		this.fetchImpl = options.fetchImpl ?? globalThis.fetch;
		this.requestTimeoutMs = options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
		this.overallTimeoutMs = options.overallTimeoutMs ?? 240_000;
		this.maxAttempts = options.maxAttempts ?? 4;
		this.rateLimit = options.rateLimit ?? {};
		this.timing = options.timing ?? realTiming;
		for (const ms of [this.requestTimeoutMs, this.overallTimeoutMs]) {
			if (!Number.isInteger(ms) || ms <= 0 || ms > 2_147_483_647) throw new Error("Firecrawl timeout must be a positive integer within the timer range.");
		}
		if (!Number.isInteger(this.maxAttempts) || this.maxAttempts < 1 || this.maxAttempts > 10) {
			throw new Error("Firecrawl maxAttempts must be an integer from 1 to 10.");
		}
	}

	async search(query: string, options: FirecrawlSearchOptions, signal?: AbortSignal, onProgress?: (message: string) => void): Promise<FirecrawlSearchData> {
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
			onProgress,
		);
	}

	async fetchPage(url: string, onlyMainContent: boolean, signal?: AbortSignal, onProgress?: (message: string) => void): Promise<FirecrawlDocument> {
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
			onProgress,
		);
	}

	private async post<T>(path: string, body: Record<string, unknown>, signal?: AbortSignal, onProgress?: (message: string) => void): Promise<T> {
		const limiter = new SharedRateLimiter(this.apiKey, this.apiUrl, this.rateLimit, this.timing);
		const overall = new AbortController();
		const timer = setTimeout(() => overall.abort(new RateLimitBudgetError("Firecrawl overall time budget exhausted.")), this.overallTimeoutMs);
		const requestSignal = signal ? AbortSignal.any([signal, overall.signal]) : overall.signal;
		const deadline = this.timing.now() + this.overallTimeoutMs;
		let lastThrottle: FirecrawlApiError | undefined;
		try {
			for (let attempt = 1; attempt <= this.maxAttempts; attempt++) {
				await limiter.admit(path, requestSignal, deadline, onProgress);
				onProgress?.(`Sending Firecrawl request (attempt ${attempt}/${this.maxAttempts}).`);
				let cooldownMs = 0;
				try {
					return await this.postOnce<T>(path, body, requestSignal, async (retryAfter, responseSignal) => {
						// Publish on receipt of 429 headers: a stalled error body must not
						// hide the cooldown from other processes. Keep a provisional error
						// for informative overall-budget failure while reading that body.
						lastThrottle = new FirecrawlApiError(`Firecrawl request failed (429): Too Many Requests.${retryAfter !== undefined ? ` Retry after ${retryAfter} seconds.` : ""}`, 429, retryAfter);
						const fallback = Math.min(30_000, 1_000 * 2 ** (attempt - 1));
						cooldownMs = Math.min(Number.MAX_SAFE_INTEGER - this.timing.now() - 60_000, Math.max(
							(retryAfter ?? 0) * 1_000,
							fallback,
						) + Math.floor(this.timing.random() * 250));
						await limiter.cooldown(path, cooldownMs, responseSignal, deadline);
					});
				} catch (error) {
					requestSignal.throwIfAborted();
					if (!(error instanceof FirecrawlApiError) || error.status !== 429) throw error;
					lastThrottle = error;
					if (attempt === this.maxAttempts) {
						throw new FirecrawlApiError(`${error.message} Automatic 429 retry limit exhausted after ${attempt} attempts.`, 429, error.retryAfterSeconds);
					}
					onProgress?.(`Firecrawl returned 429; shared cooldown ${Math.ceil(cooldownMs / 1000)}s before retry ${attempt + 1}/${this.maxAttempts}.`);
				}
			}
			throw new Error("Unreachable Firecrawl retry state.");
		} catch (error) {
			if (signal?.aborted) throw signal.reason;
			if (overall.signal.aborted || error instanceof RateLimitBudgetError) {
				const message = `${error instanceof Error ? error.message : "Firecrawl overall time budget exhausted."}${lastThrottle ? ` Last response: ${lastThrottle.message}` : ""}`;
				if (lastThrottle) throw new FirecrawlApiError(message, 429, lastThrottle.retryAfterSeconds);
				throw new Error(message);
			}
			throw error;
		} finally {
			clearTimeout(timer);
			limiter.close();
		}
	}

	private async postOnce<T>(path: string, body: Record<string, unknown>, signal: AbortSignal, onThrottle: (retryAfter: number | undefined, responseSignal: AbortSignal) => Promise<void>): Promise<T> {
		const timeout = new AbortController();
		const timer = setTimeout(() => timeout.abort(), this.requestTimeoutMs);
		const requestSignal = signal ? AbortSignal.any([signal, timeout.signal]) : timeout.signal;
		try {
			requestSignal.throwIfAborted();
			const response = await this.fetchImpl(`${this.apiUrl}${path}`, {
				method: "POST",
				headers: {
					Accept: "application/json",
					Authorization: `Bearer ${this.apiKey}`,
					"Content-Type": "application/json",
				},
				body: JSON.stringify(body),
				signal: requestSignal,
			});

			if (response.status === 429) {
				await onThrottle(retryAfterSeconds(response.headers.get("retry-after"), this.timing.now()), requestSignal);
			}
			const raw = await response.text();
			requestSignal.throwIfAborted();
			let payload: FirecrawlEnvelope<T> | undefined;
			if (raw) {
				try {
					payload = JSON.parse(raw) as FirecrawlEnvelope<T>;
				} catch {
					if (response.ok) throw new Error("Firecrawl returned a malformed JSON response.");
				}
			}

			if (!response.ok || payload?.success !== true || payload.data === undefined) {
				const retryAfter = retryAfterSeconds(response.headers.get("retry-after"), this.timing.now());
				let message = `Firecrawl request failed (${response.status}): ${errorText(payload, response.statusText || "Unknown error")}`;
				if (retryAfter !== undefined) message += ` Retry after ${retryAfter} seconds.`;
				throw new FirecrawlApiError(message.split(this.apiKey).join("[redacted]"), response.status, retryAfter);
			}
			return payload.data;
		} catch (error) {
			if (signal?.aborted) throw signal.reason;
			if (timeout.signal.aborted) {
				throw new Error(`Firecrawl request timed out after ${Math.round(this.requestTimeoutMs / 1000)} seconds.`);
			}
			throw error;
		} finally {
			clearTimeout(timer);
		}
	}
}

export function createFirecrawlClient(env: NodeJS.ProcessEnv = process.env): FirecrawlClient {
	return new FirecrawlClient({
		apiKey: env.FIRECRAWL_API_KEY ?? "",
		apiUrl: env.FIRECRAWL_API_URL,
		rateLimit: {
			stateDir: env.FIRECRAWL_RATE_LIMIT_DIR,
			teamScope: env.FIRECRAWL_RATE_LIMIT_TEAM,
			searchRpm: env.FIRECRAWL_SEARCH_RPM === undefined ? undefined : Number(env.FIRECRAWL_SEARCH_RPM),
			scrapeRpm: env.FIRECRAWL_SCRAPE_RPM === undefined ? undefined : Number(env.FIRECRAWL_SCRAPE_RPM),
		},
	});
}
