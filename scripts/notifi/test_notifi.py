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
    # tmux asks systemd, on the session bus, for a scope to start each
    # pane's command in, and waits for it: the bus here would never finish
    # that, so the servers get none and start their commands as they are.
    env = base_env() | {
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path={ROOT / 'none'}"
    }
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


def notifi(
    server: Server | None, *args: str, stdin: str = "", **extra: str
) -> str:
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
        input=stdin,
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


def attach(session: str, server: Server | None = None) -> int:
    """Attaches a real tmux client, standing in for a Ghostty window.

    To the local server, unless another is given. Its terminal has focus,
    as far as tmux knows, until `blur` says otherwise.
    """
    server = server or servers["local"]
    command = f"exec tmux -S '{server.socket}' attach-session -t {session}"
    client = subprocess.Popen(
        ["script", "-qfc", command, "/dev/null"],
        env=base_env(),
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    clients.append(client)
    until(lambda: session in client_sessions(server).split("\n"))
    return client.pid


def client_sessions(server: Server | None = None) -> str:
    server = server or servers["local"]
    return tmux(server, "list-clients", "-F", "#{session_name}")


def blur(server: Server) -> None:
    """The terminal of the client attached last loses focus, and says so."""
    clients[-1].stdin.write(b"\x1b[O")
    clients[-1].stdin.flush()
    flags = lambda: tmux(server, "list-clients", "-F", "#{client_flags}")
    until(lambda: "focused" not in flags())


def marks(server: Server) -> dict[str, str]:
    """What each pane of a server says its agent is, for tmux's status line."""
    panes = tmux(server, "list-panes", "-a", "-F", "#{pane_id}=#{@notifi}")
    said = (pane.partition("=") for pane in panes.split("\n"))
    return {pane: mark for pane, _, mark in said if mark}


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
    message = struct.pack(
        "<cBBBIII", b"l", kind, 0, 1, len(body), 1, len(array)
    )
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


def module(state: str) -> tuple[int, str]:
    """One of waybar's agent modules: its count and its tooltip."""
    shown = json.loads(notifi(None, state, "--waybar"))
    if shown["text"] == "0":
        none = {"text": "0", "class": "none"}
        assert shown == none | {"tooltip": f"No agent {state}"}, shown
        return 0, ""
    assert shown["class"] == state, shown
    return int(shown["text"]), shown["tooltip"]


def bar() -> tuple[int, int]:
    """How many agents waybar shows as pending and as seen."""
    return module("pending")[0], module("seen")[0]


def working() -> tuple[str, str] | None:
    """What waybar shows of the agents at work: the count and the tooltip."""
    count, tooltip = module("running")
    return (str(count), tooltip) if count else None


TRANSCRIPT = ROOT / "transcript.jsonl"


def hook(event: str) -> str:
    """What Claude Code gives a hook on its standard input."""
    return json.dumps(
        {"hook_event_name": event, "transcript_path": str(TRANSCRIPT)}
    )


def transcribe(*rows: dict) -> None:
    """Adds rows to the transcript, as Claude Code does during a turn."""
    with TRANSCRIPT.open("a") as transcript:
        for row in rows:
            transcript.write(json.dumps(row) + "\n")


def said(who: str, *content: dict | str) -> dict:
    """A turn in the transcript: its text, or its blocks."""
    text = len(content) == 1 and isinstance(content[0], str)
    content = content[0] if text else list(content)
    return {"type": who, "message": {"role": who, "content": content}}


INTERRUPTED = {"type": "text", "text": "[Request interrupted by user]"}
TOOL_INTERRUPTED = [
    said("assistant", {"type": "tool_use", "id": "1", "name": "Bash"}),
    said("user", {"type": "tool_result", "tool_use_id": "1", "content": "no"}),
    said(
        "user",
        {"type": "text", "text": "[Request interrupted by user for tool use]"},
    ),
    {"type": "system", "subtype": "turn_duration"},
]


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
        for server in servers.values():
            until(lambda server=server: client_sessions(server) == "")
            tmux(server, "set-option", "-su", "@notifi-desktop")
            for pane in marks(server):
                tmux(server, "set-option", "-pu", "-t", pane, "@notifi")
        tmux(self.local, "select-window", "-t", self.local.window_id)
        (HYPR / "live" / "hyprland.lock").unlink(missing_ok=True)
        shutil.rmtree(LOGS)
        LOGS.mkdir()
        TRANSCRIPT.unlink(missing_ok=True)
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

    def test_ssh_started_server_keeps_the_agent_without_a_notification(self):
        pane = self.remote.pane_id
        for event, body in (
            ("finished", "Task Finished"),
            ("attention", "Needs Input"),
            ("error", "Task Failed"),
        ):
            outcome = notifi(self.remote, "show", "--event", event, "-v")
            self.assertEqual(outcome, "kept")
            self.assertEqual(
                notifi(None, "pending"), f"test:0\t{body}\tpending"
            )
            self.assertEqual(marks(self.remote), {pane: "pending"})
        # One whose notification would expire is seen as it is.
        outcome = notifi(self.remote, "show", "--event", "aborted", "-v")
        self.assertEqual(outcome, "kept")
        self.assertEqual(notifi(None, "pending"), "test:0\tTask Aborted\tseen")
        self.assertEqual(marks(self.remote), {pane: "seen"})

        # In view is what tmux knows of it: a client with focus on its
        # window, whatever the event.
        attach("test", self.remote)
        outcome = notifi(self.remote, "show", "--event", "error", "-v")
        self.assertEqual(outcome, "visible")
        self.assertEqual(marks(self.remote), {pane: "seen"})
        outcome = notifi(self.remote, "show", "--force", "-v")
        self.assertEqual(outcome, "kept")
        self.assertEqual(marks(self.remote), {pane: "pending"})
        blur(self.remote)
        self.assertEqual(notifi(self.remote, "show", "-v"), "kept")
        self.assertEqual(bar(), (1, 0))

        self.assertEqual(deliveries(), [])
        self.assertEqual(notifi(self.remote, "status"), "blocked")
        self.assertEqual(notifi(self.local, "status"), "allowed")
        notifi(self.remote, "dismiss")
        self.assertEqual(records(), [])
        self.assertEqual(marks(self.remote), {})

    def test_notifi_desktop_option_is_read_per_notification(self):
        for mode in ("off", "invalid"):
            tmux(self.local, "set-option", "-s", "@notifi-desktop", mode)
            outcome = notifi(self.local, "show", "--event", "error", "-v")
            self.assertEqual(outcome, "kept")
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
            # It stopped in view: nothing to go to, but it still waits.
            self.assertEqual(bar(), (0, 1))
            self.assertGreaterEqual(bar_refreshes(), 1)
        self.assertEqual(deliveries(), [])
        self.assertEqual(notifi(None, "pending"), "test:0\tNeeds Input\tseen")
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
        self.assertEqual(bar(), (1, 0))
        self.assertEqual(bar_refreshes(), 1)

        notifi(self.local, "dismiss")
        self.assertEqual(records(), [])
        self.assertEqual(bar(), (0, 0))
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
        self.assertEqual(notifi(None, "pending"), "test:0\tTask Finished\tseen")

    def test_a_notification_that_expires_leaves_the_agent_seen(self):
        notifi(self.local, "show", "--event", "aborted")
        # Outside tmux there is no pane to go back to: nothing is kept.
        notifi(None, "show", "--app", "claude", "--event", "error")
        self.assertEqual(len(showing()), 2)
        close_notifications()  # or a timeout, which looks the same
        self.assertEqual(notifi(None, "pending"), "test:0\tTask Aborted\tseen")
        self.assertEqual(len(records()), 1)

    def test_closing_it_with_the_pane_on_screen_leaves_the_agent_seen(self):
        notifi(self.local, "show", "--event", "error")
        hyprland(attach("test"))  # the user went to look
        close_notifications()
        self.assertEqual(notifi(None, "pending"), "test:0\tTask Failed\tseen")

        # Only a dismiss forgets it.
        notifi(self.local, "dismiss")
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
        self.assertEqual(bar(), (2, 0))

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
        self.assertEqual(bar(), (1, 1))
        self.assertEqual(module("pending"), (1, "test:0\tTask Finished"))
        self.assertEqual(module("seen"), (1, "other:0\tTask Failed"))
        self.assertEqual(notifi(None, "seen"), "other:0\tTask Failed")
        self.assertEqual(notifi(None, "next"), "test:0")
        self.assertEqual(client_sessions(), "test")
        self.assertEqual(bar(), (0, 2))

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
        self.assertEqual(
            bus_calls("NotificationAction"), ["NotificationAction 0"]
        )
        self.assertEqual(read("dispatch.log"), "")
        self.assertEqual(bar(), (1, 0))

        daemon["displayed"] = 0
        self.assertEqual(notifi(None, "go"), "test:0")
        self.assertEqual(client_sessions(), "test")
        self.assertEqual(len(bus_calls("NotificationAction")), 1)
        # Nor does it need the bus, or dunst on it.
        nowhere = f"unix:path={ROOT / 'none'}"
        out = notifi(None, "go", DBUS_SESSION_BUS_ADDRESS=nowhere)
        self.assertEqual(out, "test:0")
        self.assertEqual(bar(), (0, 1))

    def test_the_focus_action_leaves_the_agent_seen(self):
        hyprland(attach("other"))
        notifi(self.local, "show", NOTIFI_TEST_ACTION="focus")
        until(lambda: bar() == (0, 1))
        self.assertEqual(client_sessions(), "test")

        # So does one whose notification expires.
        notifi(self.local, "dismiss")
        notifi(
            self.local, "show", "--event", "aborted", NOTIFI_TEST_ACTION="focus"
        )
        until(lambda: notifi(None, "pending") == "test:0\tTask Aborted\tseen")

    def test_dismiss_focused_forgets_the_agent_in_the_focused_window(self):
        tmux(self.local, "split-window", "-d", "-t", "test:0", "/bin/sh")
        beside = pane_of(self.local, "test:0.1")
        self.addCleanup(tmux, self.local, "kill-pane", "-t", beside)
        other = pane_of(self.local, "other:")
        for pane in (self.local.pane_id, beside, other):
            notifi(self.local, "show", "--event", "error", TMUX_PANE=pane)
        close_notifications()
        self.assertEqual(bar(), (3, 0))
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

    def test_an_agent_that_starts_is_running_until_it_stops(self):
        notifi(self.local, "show", "--event", "attention")
        (pid,) = showing()
        notifi(self.local, "start", "--app", "pi")  # answered
        self.assertFalse(alive(pid))
        self.assertEqual(notifi(None, "running"), "test:0\t<1m")
        self.assertEqual(working(), ("1", "test:0\t&lt;1m"))
        self.assertEqual(bar_refreshes(), 1)
        # Nothing to go to, and it is not waiting.
        self.assertEqual(notifi(None, "pending"), "")
        self.assertEqual(bar(), (0, 0))
        hyprland(attach("other"))
        self.assertEqual(notifi(None, "next"), "")
        self.assertEqual(client_sessions(), "other")

        # The one at work longest comes first.
        (record,) = STATE.glob("*.json")
        earlier = json.loads(record.read_text())
        record.write_text(
            json.dumps(earlier | {"since": earlier["since"] - 3900})
        )
        notifi(self.local, "start", TMUX_PANE=pane_of(self.local, "other:"))
        self.assertEqual(working(), ("2", "test:0\t1h05m\nother:0\t&lt;1m"))

        notifi(self.local, "show")
        self.assertEqual(notifi(None, "running"), "other:0\t<1m")
        close_notifications()
        self.assertEqual(bar(), (1, 0))
        notifi(self.local, "start")
        self.assertEqual(bar(), (0, 0))
        notifi(self.local, "dismiss")  # it exited
        self.assertEqual(notifi(None, "running"), "other:0\t<1m")

        # Super+X forgets one at work too.
        self.assertEqual(notifi(None, "dismiss", "--focused"), "other:0")
        self.assertEqual(records(), [])
        self.assertIsNone(working())

    def test_start_records_wherever_there_is_a_pane(self):
        notifi(None, "start", "--app", "claude")
        self.assertEqual(records(), [])
        self.assertEqual(bar_refreshes(), 0)
        # With no desktop to notify, too.
        notifi(self.remote, "start")
        tmux(self.local, "set-option", "-s", "@notifi-desktop", "off")
        notifi(self.local, "start")
        self.assertEqual(working()[0], "2")
        self.assertEqual(marks(self.remote), {self.remote.pane_id: "running"})
        self.assertEqual(marks(self.local), {self.local.pane_id: "running"})
        notifi(self.remote, "dismiss")
        notifi(self.local, "dismiss")
        self.assertEqual(records(), [])

        # Outside tmux it still ends the notification.
        notifi(None, "show", "--app", "claude", "--event", "error")
        notifi(None, "start", "--app", "claude")
        self.assertEqual(showing(), [])
        self.assertEqual(records(), [])

    def test_a_tool_hook_starts_only_an_agent_that_stopped(self):
        after_tool = hook("PostToolUse")
        # Forgotten, or never on record: it stays that way.
        notifi(self.local, "start", "--hook", stdin=after_tool)
        self.assertEqual(records(), [])

        notifi(self.local, "start", "--hook", stdin=hook("UserPromptSubmit"))
        (record,) = records()
        notifi(self.local, "start", "--hook", stdin=after_tool)
        self.assertEqual(records(), [record])  # at work already
        self.assertEqual(bar_refreshes(), 1)

        # It asked, was answered, and went on.
        notifi(self.local, "show", "--event", "attention")
        notifi(self.local, "start", "--hook", stdin=after_tool)
        self.assertEqual(showing(), [])
        self.assertEqual(notifi(None, "running"), "test:0\t<1m")
        # A prompt starts it anew.
        transcribe(said("user", "more"))
        notifi(self.local, "start", "--hook", stdin=hook("UserPromptSubmit"))
        (again,) = records()
        self.assertGreater(again["since"], record["since"])
        self.assertEqual(
            again["running"],
            {
                "transcript": str(TRANSCRIPT),
                "offset": TRANSCRIPT.stat().st_size,
            },
        )

    def test_an_agent_interrupted_at_work_is_seen_as_aborted(self):
        # The turn before was interrupted too, and its prompt is not
        # written yet when the hook runs.
        transcribe(said("user", "first"), said("user", INTERRUPTED))
        notifi(self.local, "start", "--hook", stdin=hook("UserPromptSubmit"))
        self.assertEqual(notifi(None, "running"), "test:0\t<1m")
        transcribe(
            said("user", "second"),
            said("assistant", {"type": "tool_use", "id": "0", "name": "Read"}),
            said("user", {"type": "tool_result", "tool_use_id": "0"}),
            {"type": "api-request"},
        )
        self.assertEqual(notifi(None, "running"), "test:0\t<1m")
        self.assertEqual(bar_refreshes(), 1)

        transcribe(said("user", INTERRUPTED), {"type": "system"})
        self.assertIsNone(working())
        self.assertEqual(bar_refreshes(), 1)
        self.assertEqual(notifi(None, "pending"), "test:0\tTask Aborted\tseen")
        self.assertEqual(deliveries(), [])

        # During a tool, and with more before it than is read.
        notifi(self.local, "start", "--hook", stdin=hook("UserPromptSubmit"))
        transcribe(said("user", "x" * 100_000), *TOOL_INTERRUPTED)
        self.assertEqual(notifi(None, "running"), "")
        self.assertEqual(bar(), (0, 1))

        # Without a transcript it runs until it says otherwise.
        notifi(self.local, "start")
        transcribe(said("user", INTERRUPTED))
        self.assertEqual(notifi(None, "running"), "test:0\t<1m")

    def test_a_pane_that_died_is_no_longer_pending(self):
        tmux(self.local, "new-window", "-d", "-t", "test:", "/bin/sh")
        doomed = pane_of(self.local, "test:1")
        notifi(self.local, "show", TMUX_PANE=doomed)
        notifi(self.local, "show", "--event", "attention")
        close_notifications()
        self.assertEqual(bar(), (2, 0))
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
        self.assertEqual(bar(), (0, 0))
        daemon["owner"] = ":1.6"  # dunst restarted
        self.assertEqual(bar(), (1, 0))

        hyprland(attach("other"))
        self.assertEqual(notifi(None, "next"), "test:0")
        until(lambda: not alive(pid))  # the notify-send left behind
        self.assertEqual(bus_calls("CloseNotification"), [])
        self.assertEqual(bar(), (0, 1))

    def test_each_pane_says_what_its_agent_is(self):
        pane = self.local.pane_id
        notifi(self.local, "start")
        self.assertEqual(marks(self.local), {pane: "running"})
        notifi(self.local, "show")
        self.assertEqual(marks(self.local), {pane: "pending"})  # notified
        close_notifications()
        self.assertEqual(marks(self.local), {pane: "pending"})
        hyprland(attach("other"))
        notifi(None, "next")
        self.assertEqual(marks(self.local), {pane: "seen"})
        notifi(self.local, "show", "--event", "aborted")
        self.assertEqual(marks(self.local), {pane: "pending"})
        close_notifications()  # or it expired
        self.assertEqual(marks(self.local), {pane: "seen"})
        notifi(self.local, "dismiss")
        self.assertEqual(marks(self.local), {})

        # Interrupted at work, it is seen once something reads the records.
        notifi(self.local, "start", "--hook", stdin=hook("UserPromptSubmit"))
        transcribe(said("user", INTERRUPTED))
        self.assertEqual(marks(self.local), {pane: "running"})
        self.assertEqual(bar(), (0, 1))
        self.assertEqual(marks(self.local), {pane: "seen"})
        # Super+X does not wait for tmux to be told.
        self.assertEqual(notifi(None, "dismiss", "--focused"), "test:0")
        until(lambda: marks(self.local) == {})

        # A notification that failed leaves nothing, on the pane either.
        failing = ROOT / "failing"
        failing.mkdir(exist_ok=True)
        (failing / "notify-send").write_text("#!/bin/sh\nexit 1\n")
        (failing / "notify-send").chmod(0o755)
        env = base_env()
        env |= {"TMUX": f"{self.local.socket},{self.local.pid},0"}
        env |= {"TMUX_PANE": pane, "PATH": f"{failing}:{env['PATH']}"}
        done = subprocess.run(
            [str(NOTIFI), "show", "--force"],
            env=env,
            capture_output=True,
            check=False,
        )
        self.assertEqual(done.returncode, 1)
        self.assertIn(b"failed", done.stderr)
        self.assertEqual(marks(self.local), {})

    def test_next_in_tmux_goes_round_its_server_with_no_desktop(self):
        tmux(self.remote, "new-session", "-d", "-s", "other", "/bin/sh")
        self.addCleanup(tmux, self.remote, "kill-session", "-t", "other")
        pane, other = self.remote.pane_id, pane_of(self.remote, "other:")
        notifi(self.remote, "show", "--event", "error", TMUX_PANE=other)
        notifi(self.remote, "show")
        tmux(self.remote, "split-window", "-d", "-t", "other:0", "/bin/sh")
        notifi(
            self.remote, "start", TMUX_PANE=pane_of(self.remote, "other:0.1")
        )
        # Another server's agent is not for this one's key.
        notifi(self.local, "show", "--event", "error")
        close_notifications()
        bar_refreshes()

        attach("test", self.remote)
        # As a key bind runs it: with the session of the client, and
        # nothing printed, which tmux would show over the pane.
        self.assertEqual(notifi(self.remote, "next", "--tmux"), "")
        self.assertEqual(client_sessions(self.remote), "other")
        active = "#{pane_id}"
        self.assertEqual(
            tmux(self.remote, "display-message", "-p", "-t", "other:", active),
            other,
        )
        self.assertEqual(marks(self.remote)[other], "seen")
        self.assertEqual(marks(self.remote)[pane], "pending")
        self.assertEqual(bar_refreshes(), 1)
        notifi(self.remote, "next", "--tmux")
        self.assertEqual(client_sessions(self.remote), "test")
        # Round the seen ones, and never to the one at work.
        for session in ("other", "test", "other"):
            notifi(self.remote, "next", "--tmux")
            self.assertEqual(client_sessions(self.remote), session)
        self.assertEqual(bar(), (1, 2))
        self.assertEqual(notifi(None, "running"), "other:0\t<1m")
        self.assertEqual(read("dispatch.log"), "")
        self.assertEqual(read("ghostty.log"), "")

        # With none it says so, in tmux.
        notifi(self.remote, "dismiss")
        notifi(self.remote, "dismiss", TMUX_PANE=other)
        self.assertEqual(notifi(self.remote, "next", "--tmux"), "")
        self.assertEqual(client_sessions(self.remote), "other")
        self.assertIn("No agent waiting", tmux(self.remote, "show-messages"))
        self.assertEqual(bar(), (1, 0))

    def test_next_in_tmux_takes_an_agent_from_its_notification(self):
        notifi(self.local, "show")
        (sender,) = showing()
        attach("other")
        notifi(self.local, "next", "--tmux", TMUX=self.key("other"))
        self.assertEqual(client_sessions(), "test")
        until(lambda: not alive(sender))
        self.assertEqual(showing(), [])
        self.assertEqual(bar(), (0, 1))
        self.assertEqual(read("dispatch.log"), "")

    def key(self, session: str) -> str:
        """$TMUX as a key bind of the local server has it, on a session."""
        number = tmux(
            self.local,
            "display-message",
            "-p",
            "-t",
            f"{session}:",
            "#{session_id}",
        )
        return f"{self.local.socket},{self.local.pid},{number.lstrip('$')}"

    def pick(self, session: str = "test") -> tuple[str, callable]:
        """Opens the list in a window of the remote server, as its popup
        would; returns its pane and what reads its screen."""
        fields = ["-P", "-F", "#{pane_id}"]
        command = f"exec '{NOTIFI}' pick"
        pane = tmux(
            self.remote,
            "new-window",
            "-d",
            *fields,
            "-t",
            f"{session}:",
            command,
        )
        return pane, lambda: tmux(self.remote, "capture-pane", "-p", "-t", pane)

    def closed(self, pane: str) -> bool:
        panes = tmux(self.remote, "list-panes", "-a", "-F", "#{pane_id}")
        return pane not in panes.split("\n")

    def test_pick_lists_the_agents_of_its_server_to_go_to_or_forget(self):
        tmux(self.remote, "new-session", "-d", "-s", "other", "/bin/sh")
        self.addCleanup(tmux, self.remote, "kill-session", "-t", "other")
        other = pane_of(self.remote, "other:")
        tmux(self.remote, "new-window", "-d", "-t", "other:", "/bin/sh")
        third = pane_of(self.remote, "other:1")

        # With none there is nothing to go to.
        picker, screen = self.pick()
        until(lambda: "running" in screen())
        self.assertEqual(screen().split(), ["pending", "seen", "running"])
        tmux(self.remote, "send-keys", "-t", picker, "Enter", "1", "x")
        time.sleep(2.2)  # read again twice, with nothing pressed
        self.assertFalse(self.closed(picker))
        # It holds no lock, and reads the records again.
        notifi(self.remote, "show", "--event", "error", TMUX_PANE=other)
        until(lambda: "other:0" in screen())
        tmux(self.remote, "send-keys", "-t", picker, "Escape")
        until(lambda: self.closed(picker))

        notifi(self.remote, "show", "--event", "aborted")
        notifi(self.remote, "start", TMUX_PANE=third)
        notifi(self.local, "show", "--event", "attention")  # not this server's
        attach("test", self.remote)
        picker, screen = self.pick()
        # The pending one first, then the seen ones, then those at work.
        until(lambda: "other:1" in screen())
        listed = [" ".join(line.split()) for line in screen().split("\n")]
        self.assertEqual(
            [line for line in listed if line],
            ["pending", "1 other:0 Task Failed <1m"]
            + ["seen", "2 test:0 Task Aborted <1m"]
            + ["running", "3 other:1 <1m"],
        )

        # x forgets the selected one, the second here, and stays.
        tmux(self.remote, "send-keys", "-t", picker, "k", "j", "j", "Up", "x")
        until(lambda: "test:0" not in screen())
        self.assertEqual(
            marks(self.remote), {other: "pending", third: "running"}
        )
        self.assertEqual(len(records()), 3)
        # A number goes to that one; one at work stays at work.
        tmux(self.remote, "send-keys", "-t", picker, "2")
        until(lambda: self.closed(picker))
        self.assertEqual(client_sessions(self.remote), "other")
        window = tmux(
            self.remote, "display-message", "-p", "-t", "other:", "#I"
        )
        self.assertEqual(window, "1")
        self.assertEqual(
            marks(self.remote), {other: "pending", third: "running"}
        )

        # Enter goes to the selected one, which is seen from then on.
        picker, screen = self.pick("other")
        until(lambda: "other:0" in screen())
        tmux(self.remote, "send-keys", "-t", picker, "Enter")
        until(lambda: self.closed(picker))
        window = tmux(
            self.remote, "display-message", "-p", "-t", "other:", "#I"
        )
        self.assertEqual(window, "0")
        self.assertEqual(marks(self.remote), {other: "seen", third: "running"})
        self.assertEqual(notifi(None, "seen"), "other:0\tTask Failed")

        # q closes it and changes nothing.
        picker, screen = self.pick()
        until(lambda: "other:0" in screen())
        tmux(self.remote, "send-keys", "-t", picker, "q")
        until(lambda: self.closed(picker))
        self.assertEqual(marks(self.remote), {other: "seen", third: "running"})
        self.assertEqual(read("dispatch.log"), "")

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
            ["pick", "--tmux"],
            ["start", "--event", "error"],
            ["running", "--hook"],
            ["seen", "--app", "pi"],
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
