import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

import { FirecrawlClient } from "../../src/client";

interface Config {
	mode: "client" | "lock";
	stateDir: string;
	apiUrl?: string;
	name?: string;
	maxAttempts?: number;
	searchRpm?: number;
}

const config = JSON.parse(process.argv[2]!) as Config;
const send = (message: Record<string, unknown>) => process.send?.(message);

if (config.mode === "lock") {
	const db = new DatabaseSync(join(config.stateDir, "rate-limits.sqlite"));
	db.exec("PRAGMA busy_timeout = 0; BEGIN IMMEDIATE");
	const future = Date.now() + 86_400_000;
	db.prepare("INSERT INTO buckets VALUES (?, ?, ?, ?)").run("uncommitted-crash-marker", future, future, future);
	// No commit: the parent deliberately kills us while the write lock is held.
	send({ event: "locked", pid: process.pid });
	process.on("message", () => {});
} else {
	process.on("message", async (message) => {
		if (message !== "start") return;
		try {
			const client = new FirecrawlClient({
				apiKey: "fc-shared-offline-process-credential",
				apiUrl: config.apiUrl,
				maxAttempts: config.maxAttempts ?? 1,
				overallTimeoutMs: 15_000,
				requestTimeoutMs: 5_000,
				rateLimit: { stateDir: config.stateDir, searchRpm: config.searchRpm },
			});
			const result = await client.search(config.name ?? "worker", { limit: 1 }, undefined, (text) => send({ event: "progress", text }));
			send({ event: "done", result, pid: process.pid });
			process.disconnect?.();
		} catch (error) {
			send({ event: "failed", message: error instanceof Error ? error.message : String(error) });
			process.exitCode = 1;
			process.disconnect?.();
		}
	});
	send({ event: "ready", pid: process.pid });
}
