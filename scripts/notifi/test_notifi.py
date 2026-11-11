#!/usr/bin/env python3
"""Tests for notifi. Run: python3 scripts/notifi/test_notifi.py

Everything external is either a disposable tmux server on a private socket,
with real attached clients in a pty, or a stub on PATH: no real
notifications, Hyprland dispatches, terminals or signals to waybar, and no
running server is touched.
"""

import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from contextlib import suppress
from pathlib import Path
from typing import NamedTuple

NOTIFI = Path(__file__).resolve().parent / "notifi"
ROOT = Path(tempfile.mkdtemp(prefix="notifi-test-"))
BIN, LOGS, STATE = ROOT / "bin", ROOT / "logs", ROOT / "run" / "notifi"

STUBS = {
    # Prints an id, then either the chosen action or nothing until killed.
    "notify-send": r"""
printf '%s\037' "$@" >> "$NOTIFI_TEST_DIR/notify-send.log"
echo >> "$NOTIFI_TEST_DIR/notify-send.log"
echo 7
if [ -n "$NOTIFI_TEST_ACTION" ]; then echo "$NOTIFI_TEST_ACTION"; exit 0; fi
exec sleep 30
""",
    # Behaves like hyprctl: the instance list is read from disk, everything
    # else needs the live signature and prints an error (exit 0) for a stale
    # one.
    "hyprctl": r"""
f="$NOTIFI_TEST_DIR/hypr.json"; sig="$HYPRLAND_INSTANCE_SIGNATURE"
if [ "$1" = --instance ]; then sig=$2; shift 2; fi
if [ ! -f "$f" ]; then
	[ "$1" = instances ] && echo '[]' || echo 'no instance signature!'
	exit 0
fi
if [ "$1" = instances ]; then jq -c .instances "$f"; exit 0; fi
if [ "$sig" != "$(jq -r '.instances[0].instance' "$f")" ]; then
	echo "Couldn't connect to $sig"; exit 0
fi
case "$1" in
	clients) jq -c .clients "$f" ;;
	monitors) jq -c .monitors "$f" ;;
	dispatch) printf '%s\n' "$2" >> "$NOTIFI_TEST_DIR/dispatch.log"; echo ok ;;
esac
""",
    "gdbus": r"""
printf '%s\n' "$*" >> "$NOTIFI_TEST_DIR/gdbus.log"
case "$*" in *GetNameOwner*) cat "$NOTIFI_TEST_DIR/owner" ;; esac
""",
    "pkill": r"""
printf '%s\n' "$*" >> "$NOTIFI_TEST_DIR/pkill.log"
""",
    "ghostty": r"""
{
	printf 'TMUX=%s HIS=%s WAYLAND=%s\n' \
		"$TMUX" "$HYPRLAND_INSTANCE_SIGNATURE" "$WAYLAND_DISPLAY"
	printf '%s\n' "$@"
} > "$NOTIFI_TEST_DIR/ghostty.log"
""",
}


def base_env() -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if key not in ("TMUX", "TMUX_PANE", "HYPRLAND_INSTANCE_SIGNATURE")
        and not key.startswith("SSH_")
    }
    return env | {
        "PATH": f"{BIN}:{os.environ['PATH']}",
        "TERM": "xterm-256color",
        "NOTIFI_TEST_DIR": str(LOGS),
        "XDG_RUNTIME_DIR": str(ROOT / "run"),
    }


class Server(NamedTuple):
    socket: str
    pid: str
    session_id: str
    window_id: str
    pane_id: str


servers: dict[str, Server] = {}
clients: list[subprocess.Popen] = []


def tmux(server: Server, *args: str) -> str:
    # Only sockets created here are ever addressed.
    assert server.socket.startswith(str(ROOT))
    return subprocess.run(
        ["tmux", "-N", "-S", server.socket, *args],
        env=base_env(),
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def start_server(name: str, ssh_started: bool = False) -> Server:
    socket = str(ROOT / name)
    env = base_env()
    if ssh_started:
        env["SSH_CONNECTION"] = "10.0.0.2 1 10.0.0.1 22"
    subprocess.run(
        ["tmux", "-f", "/dev/null", "-S", socket]
        + ["new-session", "-d", "-s", "test", "/bin/sh"],
        env=env,
        check=True,
    )
    probe = Server(socket, "", "", "", "")
    fields = "#{pid}\t#{session_id}\t#{window_id}\t#{pane_id}"
    server = Server(
        socket, *tmux(probe, "display-message", "-p", fields).split("\t")
    )
    servers[name] = server
    return server


def notifi(server: Server | None, *args: str, **extra: str) -> str:
    """Runs notifi as an agent in the server's first pane would.

    Without a server it runs outside tmux, as a key bind or waybar would.
    The timeout also checks that `show` returns while its notification is
    still up, without holding the caller's pipes open.
    """
    env = base_env()
    if server:
        env["TMUX"] = f"{server.socket},{server.pid},0"
        env["TMUX_PANE"] = server.pane_id
    env |= extra
    done = subprocess.run(
        [str(NOTIFI), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert done.returncode == 0, done.stderr
    return done.stdout.strip()


def until(condition, timeout: float = 3) -> None:
    deadline = time.monotonic() + timeout
    while not condition():
        if time.monotonic() > deadline:
            raise TimeoutError
        time.sleep(0.02)


def attach(session: str) -> int:
    """Attaches a real tmux client, standing in for a Ghostty window."""
    local = servers["local"]
    command = f"exec tmux -S '{local.socket}' attach-session -t {session}"
    client = subprocess.Popen(
        ["script", "-qfc", command, "/dev/null"],
        env=base_env(),
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    clients.append(client)
    until(lambda: session in client_sessions().split("\n"))
    return client.pid


def client_sessions() -> str:
    return tmux(servers["local"], "list-clients", "-F", "#{session_name}")


def hyprland(window_pid: int | None, workspace: int = 1) -> None:
    window = {
        "address": "0xabc",
        "pid": window_pid,
        "mapped": True,
        "hidden": False,
        "focusHistoryID": 0,
        "workspace": {"id": workspace},
    }
    snapshot = {
        "instances": [
            {"instance": "live", "time": 2, "wl_socket": "wayland-9"}
        ],
        "clients": [window] if window_pid else [],
        "monitors": [
            {"activeWorkspace": {"id": 1}, "specialWorkspace": {"id": 0}}
        ],
    }
    (LOGS / "hypr.json").write_text(json.dumps(snapshot))


def read(name: str) -> str:
    return (LOGS / name).read_text() if (LOGS / name).exists() else ""


def deliveries() -> list[list[str]]:
    lines = filter(None, read("notify-send.log").split("\n"))
    return [line.split("\x1f")[:-1] for line in lines]


def gdbus_calls(method: str) -> list[str]:
    return [line for line in read("gdbus.log").split("\n") if method in line]


def records() -> list[dict]:
    return [json.loads(path.read_text()) for path in STATE.glob("*.json")]


def showing() -> list[int]:
    """The notify-send process of every notification notifi has on record."""
    return [record["toast"]["pid"] for record in records() if "toast" in record]


def close_notifications() -> None:
    """Closes every notification from the desktop, as Super+N would."""
    for pid in showing():
        with suppress(OSError):
            os.kill(pid, signal.SIGTERM)
    until(lambda: not showing())


def pane_of(server: Server, target: str) -> str:
    return tmux(server, "display-message", "-p", "-t", target, "#{pane_id}")


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def setUpModule() -> None:
    for directory in (BIN, LOGS):
        directory.mkdir()
    for name, script in STUBS.items():
        (BIN / name).write_text(f"#!/bin/sh{script}")
        (BIN / name).chmod(0o755)
    start_server("local,with-comma")
    servers["local"] = servers.pop("local,with-comma")
    start_server("remote", ssh_started=True)
    tmux(servers["local"], "new-session", "-d", "-s", "other", "/bin/sh")


def tearDownModule() -> None:
    for server in servers.values():
        tmux(server, "kill-server")  # never a bare kill-server
    shutil.rmtree(ROOT)


class NotifiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.local, self.remote = servers["local"], servers["remote"]

    def tearDown(self) -> None:
        close_notifications()
        for record in STATE.glob("*.json"):
            record.unlink()
        for client in clients:
            client.kill()
            client.communicate()
        clients.clear()
        until(lambda: client_sessions() == "")
        for server in servers.values():
            tmux(server, "set-option", "-su", "@notifi-desktop")
        tmux(self.local, "select-window", "-t", self.local.window_id)
        shutil.rmtree(LOGS)
        LOGS.mkdir()

    def test_local_server_allows_delivery_despite_stale_ssh_variables(self):
        outcome = notifi(
            self.local,
            *["show", "--app", "pi", "-v"],
            SSH_CONNECTION="stale from an old attach",
        )
        self.assertEqual(outcome, "sent")
        self.assertEqual(
            deliveries(),
            [
                ["--app-name=pi", "--urgency=normal", "--expire-time=0"]
                + ["--print-id", "--wait", "--action=focus=Focus"]
                + ["--", "test:0", "Task Finished"]
            ],
        )

    def test_ssh_started_server_blocks_every_event_and_force(self):
        for event in ("finished", "attention", "error", "aborted"):
            outcome = notifi(
                self.remote, "show", "--event", event, "--force", "-v"
            )
            self.assertEqual(outcome, "blocked")
        self.assertEqual(deliveries(), [])
        self.assertEqual(notifi(self.remote, "status"), "blocked")
        self.assertEqual(notifi(self.local, "status"), "allowed")

    def test_notifi_desktop_option_is_read_per_notification(self):
        for mode in ("off", "invalid"):
            tmux(self.local, "set-option", "-s", "@notifi-desktop", mode)
            notifi(self.local, "show", "--event", "error")
        self.assertEqual(deliveries(), [])
        tmux(self.remote, "set-option", "-s", "@notifi-desktop", "on")
        notifi(self.remote, "show", "--event", "error")
        self.assertEqual(len(deliveries()), 1)

    def test_outside_tmux_is_a_plain_notification_and_none_over_ssh(self):
        notifi(None, "show", "--app", "claude", "--event", "error")
        self.assertEqual(
            deliveries(),
            [
                ["--app-name=claude", "--urgency=critical", "--expire-time=0"]
                + ["--print-id", "--wait", "--", "claude", "Task Failed"]
            ],
        )
        notifi(None, "show", "--event", "error", SSH_TTY="/dev/pts/9")
        self.assertEqual(len(deliveries()), 1)
        notifi(None, "dismiss", "--app", "claude")
        self.assertEqual(showing(), [])

    def test_each_event_has_its_own_text_urgency_and_expiry(self):
        notifi(self.local, "show", "--event", "aborted")
        notifi(self.local, "show", "--event", "attention")
        aborted, attention = deliveries()
        self.assertEqual(
            aborted[1:3], ["--urgency=critical", "--expire-time=5000"]
        )
        self.assertEqual(aborted[-1], "Task Aborted")
        self.assertEqual(
            attention[1:3], ["--urgency=normal", "--expire-time=0"]
        )
        self.assertEqual(attention[-1], "Needs Input")

    def test_focus_aware_events_are_skipped_while_the_window_is_on_screen(self):
        hyprland(attach("test"))
        for event in ("finished", "attention"):
            outcome = notifi(self.local, "show", "--event", event, "-v")
            self.assertEqual(outcome, "visible")
        self.assertEqual(deliveries(), [])
        notifi(self.local, "show", "--event", "error")
        notifi(self.local, "show", "--force")
        self.assertEqual(len(deliveries()), 2)

        hyprland(clients[0].pid, workspace=2)  # same window, off screen
        notifi(self.local, "show")
        self.assertEqual(len(deliveries()), 3)

    def test_a_notification_is_replaced_and_closed_once_the_window_is_seen(
        self,
    ):
        (LOGS / "owner").write_text("(':1.5',)\n")
        notifi(self.local, "show", "--event", "attention")
        (first,) = showing()
        notifi(self.local, "show")
        (second,) = showing()
        self.assertNotEqual(first, second)
        self.assertFalse(alive(first))
        self.assertEqual(len(gdbus_calls("CloseNotification")), 1)

        hyprland(attach("test"))
        self.assertEqual(notifi(self.local, "show", "-v"), "visible")
        self.assertEqual(showing(), [])
        self.assertFalse(alive(second))
        self.assertEqual(len(gdbus_calls("CloseNotification")), 2)

    def test_focus_after_a_hyprland_restart_reuses_the_live_window(self):
        hyprland(attach("other"))
        notifi(
            self.local,
            "show",
            # Left behind in tmux by the previous Hyprland.
            HYPRLAND_INSTANCE_SIGNATURE="stale",
            NOTIFI_TEST_ACTION="focus",
        )
        until(lambda: client_sessions() == "test")
        self.assertEqual(
            read("dispatch.log"), 'hl.dsp.focus({ window = "address:0xabc" })\n'
        )
        self.assertFalse((LOGS / "ghostty.log").exists())

    def test_focus_opens_ghostty_when_no_window_hosts_a_client(self):
        tmux(self.local, "new-window", "-d", "-t", "test:", "/bin/sh")
        tmux(self.local, "select-window", "-t", "test:1")
        hyprland(None)
        notifi(
            self.local,
            "show",
            HYPRLAND_INSTANCE_SIGNATURE="stale",
            NOTIFI_TEST_ACTION="focus",
        )
        until(lambda: (LOGS / "ghostty.log").exists() and read("ghostty.log"))
        self.assertEqual(
            read("ghostty.log").strip().split("\n"),
            ["TMUX= HIS=live WAYLAND=wayland-9", "-e", "tmux", "-S"]
            + [
                self.local.socket,
                "attach-session",
                "-t",
                self.local.session_id,
            ],
        )
        selected = tmux(
            self.local, "display-message", "-p", "-t", "test", "#{window_id}"
        )
        self.assertEqual(selected, self.local.window_id)
        tmux(self.local, "kill-window", "-t", "test:1")

    def test_dismiss_closes_it_unless_the_daemon_that_issued_it_is_gone(self):
        (LOGS / "owner").write_text("(':1.5',)\n")
        notifi(self.local, "show")
        (pid,) = showing()
        notifi(self.local, "dismiss")
        self.assertEqual(showing(), [])
        self.assertFalse(alive(pid))
        (close,) = gdbus_calls("CloseNotification")
        self.assertRegex(close, r"CloseNotification 7$")
        notifi(self.local, "dismiss")  # nothing left to close
        self.assertEqual(len(gdbus_calls("GetNameOwner")), 2)

        notifi(self.local, "show")
        (pid,) = showing()
        (LOGS / "owner").write_text("(':1.6',)\n")  # dunst restarted
        notifi(self.local, "dismiss")
        self.assertFalse(alive(pid))
        self.assertEqual(len(gdbus_calls("CloseNotification")), 1)

    def test_closing_the_notification_leaves_the_agent_pending(self):
        notifi(self.local, "show", "--event", "attention")
        self.assertEqual(notifi(None, "pending"), "")
        self.assertEqual(read("pkill.log"), "")
        close_notifications()
        self.assertEqual(notifi(None, "pending"), "test:0\tNeeds Input")
        self.assertEqual(notifi(None, "pending", "--count"), "1")
        self.assertEqual(read("pkill.log"), "-RTMIN+8 -x waybar\n")

        notifi(self.local, "dismiss")
        self.assertEqual(records(), [])
        self.assertEqual(notifi(None, "pending", "--count"), "")
        self.assertEqual(gdbus_calls("CloseNotification"), [])
        self.assertEqual(read("pkill.log"), "-RTMIN+8 -x waybar\n" * 2)

    def test_a_new_notification_ends_the_pending_state(self):
        notifi(self.local, "show")
        close_notifications()
        notifi(self.local, "show", "--event", "error")
        self.assertEqual(len(showing()), 1)
        self.assertEqual(notifi(None, "pending"), "")

        close_notifications()
        self.assertEqual(notifi(None, "pending"), "test:0\tTask Failed")
        hyprland(attach("test"))
        self.assertEqual(notifi(self.local, "show", "-v"), "visible")
        self.assertEqual(records(), [])

    def test_only_a_pane_whose_notification_never_expires_stays_pending(self):
        notifi(self.local, "show", "--event", "aborted")
        notifi(None, "show", "--app", "claude", "--event", "error")
        self.assertEqual(len(showing()), 2)
        close_notifications()
        self.assertEqual(records(), [])

    def test_closing_it_with_the_pane_on_screen_leaves_nothing_pending(self):
        notifi(self.local, "show", "--event", "error")
        hyprland(attach("test"))  # the user went to look
        close_notifications()
        self.assertEqual(records(), [])

    def test_next_focuses_the_pending_agents_oldest_first(self):
        other = pane_of(self.local, "other:")
        notifi(self.local, "show", "--event", "error", TMUX_PANE=other)
        notifi(self.local, "show")
        close_notifications()
        self.assertEqual(
            notifi(None, "pending"),
            "other:0\tTask Failed\ntest:0\tTask Finished",
        )

        # Nowhere to focus: it fails and forgets nothing.
        done = subprocess.run(
            [str(NOTIFI), "next"],
            env=base_env(),
            capture_output=True,
            text=True,
        )
        self.assertEqual(done.returncode, 1)
        self.assertIn("Hyprland", done.stderr)
        self.assertEqual(notifi(None, "pending", "--count"), "2")

        hyprland(attach("test"))
        self.assertEqual(notifi(None, "next"), "other:0")
        self.assertEqual(client_sessions(), "other")
        self.assertEqual(
            read("dispatch.log"), 'hl.dsp.focus({ window = "address:0xabc" })\n'
        )
        self.assertEqual(notifi(None, "pending"), "test:0\tTask Finished")
        self.assertEqual(notifi(None, "next"), "test:0")
        self.assertEqual(client_sessions(), "test")
        self.assertEqual(notifi(None, "next"), "")
        self.assertEqual(records(), [])

    def test_a_pane_that_died_is_no_longer_pending(self):
        tmux(self.local, "new-window", "-d", "-t", "test:", "/bin/sh")
        doomed = pane_of(self.local, "test:1")
        notifi(self.local, "show", TMUX_PANE=doomed)
        notifi(self.local, "show", "--event", "attention")
        close_notifications()
        self.assertEqual(notifi(None, "pending", "--count"), "2")
        tmux(self.local, "kill-window", "-t", "test:1")  # no dismiss
        self.assertEqual(notifi(None, "pending"), "test:0\tNeeds Input")
        self.assertEqual(len(records()), 1)

        # A later tmux server on the same socket numbers its panes from %0
        # again, so the record of an earlier one must not pass for them.
        (record,) = STATE.glob("*.json")
        earlier = json.loads(record.read_text()) | {"server": "1"}
        record.write_text(json.dumps(earlier))
        self.assertEqual(notifi(None, "pending"), "")
        self.assertEqual(records(), [])

    def test_a_notification_lost_with_its_daemon_is_pending(self):
        (LOGS / "owner").write_text("(':1.5',)\n")
        notifi(self.local, "show")
        (pid,) = showing()
        self.assertEqual(notifi(None, "pending", "--count"), "")
        (LOGS / "owner").write_text("(':1.6',)\n")  # dunst restarted
        self.assertEqual(notifi(None, "pending", "--count"), "1")

        hyprland(attach("other"))
        self.assertEqual(notifi(None, "next"), "test:0")
        until(lambda: not alive(pid))  # the notify-send left behind
        self.assertEqual(gdbus_calls("CloseNotification"), [])
        self.assertEqual(records(), [])

    def test_usage_errors_never_exit_with_status_2(self):
        # Claude Code treats exit status 2 from a hook as "block".
        for args in (["bogus"], ["show", "--event", "nope"], []):
            done = subprocess.run(
                [str(NOTIFI), *args], env=base_env(), capture_output=True
            )
            self.assertEqual(done.returncode, 1, args)


if __name__ == "__main__":
    unittest.main()
