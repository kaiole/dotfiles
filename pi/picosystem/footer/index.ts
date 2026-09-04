import { readFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
	return `${Math.round(count / 1000000)}M`;
}

function displayPath(cwd: string): string {
	const home = process.env.HOME || process.env.USERPROFILE;
	return home && cwd.startsWith(home) ? `~${cwd.slice(home.length)}` : cwd;
}

type UsageLimit = { reset: Date; percentUsed: number };

type UsageLimits = { fiveHour?: UsageLimit; weekly?: UsageLimit };

function padBetween(left: string, right: string, width: number): string {
	const leftWidth = visibleWidth(left);
	const rightWidth = visibleWidth(right);

	if (leftWidth + rightWidth >= width) {
		const availableForRight = Math.max(0, width - leftWidth - 1);
		const truncatedRight = availableForRight > 0 ? truncateToWidth(right, availableForRight, "") : "";
		return truncateToWidth(`${left} ${truncatedRight}`, width, "");
	}

	return `${left}${" ".repeat(width - leftWidth - rightWidth)}${right}`;
}

function parseNumber(value: string | undefined): number | undefined {
	if (!value) return undefined;
	const num = Number(value.replace(/,/g, ""));
	return Number.isFinite(num) ? num : undefined;
}

function parseReset(value: string | undefined): Date | undefined {
	if (!value) return undefined;
	const trimmed = value.trim();
	const unix = Number(trimmed);
	if (Number.isFinite(unix)) return new Date(unix > 10_000_000_000 ? unix : unix * 1000);

	let ms = 0;
	for (const match of trimmed.matchAll(/(\d+(?:\.\d+)?)\s*(ms|s|sec|secs|m|min|mins|h|hr|hrs|d|day|days)/gi)) {
		const amount = Number(match[1]);
		const unit = match[2].toLowerCase();
		if (unit === "ms") ms += amount;
		else if (unit.startsWith("s")) ms += amount * 1000;
		else if (unit.startsWith("m")) ms += amount * 60_000;
		else if (unit.startsWith("h")) ms += amount * 3_600_000;
		else if (unit.startsWith("d")) ms += amount * 86_400_000;
	}
	if (ms) return new Date(Date.now() + ms);

	const date = new Date(trimmed);
	return Number.isNaN(date.getTime()) ? undefined : date;
}

function findHeader(headers: Record<string, string>, prefix: "limit" | "remaining" | "reset", patterns: RegExp[]): string | undefined {
	const entries = Object.entries(headers).map(([key, value]) => [key.toLowerCase(), value] as const);
	return entries.find(([key]) => key.includes("ratelimit") && key.includes(prefix) && patterns.some((pattern) => pattern.test(key)))?.[1];
}

function parseUsageLimit(headers: Record<string, string>, patterns: RegExp[]): UsageLimit | undefined {
	const limit = parseNumber(findHeader(headers, "limit", patterns));
	const remaining = parseNumber(findHeader(headers, "remaining", patterns));
	const reset = parseReset(findHeader(headers, "reset", patterns));
	if (!limit || remaining == null || !reset) return undefined;
	return { reset, percentUsed: Math.max(0, Math.min(100, ((limit - remaining) / limit) * 100)) };
}

function formatTime(date: Date): string {
	const hours = date.getHours();
	const hour12 = hours % 12 || 12;
	const suffix = hours < 12 ? "am" : "pm";
	return `${hour12}:${date.getMinutes().toString().padStart(2, "0")}${suffix}`;
}

function formatReset(date: Date, preferDate: boolean): string {
	const now = new Date();
	const sameDay = date.toDateString() === now.toDateString();
	return preferDate && !sameDay
		? `${(date.getMonth() + 1).toString().padStart(2, "0")}/${date.getDate().toString().padStart(2, "0")}`
		: formatTime(date);
}

function formatUsageLimit(limit: UsageLimit | undefined, preferDate = false): string | undefined {
	if (!limit) return undefined;
	return `${limit.percentUsed.toFixed(0)}% [󰜉 ${formatReset(limit.reset, preferDate)}]`;
}

function authPath(): string | undefined {
	const home = process.env.HOME || process.env.USERPROFILE;
	return home ? `${home}/.pi/agent/auth.json` : undefined;
}

function decodeJwtPayload(token: string): Record<string, unknown> | undefined {
	try {
		const payload = token.split(".")[1];
		if (!payload) return undefined;
		return JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
	} catch {
		return undefined;
	}
}

function getOpenAICodexAuth(): { access: string; accountId: string } | undefined {
	try {
		const path = authPath();
		if (!path) return undefined;

		const auth = JSON.parse(readFileSync(path, "utf8")) as Record<string, Record<string, unknown> | undefined>;
		const entry = auth["openai-codex"];
		const access = typeof entry?.access === "string" ? entry.access : typeof entry?.accessToken === "string" ? entry.accessToken : undefined;
		if (!access) return undefined;

		let accountId = typeof entry?.accountId === "string" ? entry.accountId : undefined;
		if (!accountId) {
			const payload = decodeJwtPayload(access);
			const openaiAuth = payload?.["https://api.openai.com/auth"] as Record<string, unknown> | undefined;
			accountId = typeof openaiAuth?.chatgpt_account_id === "string" ? openaiAuth.chatgpt_account_id : undefined;
		}
		return accountId ? { access, accountId } : undefined;
	} catch {
		return undefined;
	}
}

function usageLimitFromCodexWindow(window: unknown): UsageLimit | undefined {
	if (!window || typeof window !== "object") return undefined;
	const data = window as { used_percent?: unknown; reset_at?: unknown };
	const percentUsed = Number(data.used_percent);
	const resetAt = Number(data.reset_at);
	if (!Number.isFinite(percentUsed) || !Number.isFinite(resetAt)) return undefined;
	return {
		percentUsed: Math.max(0, Math.min(100, percentUsed)),
		reset: new Date(resetAt * 1000),
	};
}

async function refreshOpenAIUsageLimits(usageLimits: UsageLimits): Promise<boolean> {
	const auth = getOpenAICodexAuth();
	if (!auth) return false;

	try {
		const response = await fetch("https://chatgpt.com/backend-api/wham/usage", {
			headers: {
				Authorization: `Bearer ${auth.access}`,
				"ChatGPT-Account-Id": auth.accountId,
				"User-Agent": "codex-cli",
			},
		});
		if (!response.ok) return false;

		const payload = (await response.json()) as { rate_limit?: { primary_window?: unknown; secondary_window?: unknown } };
		const fiveHour = usageLimitFromCodexWindow(payload.rate_limit?.primary_window);
		const weekly = usageLimitFromCodexWindow(payload.rate_limit?.secondary_window);
		if (fiveHour) usageLimits.fiveHour = fiveHour;
		if (weekly) usageLimits.weekly = weekly;
		return Boolean(fiveHour || weekly);
	} catch {
		return false;
	}
}

export default function (pi: ExtensionAPI) {
	let requestFooterRender: (() => void) | undefined;
	let usagePoll: ReturnType<typeof setInterval> | undefined;
	const usageLimits: UsageLimits = {};

	pi.on("thinking_level_select", async () => {
		requestFooterRender?.();
	});

	pi.on("model_select", async () => {
		requestFooterRender?.();
	});

	pi.on("session_shutdown", async () => {
		requestFooterRender = undefined;
		if (usagePoll) clearInterval(usagePoll);
		usagePoll = undefined;
	});

	pi.on("after_provider_response", async (event) => {
		const fiveHour = parseUsageLimit(event.headers, [/5h/, /5-hour/, /5_hour/]);
		const weekly = parseUsageLimit(event.headers, [/week/, /weekly/, /7d/]);
		if (fiveHour) usageLimits.fiveHour = fiveHour;
		if (weekly) usageLimits.weekly = weekly;
		if (fiveHour || weekly) requestFooterRender?.();

		if (await refreshOpenAIUsageLimits(usageLimits)) requestFooterRender?.();
	});

	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;

		if (usagePoll) clearInterval(usagePoll);
		void refreshOpenAIUsageLimits(usageLimits).then((updated) => {
			if (updated) requestFooterRender?.();
		});
		usagePoll = setInterval(() => {
			void refreshOpenAIUsageLimits(usageLimits).then((updated) => {
				if (updated) requestFooterRender?.();
			});
		}, 60_000);

		ctx.ui.setFooter((tui, theme, footerData) => {
			const render = () => tui.requestRender();
			requestFooterRender = render;
			const unsubscribeBranch = footerData.onBranchChange(render);

			return {
				dispose() {
					unsubscribeBranch();
					if (requestFooterRender === render) requestFooterRender = undefined;
				},
				invalidate() {},
				render(width: number): string[] {
					const contextUsage = ctx.getContextUsage();
					const contextWindow = contextUsage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
					const contextPercent = contextUsage?.percent == null ? "?" : contextUsage.percent.toFixed(0);
					const usedTokens = contextUsage?.tokens == null ? "?" : formatTokens(contextUsage.tokens);
					const contextDisplay = `${contextPercent}% [${usedTokens}/${formatTokens(contextWindow)}]`;

					let cwd = displayPath(ctx.sessionManager.getCwd());
					const branch = footerData.getGitBranch();
					if (branch) cwd += ` (${branch})`;

					const sessionName = ctx.sessionManager.getSessionName();
					if (sessionName) cwd += ` • ${sessionName}`;

					const model = ctx.model;
					const thinkingLevel = model?.reasoning ? pi.getThinkingLevel() : undefined;
					const modelLine = `${model?.id ?? "no-model"}${thinkingLevel ? ` • ${thinkingLevel}` : ""}`;
					const fiveHourUsage = formatUsageLimit(usageLimits.fiveHour);
					const weeklyUsage = formatUsageLimit(usageLimits.weekly, true);
					const usageAndModel = [modelLine, contextDisplay, fiveHourUsage, weeklyUsage].filter(Boolean).join(" | ");
					const styledUsageAndModel = theme.fg("thinkingLow", usageAndModel);
					const sessionAndUsage = ctx.sessionManager.isPersisted()
						? styledUsageAndModel
						: `${theme.fg("warning", "⸸")} ${styledUsageAndModel}`;

					const contentWidth = Math.max(0, width - 1);
					const firstLine = ` ${padBetween(sessionAndUsage, theme.fg("thinkingLow", cwd), contentWidth)}`;

					return [truncateToWidth(firstLine, width), ""];
				},
			};
		});
	});
}
