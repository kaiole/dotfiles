//! `show`: the notification, and the waiter that stays behind with it.

use std::env;
use std::fs;
use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use crate::agents::{self, Event};
use crate::dbus::Daemon;
use crate::run::{self, Running};
use crate::state::{self, State};
use crate::tmux::{self, Look};
use crate::{desktop, hyprland};

const SSH_VARIABLES: [&str; 3] = ["SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT"];

/// Whether this agent may notify the local desktop.
///
/// A tmux server can be told with `set-option -s @notifi-desktop on|off`;
/// by default (`auto`) it may unless it was started over SSH. The server's
/// global environment is checked rather than the agent's, which can keep
/// stale SSH variables after a reattach.
pub enum Desktop {
    Known(bool),
    /// tmux was asked for the option and for its environment.
    Asked(Running, Running),
}

impl Desktop {
    pub fn ask() -> Desktop {
        let set = |name: &&str| env::var_os(name).is_some_and(|value| !value.is_empty());
        if !set(&"TMUX") {
            return Desktop::Known(!SSH_VARIABLES.iter().any(set));
        }
        let Some(socket) = tmux::socket() else {
            return Desktop::Known(false);
        };
        Desktop::Asked(
            tmux::start(&socket, &["show-options", "-sqv", "@notifi-desktop"]),
            tmux::start(&socket, &["show-environment", "-g"]),
        )
    }

    pub fn allowed(self) -> bool {
        let (mode, environment) = match self {
            Desktop::Known(allowed) => return allowed,
            Desktop::Asked(mode, environment) => (mode, environment),
        };
        let over_ssh = |line: &str| {
            let value = |name| line.strip_prefix(name)?.strip_prefix('=');
            SSH_VARIABLES
                .iter()
                .any(|name| value(name).is_some_and(|v| !v.is_empty()))
        };
        match mode
            .finish()
            .map(|mode| mode.trim().to_lowercase())
            .as_deref()
        {
            Some("on") => true,
            Some("" | "auto") => environment
                .finish()
                .is_some_and(|environment| !environment.lines().any(over_ssh)),
            _ => false, // off, unreachable, or invalid
        }
    }
}

/// Shows a notification; returns `sent` or why it was not sent.
pub fn show(app: &str, event: &'static Event, force: bool) -> String {
    let (desktop, look) = (Desktop::ask(), tmux::look(false));
    if !desktop.allowed() {
        return "blocked".into();
    }
    let own = look.and_then(Look::finish);
    let pane = own.as_ref().map(|(pane, _)| pane);
    let path = state::path(app);
    let mut command = Command::new("notify-send");
    command
        .arg(format!("--app-name={app}"))
        .arg(format!("--urgency={}", event.urgency))
        .arg(format!("--expire-time={}", event.expire_ms))
        .args(["--print-id", "--wait"])
        .args(pane.map(|_| "--action=focus=Focus"))
        .args(["--", pane.map_or(app, |pane| &pane.title), event.body])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    run::detach(&mut command);

    let lock = state::lock();
    let mut daemon = Daemon::default();
    // Whatever the agent was waiting with is stale: it has moved on, or the
    // user is looking at it.
    agents::close(&path, &mut daemon);
    if let Some((pane, server)) = &own
        && event.focus_aware
        && !force
        && hyprland::snapshot().is_some_and(|hypr| desktop::visible(pane, &hypr, &server.clients))
    {
        return "visible".into();
    }

    // notify-send --wait lives exactly as long as the notification. It
    // prints the id at once and the chosen action, if any, at the end.
    let mut sender = match command.spawn() {
        Ok(sender) => sender,
        Err(error) => return format!("failed: {error}"),
    };
    let (Some(mut stdout), Some(mut stderr)) = (sender.stdout.take(), sender.stderr.take()) else {
        return "failed: notify-send has no output".into();
    };
    let deadline = Instant::now() + Duration::from_secs(5);
    let (mut printed, mut chunk) = (Vec::new(), [0; 256]);
    while !printed.contains(&b'\n') && run::readable(&stdout, deadline) {
        match stdout.read(&mut chunk) {
            Ok(count) if count > 0 => printed.extend(&chunk[..count]),
            _ => break,
        }
    }
    let mut lines = printed.splitn(2, |byte| *byte == b'\n');
    let id = String::from_utf8_lossy(lines.next().unwrap_or_default());
    let mut printed = lines.next().unwrap_or_default().to_vec();
    if id.trim().is_empty() {
        let _ = sender.kill();
        let mut reason = String::new();
        let _ = stderr.read_to_string(&mut reason);
        let reason = Some(reason.trim()).filter(|reason| !reason.is_empty());
        return format!("failed: {}", reason.unwrap_or("notify-send printed no id"));
    }
    let pid = sender.id() as i32;
    let mut state = State::new();
    state.insert("event".into(), event.name.into());
    state.insert("since".into(), state::now().into());
    let toast = json!({
        "id": id.trim(),
        "owner": daemon.owner(),
        "pid": pid,
        "started": run::start_time(pid),
    });
    state.insert("toast".into(), toast);
    if let Some(pane) = pane {
        state.insert("socket".into(), pane.socket.as_str().into());
        state.insert("pane".into(), pane.id.as_str().into());
        state.insert("server".into(), pane.server.as_str().into());
    }
    state::write(&path, &state);
    // Not for the waiter to keep.
    drop((lock, daemon));

    // The caller (an agent hook) must not wait for the notification, so a
    // detached child stays behind for the action.
    if unsafe { libc::fork() } != 0 {
        return "sent".into();
    }
    unsafe {
        libc::setsid();
        let null = libc::open(c"/dev/null".as_ptr(), libc::O_RDWR);
        for stream in 0..3 {
            libc::dup2(null, stream);
        }
    }
    let _ = stdout.read_to_end(&mut printed);
    let printed = String::from_utf8_lossy(&printed);
    let acted = printed.split_whitespace().any(|word| word == "focus");
    let (look, hypr) = (tmux::look(acted), hyprland::snapshot());
    // The agent is still waiting, so its record stays: seen after the
    // action, pending if the notification was only closed. Not if it was
    // closed with the pane on screen, which takes no going to; nor if the
    // notification expires, because a timeout looks the same as a close
    // from here.
    let mut keep = false;
    if let Some((pane, mut server)) = look.and_then(Look::finish) {
        let visible = hypr.as_ref().is_some_and(|hypr| {
            if acted {
                desktop::focus(&pane, hypr, &mut server).finish();
            }
            desktop::visible(&pane, hypr, &server.clients)
        });
        keep = event.expire_ms == 0 && (acted || !visible);
    }
    let _lock = state::lock();
    let mut state = state::read(&path).unwrap_or_default();
    let recorded = state::toast(&state).and_then(|toast| toast.get("pid"));
    if recorded.and_then(Value::as_i64) == Some(pid.into()) {
        if keep {
            state.remove("toast");
            if acted {
                state.insert("seen".into(), state::now().into());
            }
            state::write(&path, &state);
        } else {
            let _ = fs::remove_file(&path);
        }
        state::refresh_bar();
    }
    // notify-send had this end of its stderr until now.
    drop(stderr);
    unsafe { libc::_exit(0) }
}
