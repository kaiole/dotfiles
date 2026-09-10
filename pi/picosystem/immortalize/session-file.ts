import { link, mkdir, open, unlink } from "node:fs/promises";
import { basename, join } from "node:path";
import type { FileEntry, SessionHeader } from "@earendil-works/pi-coding-agent";

export interface PublishOptions {
	/** Override only for tests or custom session roots. */
	sessionDir: string;
	validate: (path: string) => void;
	now?: () => number;
	random?: () => string;
}

function sessionFilename(header: SessionHeader, suffix?: string): string {
	const timestamp = header.timestamp.replace(/[:.]/g, "-");
	return `${timestamp}_${header.id}${suffix ? `_${suffix}` : ""}.jsonl`;
}

/** Serialize a complete immutable snapshot and publish it without replacing a file. */
export async function publishSessionSnapshot(
	header: SessionHeader,
	entries: readonly FileEntry[],
	options: PublishOptions,
): Promise<string> {
	await mkdir(options.sessionDir, { recursive: true });
	const payload = `${[header, ...entries].map((entry) => JSON.stringify(entry)).join("\n")}\n`;
	const nonce = options.random ?? (() => `${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`);
	const tempPath = join(options.sessionDir, `.${basename(sessionFilename(header))}.${nonce()}.tmp`);
	let tempExists = false;

	try {
		const handle = await open(tempPath, "wx", 0o600);
		tempExists = true;
		try {
			await handle.writeFile(payload, "utf8");
			await handle.sync();
		} finally {
			await handle.close();
		}

		for (let attempt = 0; ; attempt++) {
			const suffix = attempt === 0 ? undefined : `${options.now?.() ?? Date.now()}-${attempt}`;
			const targetPath = join(options.sessionDir, sessionFilename(header, suffix));
			try {
				await link(tempPath, targetPath);
				try {
					options.validate(targetPath);
				} catch (error) {
					await unlink(targetPath).catch(() => {});
					throw error;
				}
				await unlink(tempPath);
				tempExists = false;

				// Best effort: some platforms do not allow opening directories.
				try {
					const directory = await open(options.sessionDir, "r");
					try {
						await directory.sync();
					} finally {
						await directory.close();
					}
				} catch {}
				return targetPath;
			} catch (error) {
				if ((error as NodeJS.ErrnoException).code === "EEXIST") continue;
				throw error;
			}
		}
	} finally {
		if (tempExists) await unlink(tempPath).catch(() => {});
	}
}
