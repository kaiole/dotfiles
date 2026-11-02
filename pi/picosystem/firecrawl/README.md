# pi-firecrawl

A Pi extension that adds two Firecrawl-backed tools:

- `web_search` searches the public web and returns ranked links and snippets.
- `web_fetch` extracts one URL as readable Markdown.

It does not crawl whole sites or control a browser.

## Setup

Requires Node.js 22.13 or newer (uses built-in SQLite; older Node releases may print its experimental warning).

Create a Firecrawl account, copy an API key, and expose it to the process that launches Pi:

```bash
export FIRECRAWL_API_KEY="fc-..."
```

Put the export in your shell startup file if it should persist. Do not commit the key.

Install the local package:

```bash
pi install /home/red/dotfiles/pi/picosystem/firecrawl
```

Or add that path to the `packages` array in `~/.pi/agent/settings.json`, then restart Pi or run `/reload`.

## Tool behavior

`web_search` accepts a query, a result limit from 1 to 10, and optional domain inclusion or exclusion lists. It performs lightweight search without scraping every result. Pi can then call `web_fetch` for selected sources, which avoids spending extraction credits on irrelevant pages.

`web_fetch` accepts HTTP and HTTPS URLs. It requests Markdown from Firecrawl and defaults to main-page content. Set `onlyMainContent` to `false` when navigation or other surrounding page content matters.

Both tools cap model-facing output below Pi's 50 KB and 2,000-line limits. If a fetched page exceeds the limit, the extension stores the complete result in a temporary file and reports its path.

## Rate limits

Both tools automatically retry **HTTP 429 only**, up to four total attempts. Valid numeric or HTTP-date `Retry-After` guidance is never shortened to fit the tool's budget. Missing, malformed, zero, or past guidance uses exponential backoff starting at 1s and doubling on each 429 (capped at 30s), with additive jitter. Valid guidance also receives at least this backoff floor and additive jitter. Each attempt has a 125s timeout including its response body; each tool call has a **240s overall budget**, including coordination, cooldowns, retries, and requests. A cooldown beyond the remaining budget fails immediately with the last 429 and retry guidance, rather than retrying early. Even the final 429 publishes its cooldown for other calls. Other HTTP failures and network errors are not retried, avoiding possible duplicate credit consumption.

Fresh clients and separate local Pi processes share cooldowns in a private SQLite database. Updates are atomic; no transaction is held during a request or sleep. SQLite releases locks and recovers incomplete transactions after process death. Waiting calls reserve no future slots, so cancellation or process death cannot strand a queue (at most one already-admitted start gap is lost). Starts are staggered by 1–1.25s for a minute after cooldown expiry to avoid a retry burst. Tools report waits and retry attempts through progress updates; all waits and requests are cancellable.

[Firecrawl rate limits](https://docs.firecrawl.dev/rate-limits) are per team, with separate `/search` and `/scrape` buckets. By default, local coordination groups calls by a SHA-256 identifier derived from the API key and normalized service URL, separately for each endpoint. **No plan-specific RPM or local concurrency limit is assumed.** Initial bursts can still hit 429; server-side browser queues handle concurrency. Optional evenly spaced request starts can prevent local RPM bursts when you know your allowance:

| Environment variable | Purpose |
| --- | --- |
| `FIRECRAWL_API_URL` | Optional service base URL; defaults to `https://api.firecrawl.dev`. No credentials, query, or fragment. |
| `FIRECRAWL_SEARCH_RPM` | Optional positive requests/minute allowance for search. |
| `FIRECRAWL_SCRAPE_RPM` | Optional positive requests/minute allowance for fetching. |
| `FIRECRAWL_RATE_LIMIT_TEAM` | Optional non-secret local team label. Set the same label on different keys belonging to one team to share their endpoint counters. Different teams must use different labels. |
| `FIRECRAWL_RATE_LIMIT_DIR` | Dedicated private coordination directory (absolute path). Defaults to `$XDG_CACHE_HOME/pi/firecrawl`, or `~/.cache/pi/firecrawl`. |

Use consistent pacing settings and the same directory across participating processes. Coordination covers only cooperating processes on the same machine/user and local filesystem, **not other machines, API clients, or different keys unless a team label is configured**. It is admission pacing, not a server quota guarantee. Requests already in flight when a 429 arrives cannot be recalled. Network-mounted coordination directories are unsupported.

The directory must be user-owned, mode 0700; its database is mode 0600. Insecure/symlinked state or storage failures fail closed, without sending an uncoordinated request. State contains only hashed scope identifiers and timestamps—no raw keys, queries, or URLs. Expired rows are cleaned on admission. Long server cooldowns persist across processes/restarts; they are not capped to the tool's budget to permit an early retry. Values beyond the safe timestamp range become an effectively permanent cooldown until reset. If state needs a manual reset, stop **all** participating Pi processes before removing the dedicated directory.

## Security and privacy

Search queries and requested URLs are sent to Firecrawl. Firecrawl also retrieves the requested pages. Review Firecrawl's privacy policy before using sensitive URLs or queries.

Web pages and search snippets are untrusted data. The extension labels them as such, but the model must still ignore instructions embedded in fetched content.

## Development

```bash
npm install --ignore-scripts
npm test
npm run typecheck
```
