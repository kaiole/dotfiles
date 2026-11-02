# Pi fullscreen Vim copy mode

Status: parked. No implementation or commitment to maintain a custom build.

## Goal

Keep Pi's native fullscreen interface and smooth transcript scrolling while gaining keyboard-only navigation, highlighting, and copying. Preserve the ability to compose a prompt while viewing older conversation text.

Modified scrolling shortcuts alone do not meet the need. Neither does replacing Pi's interface with a Neovim RPC frontend. The current regular-mode tmux copy-mode + split-editor workflow remains the fallback.

## Proposed interaction

- `Ctrl+b`: enter browse mode from the main prompt editor. Proposed default; replaces prompt cursor-left on that key, not tmux's prefix (currently `Ctrl+Space`).
- `q`: leave browse mode and return to the unchanged draft without moving the transcript.
- `Escape` and `Ctrl+c`: equivalent within browse mode. Close search or cancel selection; otherwise remain browsing. Consume these keys so they do not clear the draft or trigger unrelated application actions. Outside browse mode, retain existing behavior.
- `G`: go to the transcript bottom and resume following output. No visible "go to bottom" button.
- New output must not pull the viewport away while browsing or composing against older history.
- Search input owns printable keys: typing `q` searches for q rather than leaving browse mode.

### Initial scope

Navigation and selection only; not a full Vim implementation:

- `hjkl`, `w/b/e`, `0/^/$`, `gg/G`.
- `Ctrl+u/d` half-page navigation.
- `/` search, `n/N` next/previous match.
- Counts such as `5j` and `3w`.
- `v/V` characterwise/linewise selection.
- `y` copies plain text to the system clipboard, without interface decorations, and remains in browse mode.

No editing operators, text objects, marks, or macros initially.

Proposed cursor default: restore the previous browse cursor if still visible; otherwise place it in the current viewport. Exact placement is not yet specified.

## Engineering direction and uncertainty

Inspection of installed Pi 1.4.0 docs and declarations found fullscreen scrolling/search actions and mouse-driven selection machinery, but no public extension API for manipulating the transcript selection cursor. A remapping-only extension is insufficient.

Preferred direction, if revisited: reuse Pi's native fullscreen transcript rendering and selection machinery, adding keyboard cursor/selection control and modal input routing. Avoid a duplicate transcript viewer or simulated mouse drags.

A source change appears necessary for that direction, but no detailed source investigation or patch-size assessment has been completed. Do not treat a fork as the established requirement: first determine whether a small upstream API addition could enable a clean extension.

Decision-critical implementation details:

- Stable cursor and selection anchors while output streams or tool displays change.
- Wrapped lines, logical lines, wide characters, and terminal resizing.
- Plain-text copying and soft-wrap behavior.
- Correct input ownership across prompt editor, search, selection, dialogs, and split-editor.
- Explicit viewport-follow behavior independent of prompt focus.

## Custom-build maintenance, if needed

- Keep a small isolated commit series on top of an official release.
- Preserve the managed stock Pi installation as a fallback; develop with a separate launcher initially.
- Never patch installed JavaScript in place.
- Update deliberately: fetch a release, replay commits, build/test, smoke-test, then switch.
- Failed updates must leave the known-good build usable; rollback must be straightforward.
- Automated checks cannot guarantee semantic compatibility even when Git reports no conflicts.
- TUI changes upstream may require substantial adaptation. Maintenance cost depends on coupling to internals, not patch line count; no reliable estimate yet.
- Ideally upstream the feature or the minimal APIs needed to support it.

## Next step if resumed

Perform a narrowly scoped source investigation to identify the smallest clean integration boundary and assess update coupling before choosing a fork or starting implementation.
