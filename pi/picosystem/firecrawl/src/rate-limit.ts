import { createHash } from "node:crypto";
import { constants, closeSync, lstatSync, mkdirSync, openSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { setTimeout as delay } from "node:timers/promises";

export interface Timing {
	now(): number;
	random(): number;
	sleep(ms: number, signal: AbortSignal): Promise<void>;
}

export const realTiming: Timing = {
	now: Date.now,
	random: Math.random,
	async sleep(ms, signal) { await delay(ms, undefined, { signal }); },
};

export interface RateLimitOptions {
	stateDir?: string;
	/** Non-secret local team identifier, for coordinating different keys on one team. */
	teamScope?: string;
	searchRpm?: number;
	scrapeRpm?: number;
}

export class RateLimitBudgetError extends Error {}

interface BucketState {
	cooldown: number;
	next_start: number;
	recovery_until: number;
}

function isBusy(error: unknown): boolean {
	return !!error && typeof error === "object" && "errcode" in error
		&& (error.errcode === 5 || error.errcode === 6); // SQLITE_BUSY / SQLITE_LOCKED
}

function ensurePrivateStore(directory: string): string {
	mkdirSync(directory, { recursive: true, mode: 0o700 });
	const stat = lstatSync(directory);
	if (!stat.isDirectory() || (stat.mode & 0o077) !== 0
		|| (process.getuid && stat.uid !== process.getuid())) {
		throw new Error("Firecrawl rate-limit directory must be a private, user-owned directory (mode 0700), not a symlink.");
	}
	const path = join(directory, "rate-limits.sqlite");
	try {
		const fd = openSync(path, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | constants.O_NOFOLLOW, 0o600);
		closeSync(fd);
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
	}
	const file = lstatSync(path);
	if (!file.isFile() || file.nlink !== 1 || (file.mode & 0o077) !== 0
		|| (process.getuid && file.uid !== process.getuid())) {
		throw new Error("Firecrawl rate-limit database must be a private, user-owned regular file (mode 0600).");
	}
	return path;
}

/** SQLite owns crash recovery and lock ownership. Transactions never contain an await,
 * network request, or sleep. Busy writers are polled asynchronously with cancellation.
 * Waiting calls don't reserve slots; cancellation/death can waste at most one start gap.
 */
export class SharedRateLimiter {
	private db?: DatabaseSync;
	private readonly scope: string;
	private readonly directory: string;

	constructor(apiKey: string, apiUrl: string, private readonly options: RateLimitOptions = {}, private readonly timing: Timing = realTiming) {
		const cacheHome = process.env.XDG_CACHE_HOME;
		this.directory = options.stateDir ?? join(cacheHome && isAbsolute(cacheHome) ? cacheHome : join(homedir(), ".cache"), "pi", "firecrawl");
		if (!isAbsolute(this.directory)) {
			throw new Error("FIRECRAWL_RATE_LIMIT_DIR must be absolute so processes with different working directories coordinate.");
		}
		this.scope = createHash("sha256").update(JSON.stringify([
			apiUrl, options.teamScope ? ["team", options.teamScope] : ["key", apiKey],
		])).digest("hex");
		for (const rpm of [options.searchRpm, options.scrapeRpm]) {
			if (rpm !== undefined && (!Number.isFinite(rpm) || rpm <= 0)) {
				throw new Error("Firecrawl requests-per-minute settings must be finite positive numbers.");
			}
		}
	}

	private database(): DatabaseSync {
		if (!this.db) {
			this.db = new DatabaseSync(ensurePrivateStore(this.directory));
			// No synchronous busy timeout: retry outside the transaction instead.
			this.db.exec("PRAGMA busy_timeout = 0");
		}
		this.db.exec(`CREATE TABLE IF NOT EXISTS buckets (
			scope TEXT PRIMARY KEY, cooldown REAL NOT NULL, next_start REAL NOT NULL,
			recovery_until REAL NOT NULL
		)`);
		return this.db;
	}

	private async transaction<T>(signal: AbortSignal, deadline: number, action: (db: DatabaseSync) => T): Promise<T> {
		for (;;) {
			signal.throwIfAborted();
			if (this.timing.now() >= deadline) throw new RateLimitBudgetError("Firecrawl overall time budget exhausted while coordinating requests.");
			let db: DatabaseSync | undefined;
			let begun = false;
			try {
				db = this.database();
				db.exec("BEGIN IMMEDIATE");
				begun = true;
				const result = action(db);
				db.exec("COMMIT");
				return result;
			} catch (error) {
				if (begun) db!.exec("ROLLBACK");
				if (!isBusy(error)) throw error;
				await this.timing.sleep(Math.min(25 + this.timing.random() * 25, deadline - this.timing.now()), signal);
			}
		}
	}

	async admit(bucket: string, signal: AbortSignal, deadline: number, onProgress?: (message: string) => void): Promise<void> {
		const key = `${this.scope}:${bucket}`;
		let announcedUntil = 0;
		let announcedCooldown = false;
		for (;;) {
			const wait = await this.transaction(signal, deadline, (db) => {
				const now = this.timing.now();
				// Retain only active cooldown/pacing state, including rotated credentials.
				db.prepare("DELETE FROM buckets WHERE cooldown <= ? AND next_start <= ? AND recovery_until <= ?").run(now, now, now);
				const state = db.prepare("SELECT cooldown, next_start, recovery_until FROM buckets WHERE scope = ?").get(key) as unknown as BucketState | undefined;
				const until = Math.max(state?.cooldown ?? 0, state?.next_start ?? 0);
				if (until > now) return { ms: until - now, cooldown: (state?.cooldown ?? 0) > now };
				const rpm = bucket === "/v2/search" ? this.options.searchRpm : this.options.scrapeRpm;
				// After throttling, stagger starts for one minute instead of a retry herd.
				const recovering = (state?.recovery_until ?? 0) > now;
				const gap = Math.max(rpm ? 60_000 / rpm : 0, recovering ? 1_000 + this.timing.random() * 250 : 0);
				db.prepare(`INSERT INTO buckets VALUES (?, ?, ?, ?) ON CONFLICT(scope) DO UPDATE SET
					cooldown = excluded.cooldown, next_start = excluded.next_start, recovery_until = excluded.recovery_until`)
					.run(key, state?.cooldown ?? 0, now + gap, state?.recovery_until ?? 0);
				return { ms: 0, cooldown: false };
			});
			if (!wait.ms) { signal.throwIfAborted(); return; }
			const until = this.timing.now() + wait.ms;
			if (!announcedUntil || wait.cooldown !== announcedCooldown || until > announcedUntil + 1_000) {
				onProgress?.(`Waiting for Firecrawl ${wait.cooldown ? "shared cooldown" : "request pacing"} (${Math.ceil(wait.ms / 1000)}s).`);
				announcedUntil = until;
				announcedCooldown = wait.cooldown;
			}
			if (wait.ms >= deadline - this.timing.now()) {
				throw new RateLimitBudgetError(`Firecrawl shared cooldown/pacing (${Math.ceil(wait.ms / 1000)}s) exceeds the remaining overall time budget (${Math.max(0, Math.floor((deadline - this.timing.now()) / 1000))}s).`);
			}
			// Re-read state periodically: another process may extend the cooldown.
			await this.timing.sleep(Math.min(wait.ms, 1_000), signal);
		}
	}

	async cooldown(bucket: string, delayMs: number, signal: AbortSignal, deadline: number): Promise<void> {
		await this.transaction(signal, deadline, (db) => {
			const until = this.timing.now() + delayMs;
			db.prepare(`INSERT INTO buckets VALUES (?, ?, 0, ?) ON CONFLICT(scope) DO UPDATE SET
				cooldown = max(cooldown, excluded.cooldown), recovery_until = max(recovery_until, excluded.recovery_until)`)
				.run(`${this.scope}:${bucket}`, until, until + 60_000);
		});
	}

	close(): void {
		this.db?.close();
		this.db = undefined;
	}
}
