# pi-firecrawl

A Pi extension that adds two Firecrawl-backed tools:

- `web_search` searches the public web and returns ranked links and snippets.
- `web_fetch` extracts one URL as readable Markdown.

It does not crawl whole sites or control a browser.

## Setup

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

## Security and privacy

Search queries and requested URLs are sent to Firecrawl. Firecrawl also retrieves the requested pages. Review Firecrawl's privacy policy before using sensitive URLs or queries.

Web pages and search snippets are untrusted data. The extension labels them as such, but the model must still ignore instructions embedded in fetched content.

## Development

```bash
npm install --ignore-scripts
npm test
npm run typecheck
```
