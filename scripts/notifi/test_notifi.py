#!/usr/bin/env python3
"""Tests for notifi. Run: python3 scripts/notifi/test_notifi.py

Builds notifi first. Everything external is a disposable tmux server on a
private socket, with real attached clients in a pty, a stub on PATH or, for
Hyprland and the session bus, a socket answered from here; this process
stands in for waybar. So there are no real notifications, Hyprland
dispatches, terminals, bus calls or signals to waybar, and no running server
is touched.
"""

import json
import os
import shutil
import signal
import socket
import struct
import subprocess
import tempfile
import threading
import time
import unittest
from contextlib import suppress
from pathlib import Path
from typing import NamedTuple

CRATE = Path(__file__).resolve().parent
NOTIFI = CRATE / "target" / "release" / "notifi"
ROOT = Path(tempfile.mkdtemp(prefix="notifi-test-"))
BIN, LOGS, STATE = ROOT / "bin", ROOT / "logs", ROOT / "run" / "notifi"
# Where notifi looks for Hyprland instances: one directory each.
HYPR = ROOT / "run" / "hypr"
# notifi signals the bar it finds by this name, which this process takes.
BAR = f"bar-{os.getpid()}"
BAR_SIGNAL = signal.SIGRTMIN + 8

STUBS = {
    # Prints an id, then either the chosen action or nothing until killed.
    "notify-send": r"""
printf '%s\037' "$@" >> "$NOTIFI_TEST_DIR/notify-send.log"
echo >> "$NOTIFI_TEST_DIR/notify-send.log"
echo 7
if [ -n "$NOTIFI_TEST_ACTION" ]; then echo "$NOTIFI_TEST_ACTION"; exit 0; fi
exec sleep 30
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
        "NOTIFI_BAR": BAR,
        "XDG_RUNTIME_DIR": str(ROOT / "run"),
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path={ROOT / 'bus'}",
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


# What the fake Hyprland answers each request with.
desktop: dict[str, list] = {}


def serve_hyprland(listener: socket.socket) -> None:
    """Answers on Hyprland's request socket, and logs the dispatches."""
    while True:
        connection, _ = listener.accept()
        with connection, suppress(OSError):
            request = connection.recv(8192).decode()
            if request.startswith("/dispatch "):
                with open(LOGS / "dispatch.log", "a") as log:
                    log.write(request.removeprefix("/dispatch ") + "\n")
                reply = "ok"
            else:
                reply = json.dumps(desktop.get(request, "unknown request"))
            connection.sendall(reply.encode())


def hyprland(window_pid: int | None, workspace: int = 1) -> None:
    """Has Hyprland running, with one window or none; workspace 1 is shown.

    Until then, and again after each test, none is: without its lock file
    the instance doesn't count.
    """
    window = {
        "address": "0xabc",
        "pid": window_pid,
        "mapped": True,
        "hidden": False,
        "focusHistoryID": 0,
        "workspace": {"id": workspace},
    }
    desktop["j/clients"] = [window] if window_pid else []
    desktop["j/monitors"] = [
        {"activeWorkspace": {"id": 1}, "specialWorkspace": {"id": 0}}
    ]
    (HYPR / "live" / "hyprland.lock").write_text(f"{os.getpid()}\nwayland-9\n")


# The notification daemon on the fake session bus: its bus name, None while
# none runs, and how many notifications it has on screen.
daemon: dict = {"owner": None, "displayed": 0}
# The calls made on that bus, as "<method> <arguments>".
bus_log: list[str] = []


def bus_text(text: str) -> bytes:
    return struct.pack("<I", len(text)) + text.encode() + b"\0"


def bus_message(kind: int, fields: dict, signature="", body=b"") -> bytes:
    """A message in the bus's wire format; `fields` are its header fields."""
    if signature:
        fields = fields | {8: signature}
    array = b""
    for code, value in fields.items():
        array += b"\0" * (-len(array) % 8)
        if isinstance(value, int):
            array += bytes([code, 1, ord("u"), 0]) + struct.pack("<I", value)
        elif code == 8:
            array += bytes([code, 1, ord("g"), 0, len(value)])
            array += value.encode() + b"\0"
        else:
            kind_of = "o" if code == 1 else "s"
            array += bytes([code, 1, ord(kind_of), 0]) + bus_text(value)
    message = struct.pack("<cBBBIII", b"l", kind, 0, 1, len(body), 1, len(array))
    message += array
    return message + b"\0" * (-len(message) % 8) + body


def bus_fields(array: bytes) -> dict:
    """The header fields of a message, by code."""
    fields, at = {}, 0
    while at < len(array):
        code, kind = array[at], chr(array[at + 2])
        at += 4
        if kind == "g":
            length = array[at]
            fields[code] = array[at + 1 : at + 1 + length].decode()
            at += length + 2
        else:
            (number,) = struct.unpack_from("<I", array, at)
            at += 4
            if kind == "u":
                fields[code] = number
            else:
                fields[code] = array[at : at + number].decode()
                at += number + 1
        at += -at % 8
    return fields


def bus_arguments(body: bytes, signature: str) -> list:
    """The arguments of a call: strings and 32-bit numbers."""
    arguments, at = [], 0
    for kind in signature:
        at += -at % 4
        (number,) = struct.unpack_from("<I", body, at)
        at += 4
        if kind == "s":
            arguments.append(body[at : at + number].decode())
            at += number + 1
        else:
            arguments.append(number)
    return arguments


def answer_bus(connection: socket.socket) -> None:
    """Answers one connection as the bus and as dunst would."""
    with connection, connection.makefile("rb") as stream, suppress(OSError):
        while (line := stream.readline()) != b"BEGIN\r\n":
            if not line:
                return
            if b"AUTH" in line:
                connection.sendall(b"OK 0123456789abcdef\r\n")
        while header := stream.read(16):
            body_length, serial, fields_length = struct.unpack("<4xIII", header)
            fields = bus_fields(stream.read(fields_length))
            stream.read(-fields_length % 8)
            arguments = bus_arguments(
                stream.read(body_length), fields.get(8, "")
            )
            method, reply = fields[3], {5: serial}
            if method == "Hello":
                # The bus says so twice, the second time in a signal.
                named = {1: "/org/freedesktop/DBus", 2: "org.freedesktop.DBus"}
                named |= {3: "NameAcquired"}
                answer = bus_message(2, reply, "s", bus_text(":1.99"))
                answer += bus_message(4, named, "s", bus_text(":1.99"))
                connection.sendall(answer)
                continue
            bus_log.append(" ".join([method, *map(str, arguments)]))
            if method == "GetNameOwner" and not daemon["owner"]:
                error = "org.freedesktop.DBus.Error.NameHasNoOwner"
                answer = bus_message(3, reply | {4: error})
            elif method == "GetNameOwner":
                answer = bus_message(2, reply, "s", bus_text(daemon["owner"]))
            elif method == "Get":
                shown = b"\1u\0\0" + struct.pack("<I", daemon["displayed"])
                answer = bus_message(2, reply, "v", shown)
            else:
                answer = bus_message(2, reply)
            connection.sendall(answer)


def serve_bus(listener: socket.socket) -> None:
    while True:
        connection, _ = listener.accept()
        threading.Thread(
            target=answer_bus, args=[connection], daemon=True
        ).start()


def bus_calls(method: str) -> list[str]:
    return [call for call in bus_log if call.startswith(method)]


# A byte for each signal this process gets, written by Python itself.
signals, signalled = os.pipe()


def bar_refreshes() -> int:
    """How often notifi has signalled the bar since this was last asked."""
    try:
        return os.read(signals, 4096).count(BAR_SIGNAL)
    except BlockingIOError:
        return 0


def read(name: str) -> str:
    return (LOGS / name).read_text() if (LOGS / name).exists() else ""


def deliveries() -> list[list[str]]:
    lines = filter(None, read("notify-send.log").split("\n"))
    return [line.split("\x1f")[:-1] for line in lines]


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


def bar() -> tuple[str, str] | None:
    """What waybar shows: the count and its class, or None while hidden."""
    out = notifi(None, "pending", "--waybar")
    if not out:
        return None
    module = json.loads(out)
    return module["text"], module["class"]


def pane_of(server: Server, target: str) -> str:
    return tmux(server, "display-message", "-p", "-t", target, "#{pane_id}")


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def setUpModule() -> None:
    # From its directory, where .cargo/config.toml is.
    subprocess.run(
        ["cargo", "build", "--release", "--locked"], cwd=CRATE, check=True
    )
    for directory in (BIN, LOGS, HYPR / "live", HYPR / "stale"):
        directory.mkdir(parents=True)
    Path("/proc/self/comm").write_text(BAR)
    for end in (signals, signalled):
        os.set_blocking(end, False)
    signal.signal(BAR_SIGNAL, lambda *_: None)
    signal.set_wakeup_fd(signalled)
    bus = socket.socket(socket.AF_UNIX)
    bus.bind(str(ROOT / "bus"))
    bus.listen()
    threading.Thread(target=serve_bus, args=[bus], daemon=True).start()
    for name, script in STUBS.items():
        (BIN / name).write_text(f"#!/bin/sh{script}")
        (BIN / name).chmod(0o755)
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(str(HYPR / "live" / ".socket.sock"))
    listener.listen()
    threading.Thread(
        target=serve_hyprland, args=[listener], daemon=True
    ).start()
    # A Hyprland that crashed leaves its directory behind. Its lock is the
    # newest here, so only the dead pid tells that it is gone.
    crashed = subprocess.Popen(["true"])
    crashed.wait()
    lock = HYPR / "stale" / "hyprland.lock"
    lock.write_text(f"{crashed.pid}\nwayland-1\n")
    later = time.time() + 3600
    os.utime(lock, (later, later))
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
        (HYPR / "live" / "hyprland.lock").unlink(missing_ok=True)
        shutil.rmtree(LOGS)
        LOGS.mkdir()
        daemon.update(owner=None, displayed=0)
        bus_log.clear()
        bar_refreshes()

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
        notifi(self.local, "show", "--event=attention")
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
        daemon["owner"] = ":1.5"
        notifi(self.local, "show", "--event", "attention")
        (first,) = showing()
        notifi(self.local, "show")
        (second,) = showing()
        self.assertNotEqual(first, second)
        self.assertFalse(alive(first))
        self.assertEqual(len(bus_calls("CloseNotification")), 1)

        hyprland(attach("test"))
        self.assertEqual(notifi(self.local, "show", "-v"), "visible")
        self.assertEqual(showing(), [])
        self.assertFalse(alive(second))
        self.assertEqual(len(bus_calls("CloseNotification")), 2)

    def test_focus_after_a_hyprland_restart_reuses_the_live_window(self):
        hyprland(attach("other"))
        notifi(
            self.local,
            "show",
            # Left behind in tmux by the previous Hyprland.
            HYPRLAND_INSTANCE_SIGNATURE="stale",
            NOTIFI_TEST_ACTION="focus",
        )
        until(lambda: read("dispatch.log"))
        self.assertEqual(
            read("dispatch.log"), 'hl.dsp.focus({ window = "address:0xabc" })\n'
        )
        until(lambda: client_sessions() == "test")
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
        window = ["display-message", "-p", "-t", "test", "#{window_id}"]
        until(lambda: tmux(self.local, *window) == self.local.window_id)
        tmux(self.local, "kill-window", "-t", "test:1")

    def test_dismiss_closes_it_unless_the_daemon_that_issued_it_is_gone(self):
        daemon["owner"] = ":1.5"
        notifi(self.local, "show")
        (pid,) = showing()
        notifi(self.local, "dismiss")
        self.assertEqual(showing(), [])
        self.assertFalse(alive(pid))
        (close,) = bus_calls("CloseNotification")
        self.assertEqual(close, "CloseNotification 7")
        notifi(self.local, "dismiss")  # nothing left to close
        self.assertEqual(len(bus_calls("GetNameOwner")), 2)

        notifi(self.local, "show")
        (pid,) = showing()
        daemon["owner"] = ":1.6"  # dunst restarted
        notifi(self.local, "dismiss")
        self.assertFalse(alive(pid))
        self.assertEqual(len(bus_calls("CloseNotification")), 1)

    def test_closing_the_notification_leaves_the_agent_pending(self):
        notifi(self.local, "show", "--event", "attention")
        self.assertEqual(notifi(None, "pending"), "")
        self.assertEqual(bar_refreshes(), 0)
        close_notifications()
        self.assertEqual(
            notifi(None, "pending"), "test:0\tNeeds Input\tpending"
        )
        self.assertEqual(bar(), ("1", "pending"))
        self.assertEqual(bar_refreshes(), 1)

        notifi(self.local, "dismiss")
        self.assertEqual(records(), [])
        self.assertIsNone(bar())
        self.assertEqual(bus_calls("CloseNotification"), [])
        self.assertEqual(bar_refreshes(), 1)

    def test_a_new_notification_ends_the_pending_state(self):
        notifi(self.local, "show")
        close_notifications()
        notifi(self.local, "show", "--event", "error")
        self.assertEqual(len(showing()), 1)
        self.assertEqual(notifi(None, "pending"), "")

        close_notifications()
        self.assertEqual(
            notifi(None, "pending"), "test:0\tTask Failed\tpending"
        )
        hyprland(attach("test"))
        self.assertEqual(notifi(self.local, "show", "-v"), "visible")
        self.assertEqual(records(), [])

    def test_only_a_pane_whose_notification_never_expires_stays_pending(self):
        notifi(self.local, "show", "--event", "aborted")
        notifi(None, "show", "--app", "claude", "--event", "error")
        self.assertEqual(len(showing()), 2)
        close_notifications()
        self.assertEqual(records(), [])

        # Nor does a record that its waiter never got to remove.
        notifi(self.local, "show")
        close_notifications()
        (record,) = STATE.glob("*.json")
        left = json.loads(record.read_text()) | {"event": "aborted"}
        record.write_text(json.dumps(left))
        self.assertIsNone(bar())
        self.assertEqual(records(), [])

    def test_closing_it_with_the_pane_on_screen_leaves_nothing_pending(self):
        notifi(self.local, "show", "--event", "error")
        hyprland(attach("test"))  # the user went to look
        close_notifications()
        self.assertEqual(records(), [])

    def test_next_goes_to_the_pending_agents_then_round_the_seen_ones(self):
        other = pane_of(self.local, "other:")
        notifi(self.local, "show", "--event", "error", TMUX_PANE=other)
        notifi(self.local, "show")
        close_notifications()
        self.assertEqual(
            notifi(None, "pending"),
            "other:0\tTask Failed\tpending\ntest:0\tTask Finished\tpending",
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
        self.assertEqual(bar(), ("2", "pending"))

        hyprland(attach("test"))
        self.assertEqual(notifi(None, "next"), "other:0")
        self.assertEqual(client_sessions(), "other")
        self.assertEqual(
            read("dispatch.log"), 'hl.dsp.focus({ window = "address:0xabc" })\n'
        )
        self.assertEqual(
            notifi(None, "pending"),
            "test:0\tTask Finished\tpending\nother:0\tTask Failed\tseen",
        )
        self.assertEqual(bar(), ("1", "pending"))
        self.assertEqual(notifi(None, "next"), "test:0")
        self.assertEqual(client_sessions(), "test")
        self.assertEqual(bar(), ("2", "seen"))

        # Both were gone to: it keeps going round them.
        for title in ("other:0", "test:0", "other:0"):
            self.assertEqual(notifi(None, "next"), title)
        # Only the agent's own dismiss, or the user's, ends it.
        notifi(self.local, "dismiss", TMUX_PANE=other)
        self.assertEqual(notifi(None, "pending"), "test:0\tTask Finished\tseen")

    def test_go_runs_the_action_on_screen_or_else_goes_to_the_next(self):
        notifi(self.local, "show")
        close_notifications()
        hyprland(attach("other"))
        daemon["displayed"] = 1  # someone's notification, maybe not ours
        self.assertEqual(notifi(None, "go"), "")
        self.assertEqual(bus_calls("NotificationAction"), ["NotificationAction 0"])
        self.assertEqual(read("dispatch.log"), "")
        self.assertEqual(bar(), ("1", "pending"))

        daemon["displayed"] = 0
        self.assertEqual(notifi(None, "go"), "test:0")
        self.assertEqual(client_sessions(), "test")
        self.assertEqual(len(bus_calls("NotificationAction")), 1)
        # Nor does it need the bus, or dunst on it.
        nowhere = f"unix:path={ROOT / 'none'}"
        out = notifi(None, "go", DBUS_SESSION_BUS_ADDRESS=nowhere)
        self.assertEqual(out, "test:0")
        self.assertEqual(bar(), ("1", "seen"))

    def test_the_focus_action_leaves_the_agent_seen(self):
        hyprland(attach("other"))
        notifi(self.local, "show", NOTIFI_TEST_ACTION="focus")
        until(lambda: bar() == ("1", "seen"))
        self.assertEqual(client_sessions(), "test")

        # Not one whose notification expires.
        notifi(self.local, "dismiss")
        notifi(
            self.local, "show", "--event", "aborted", NOTIFI_TEST_ACTION="focus"
        )
        until(lambda: records() == [])

    def test_dismiss_focused_forgets_the_agent_in_the_focused_window(self):
        tmux(self.local, "split-window", "-d", "-t", "test:0", "/bin/sh")
        beside = pane_of(self.local, "test:0.1")
        self.addCleanup(tmux, self.local, "kill-pane", "-t", beside)
        other = pane_of(self.local, "other:")
        for pane in (self.local.pane_id, beside, other):
            notifi(self.local, "show", "--event", "error", TMUX_PANE=pane)
        close_notifications()
        self.assertEqual(bar(), ("3", "pending"))
        hyprland(None)  # no window at all
        self.assertEqual(notifi(None, "dismiss", "--focused"), "")

        # Its active pane, when that has an agent.
        client = attach("test")
        hyprland(client, workspace=2)  # focused last, but not on screen
        self.assertEqual(notifi(None, "dismiss", "--focused"), "")
        hyprland(client)
        self.assertEqual(notifi(None, "dismiss", "--focused"), "test:0")
        self.assertEqual(
            sorted(record["pane"] for record in records()),
            sorted([beside, other]),
        )
        # Otherwise every agent in that tmux window, whatever its state.
        notifi(self.local, "show", "--event", "error")
        notifi(self.local, "dismiss")
        notifi(self.local, "show", "--event", "error", TMUX_PANE=beside)
        self.assertEqual(notifi(None, "dismiss", "--focused"), "test:0")
        self.assertEqual(showing(), [])
        self.assertEqual([record["pane"] for record in records()], [other])
        self.assertEqual(notifi(None, "dismiss", "--focused"), "")

    def test_a_pane_that_died_is_no_longer_pending(self):
        tmux(self.local, "new-window", "-d", "-t", "test:", "/bin/sh")
        doomed = pane_of(self.local, "test:1")
        notifi(self.local, "show", TMUX_PANE=doomed)
        notifi(self.local, "show", "--event", "attention")
        close_notifications()
        self.assertEqual(bar(), ("2", "pending"))
        tmux(self.local, "kill-window", "-t", "test:1")  # no dismiss
        self.assertEqual(
            notifi(None, "pending"), "test:0\tNeeds Input\tpending"
        )
        self.assertEqual(len(records()), 1)

        # A later tmux server on the same socket numbers its panes from %0
        # again, so the record of an earlier one must not pass for them.
        (record,) = STATE.glob("*.json")
        earlier = json.loads(record.read_text()) | {"server": "1"}
        record.write_text(json.dumps(earlier))
        self.assertEqual(notifi(None, "pending"), "")
        self.assertEqual(records(), [])

    def test_a_notification_lost_with_its_daemon_is_pending(self):
        daemon["owner"] = ":1.5"
        notifi(self.local, "show")
        (pid,) = showing()
        self.assertIsNone(bar())
        daemon["owner"] = ":1.6"  # dunst restarted
        self.assertEqual(bar(), ("1", "pending"))

        hyprland(attach("other"))
        self.assertEqual(notifi(None, "next"), "test:0")
        until(lambda: not alive(pid))  # the notify-send left behind
        self.assertEqual(bus_calls("CloseNotification"), [])
        self.assertEqual(bar(), ("1", "seen"))

    def test_usage_errors_never_exit_with_status_2(self):
        # Claude Code treats exit status 2 from a hook as "block".
        for args in (
            [],
            ["bogus"],
            ["show", "--event", "nope"],
            ["show", "--event"],
            ["show", "--bogus"],
            ["show", "extra"],
            ["next", "--waybar"],
        ):
            done = subprocess.run(
                [str(NOTIFI), *args], env=base_env(), capture_output=True
            )
            self.assertEqual(done.returncode, 1, args)
            self.assertIn(b"notifi", done.stderr, args)
        self.assertEqual(deliveries(), [])
        self.assertIn("notifi show", notifi(None, "--help"))


if __name__ == "__main__":
    unittest.main()
