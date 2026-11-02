# ROS workspace in host tmux

Select `Software-Cyclone-Core` (or the container's setup repo) in sessionizer.
The `ros` preset creates `zsh` and `nvim` windows in `ubuntu-ros`, initially
selecting `nvim`. The first window is an interactive Zsh shell; the editor window
starts Neovim and returns to Zsh when it exits. No
agent/model call or robot nodes launch automatically. The container and Neovim
must already exist; this integration does not install tools.

Host tmux remains in charge: existing prefix, navigation, copy mode, and session
switching still work. The club's `start_tmux_session.sh` is not involved.

## Keys

- Prefix + `c`: new Ubuntu window in the current pane's container directory.
- Prefix + `%` / `"`: split into a new Ubuntu pane in that directory.
- Ctrl-F at a container Zsh prompt or in the container Neovim's normal mode:
  open the **host** sessionizer picker. Neovim's own mapping cannot reach the
  host script, so `nvim/lua/config/sessionizer.lua` keeps an `nvim-normal` file
  in the pane's state directory while in normal mode, and `ros-tmux picker`
  treats it like the prompt marker. In other Neovim modes and during any other
  foreground command, Ctrl-F is forwarded to the application.
- Prefix + Ctrl-F: open the sessionizer from any pane or program.
- Other host sessions retain their previous window/split/Control-F behavior.

Each pane tracks its own directory, including paths containing spaces or quotes
and container-only paths such as `/opt/ros/jazzy`. Tracking is for interactive
Zsh, not arbitrary Bash/Fish shells started inside it.

Direct `tmux new-window`/`split-window` calls and mouse-menu actions still enter
Ubuntu through the session's `default-command`, but start at the project root.
Use the above bindings for directory following. Explicit commands passed to tmux
bypass `default-command` and must themselves enter the container if required.

## Implementation

- `tmux-sessionizer.conf`: discovers the dedicated home's `personal` directory
  and assigns the `ros` preset to it.
- `presets/ros`: session-local container/root/default-command settings; replaces
  sessionizer's freshly created host shell, then opens the editor window.
- `ros-tmux`: host-side shell launcher and window/split/picker dispatch.
- `ros-zsh/.zshrc`: selected with `ZDOTDIR` only for these panes. Loads the
  container's own `$HOME/.zshrc`, then installs directory/prompt hooks. Does not
  source the host shell configuration or pyenv.
- `../../tmux/tmux.conf`: in sessions with `@ros_container`, routes the ordinary
  window/split keys and Ctrl-F through the helper; its picker decides between
  sessionizer and forwarding (see Keys). Other sessions run plain tmux commands
  and never invoke the helper, which refuses non-ROS panes.
- `../../zsh/ros.zsh` (the container's `.zshrc`): sources the micro-ROS overlay,
  which chains `/opt/ros/jazzy`; jazzy alone only when the overlay is missing.

Directory reports use a private `mktemp` directory under shared `/tmp`, one per
shell. The file is NUL-terminated and atomically replaced; its contents are never
evaluated as shell code. Zsh reports on `chpwd` and `precmd` (including return from
a nested shell). The host always starts its pane in the shared project directory;
the launcher performs the requested `cd` **inside** Ubuntu. The state directory
is removed on normal exit; abrupt termination may leave small runtime files in
`/tmp`, not in the project. No host-spawn or Ubuntu tmux client is required.

Before opening each interactive shell, `ros-tmux` uses host `flock` to serialize
a short `distrobox enter --no-tty -- /bin/true` readiness probe. The per-container
lock lives under `$XDG_RUNTIME_DIR/ros-tmux` (or the host cache directory when no
runtime directory is set). This prevents simultaneous cold starts from sharing
Distrobox's startup-log FIFO and splitting its completion marker between readers.
Under the lock, a container the manager (`$DBX_CONTAINER_MANAGER`, default
`podman`) already reports running skips the probe (~60 ms instead of ~420 ms).
The check must stay under the lock: a container reports running before
Distrobox finishes initializing it, so a concurrent entrant waits for the
cold-start probe, then skips its own. The lock is released before the interactive shell launches, so an open pane never
blocks new panes. This coordinates entry through this integration; unrelated
manual Distrobox startup commands do not participate in the lock.

If readiness, container entry, or the initial `cd` fails, the pane displays the
error and waits for Enter to close. It never falls back to an Arch shell. A
dead/missing state file falls back to the session's project root.

The container hostname may still show `ubuntu-ros-isolated`: Podman renaming
changed the container name, not its hostname. `ubuntu-ros` is the entry target.

## ROS/C++ build and LSP baseline

The container's `~/.colcon/defaults.yaml` enables
`-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` on normal builds. The installed colcon-cmake
extension already combines per-package databases into `build/compile_commands.json`;
no custom merge script is needed. In Software-Cyclone-Core, the local link
`compile_commands.json -> build/compile_commands.json` makes this discoverable by
clangd for source files and generated headers. The link is excluded locally in
`.git/info/exclude`, not in the shared project's `.gitignore`.

Usual workflow inside Ubuntu, from the workspace root:

```sh
colcon build
source install/setup.zsh  # expose the built workspace to ROS tools in this shell
```

For another colcon workspace, create the same root link after building:
`ln -s build/compile_commands.json compile_commands.json`. Restart clangd/reopen
Neovim after initially wiring it up. New C++ packages must be registered in CMake
and package.xml to get their own accurate compiler commands. A successful build
does not imply unregistered loose source files are configured.

Validated on main: all 16 discovered packages built; clangd checks passed for a
ROS C++ source and the generated `loginfo__struct.hpp`; headless Neovim attached
clangd to that generated header with zero error diagnostics. This is a C/C++
baseline, not a claim that optional Python/Lua/CMake language servers or hardware
runtime behavior have been configured/tested. No Pi/agent tooling was installed.

## Tools and scope

Neovim, agents, and their configurations are **not** installed by this preset.
Provision those separately in the container; do not import the entire host home.
The host's installed tools and the club repos are not modified by this feature.
Distrobox still exposes host files; this is workspace separation, not a sandbox.

## Validation

```sh
bash scripts/tmux-sessionizer/tests/test-discovery.bash
bash scripts/tmux-sessionizer/tests/test-sessionizer.bash
# Deterministic startup race/failure tests; no real containers involved.
bash scripts/tmux-sessionizer/tests/test-ros-startup.bash
bash scripts/tmux-sessionizer/tests/test-ros-picker.bash
# Opt-in: uses the existing ubuntu-ros, with a disposable tmux server and workspace.
bash scripts/tmux-sessionizer/tests/test-ros-integration.bash
# Opt-in cold start: requires an already provisioned, STOPPED disposable container.
# Refuses names outside ros-startup-check-*; never stops the real ubuntu-ros.
bash scripts/tmux-sessionizer/tests/test-ros-cold-start.bash ros-startup-check-NAME
```

The cold-start test opens two simultaneous shells and a third while both remain
open. It uses its own tmux server; creating/removing the disposable container is
the caller's responsibility. A real test passed both on first startup and after
stopping/restarting a disposable container; no robot processes are launched.

For a new tmux server, the normal config enables the bindings. On an existing
server, source `~/dotfiles/tmux/tmux.conf`. Existing non-ROS sessions are not
converted. Select the project through sessionizer to create the configured ROS
session. Revert the added bindings/search rule/preset to remove the integration;
this does not remove the container or project files.
