import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
	formatSize,
	truncateHead,
	withFileMutationQueue,
} from "@earendil-works/pi-coding-agent";

const MAX_OUTPUT_BYTES = 40_000;
const MAX_SERIALIZED_TEXT_BYTES = 36_000;
const MAX_OUTPUT_LINES = 1_900;

export interface BoundedOutputDetails {
	truncated: boolean;
	fullOutputPath?: string;
	outputBytes: number;
	totalBytes: number;
	outputLines: number;
	totalLines: number;
}

export async function boundWebOutput(text: string): Promise<{ text: string; details: BoundedOutputDetails }> {
	let maxBytes = MAX_OUTPUT_BYTES;
	let truncation = truncateHead(text, { maxBytes, maxLines: MAX_OUTPUT_LINES });
	while (Buffer.byteLength(JSON.stringify(truncation.content)) > MAX_SERIALIZED_TEXT_BYTES && maxBytes > 1_000) {
		maxBytes = Math.max(1_000, Math.floor(maxBytes * 0.75));
		truncation = truncateHead(text, { maxBytes, maxLines: MAX_OUTPUT_LINES });
	}

	const details: BoundedOutputDetails = {
		truncated: truncation.truncated,
		outputBytes: truncation.outputBytes,
		totalBytes: truncation.totalBytes,
		outputLines: truncation.outputLines,
		totalLines: truncation.totalLines,
	};
	if (!truncation.truncated) return { text: truncation.content, details };

	const tempDir = await mkdtemp(join(tmpdir(), "pi-firecrawl-"));
	const fullOutputPath = join(tempDir, "web-content.md");
	await withFileMutationQueue(fullOutputPath, () => writeFile(fullOutputPath, text, "utf8"));
	details.fullOutputPath = fullOutputPath;

	const notice = [
		"",
		`[Output truncated: showing ${truncation.outputLines} of ${truncation.totalLines} lines`,
		`(${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)}).`,
		`Full output saved to: ${fullOutputPath}]`,
	].join(" ");
	return { text: `${truncation.content}\n${notice}`, details };
}
