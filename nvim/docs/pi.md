# Pi in Neovim

Uses the local `~/personal/pi-nvim` toolkit and Pi on Neovim's `$PATH`.
The integration is skipped if the toolkit checkout is missing. Configure your
model/credentials in Pi beforehand. Startup and opening windows do not call a
model; **sending a question can incur charges**.

## Workflow

1. Collect context while visiting source buffers. Nothing attaches automatically.
2. `:PiAsk` (or `<leader>pa`) opens the floating Markdown draft with attachments
   underneath. Closing it hides both panes, retaining text, cursor and undo.
3. Write your question. Use normal-mode `<Tab>` to switch between the panes.
4. In the attachment pane: `<Enter>` previews exactly that attachment, `d` removes
   it, and `r` refreshes it from its original source. Changed sources are marked.
5. `:PiPreview` (draft normal-mode `gP`) previews the outgoing user message
   (question and attachments, not system instructions or conversation history).
6. `:PiSend` or draft-local `<C-s>` sends. Enter inserts a newline as usual.
   Writing or closing the draft never sends it.
7. The answer streams into a read-only conversation split. `:PiChat` or
   `<leader>pc` reopens it. Normal-mode `q` hides a view without cancelling work.

## Context commands

| Command | Context | Mapping |
|---|---|---|
| `:PiAttachFile [path]` | Disk file reference; defaults to current file | `<leader>pf` |
| `:PiAttachBuffer` | Complete unsaved editor buffer | — |
| `:PiAttachDiagnostics` | All diagnostics in the source buffer | `<leader>pD` |
| `:PiAttachDiagnostic` | Diagnostic covering the cursor; picker on overlaps | `<leader>pd` |
| `:PiAttachSelection` | Active Visual selection | Visual `<leader>pv` |
| `:'<,'>PiAttachSelection` | Explicit linewise Ex range | — |
| `:PiAttachQuickfix` | Current quickfix list entries and title | `<leader>pq` |

Every successful attachment shows a command-line confirmation, including Visual
selections after leaving Visual mode. Attachment commands don't open/focus the
composer or alter quickfix. Run file/buffer/diagnostic/selection commands from the
source buffer, not a Pi view.
The Visual mapping preserves characterwise/multibyte selection boundaries. An
Ex range is linewise. Blockwise/virtual-space selections aren't supported by
the toolkit and produce an error rather than silently capturing different text.

Paths display relative to the conversation workspace where possible; external
paths remain absolute. Explicit relative `PiAttachFile` paths resolve against
that workspace. A file reference asks Pi to read disk with its tools; it is not
an automatic upload. For modified files, choose an unsaved buffer snapshot, a
disk reference, or cancel. Buffers are never silently saved.

Outgoing messages contain the question and explicit attachments, without a
repeated workspace header. Editor snapshots include paths, filetypes, text and
zero-based byte positions; diagnostics include readable severity and nonempty
source/code fields. Snapshot IDs, buffer numbers, changedticks, namespaces and
encoding/EOL/BOM details stay internal. Quickfix omits unused fields.

Selections, diagnostics and quickfix are frozen when attached. Sending refuses
changed attachments until you refresh/remove them. Refreshing a selection uses
its original coordinates, **not tracking a moved selection**; reattach after
structural edits. A refreshed single diagnostic must still uniquely cover its
original position. Diagnostic publication can lag behind edits; freshness checks
are not proof that the LSP's diagnostic is up to date. Quickfix includes entry
messages/paths/locations, not the contents of every referenced file.

## Conversation and recovery

- One continuing **in-memory** conversation, using the same running RPC client.
  Hiding windows doesn't stop/reset Pi. There is no connection to a separate Pi
  terminal session. Drafts and conversation do not survive restarting Neovim.
- The session directory is Neovim's current working directory on first use,
  pinned for that conversation. Source-file locations and Git roots don't change it.
- `:PiNew` starts a fresh conversation using Neovim's current working directory.
  `:PiNew /other/project` uses an explicit directory instead. An unfinished draft
  is preserved if the directory is unchanged; changing directories requires an
  empty draft/attachment list. It clears the displayed conversation and archive.
- Successful submission archives and clears the sent draft/attachments, hiding
  the composer to show the answer. If you changed the draft or added context
  while awaiting acknowledgement, it stays open and your changes aren't erased. A submission/startup
  failure preserves the draft. Acceptance isn't the same as a successful answer.
- `:PiRestore` (draft `gR`) restores the last accepted draft with its attachments,
  including after cancellation/provider failure. Clear your current draft first.
- `:PiClear` (draft normal-mode `gC`) discards the unfinished draft and attachments explicitly. Deleting
  draft text with Vim motions leaves attachments intact.
- A second send while busy is refused; the next draft remains intact. There is
  no implicit queue or steering.
- `:PiAbort` clears any Pi queue, then aborts the current work. The conversation
  remains usable after ordinary cancellation.
- A three-minute whole-task deadline stops Pi. Cancellation failure or an
  unexpected process exit also requires `:PiNew`, so a lost conversation isn't
  silently replaced. An ambiguous acknowledgement/transport failure stops Pi
  rather than pretending the prompt couldn't have executed. Stop/exit retains partial output and the submitted archive.
- Prompts over 1 MiB are refused without truncation. Remove large attachments.

## Explain/investigate only

Only `read`, `grep`, `find`, and `ls` tools are enabled. There is no shell,
editing, or writing tool. Extensions, skills, prompt templates and automatic
context-file discovery are disabled for this client; instructions attached in
source are treated as data. Attachments guide attention, **not filesystem access**.

This is a tool allowlist, not an OS sandbox. Pi, settings, credential helpers and
the configured provider remain trusted executable components. Review context
before sending it, especially unsaved buffers and diagnostic/build messages.

## Files and verification

- `lua/plugins/pi.lua`: local toolkit loading, mappings, teardown.
- `lua/config/pi/init.lua`: workflow ownership, commands, Pi lifecycle.
- `lua/config/pi/context.lua`: detached attachment capture and serialization.
- `lua/config/pi/view.lua`: composer, attachment, preview and chat windows.

Reload by executing `:lua dofile(vim.fn.stdpath('config') .. '/lua/plugins/pi.lua')`.
Reload explicitly disposes the old process/UI/commands/mappings and discards its
in-memory state. Removing the integration requires removing its `init.lua`
require. Colors use existing highlights; no palette changes are needed.

Deterministic tests (Python 3, Neovim and the local toolkit; no provider/network):

```sh
nvim --headless -u NONE -l tests/pi.lua
stylua --check lua/config/pi lua/plugins/pi.lua tests/pi.lua init.lua
nvim --headless +qa
```
