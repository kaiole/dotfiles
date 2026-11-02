# FL Studio x AeroSpace Notes

## Context

- Platform: macOS
- WM: AeroSpace
- App: FL Studio

## Observed Behavior

- On initial launch, FL Studio does not appear in `aerospace list-windows
  --all`.
- If FL Studio is minimized (not closed) and then restored, it appears in
  `aerospace list-windows --all`.
- Even after appearing in list output, FL Studio remains effectively
  untileable.

## What Still Works

- FL Studio stays assigned to a workspace.
- FL Studio can be moved between workspaces.

## What Does Not Work

- Standard tiling behavior is not applied.

## Preliminary Hypothesis

- FL Studio windows may expose partial accessibility/window metadata that
  allows workspace assignment but not full tiling management.
- Minimize/restore likely changes discoverability timing/state, but not enough
  for full tile compatibility.

## Suggested Next Diagnostics

1. Record `aerospace list-windows --all` before launch, after launch, and after
minimize/restore.
2. Record app/window identifiers from AeroSpace output.
3. Add a targeted `on-window-detected` rule for FL Studio and test `layout
tiling` vs `layout floating`.
4. Confirm whether behavior changes across FL Studio versions.
