//! What an agent says of itself. `show`: it stopped, with the notification
//! and the waiter that stays behind with it, or without one where there is
//! no desktop to notify. `start`: it is at work.

use std::env;
use std::fs;
use std::io::{self, Read};
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

/// Whether this agent may notify the local desktop. Where it may not, an
/// agent in tmux is kept on record all the same, and tmux is what shows it.
///
/// A tmux server can be told with `set-option -s @notifi-desktop on|off`;
/// by default (`auto`) it may unless it was started over SSH. The server's
/// global environment is checked rather than the agent's, which can keep
/// stale SSH variables after a reattach. Only Linux has the desktop that
/// this notifies: elsewhere none may.
pub enum Desktop {
    Known(bool),
    /// tmux was asked for the option and for its environment.
    Asked(Running, Running),
}

impl Desktop {
    pub fn ask() -> Desktop {
        if !cfg!(target_os = "linux") {
            return Desktop::Known(false);
        }
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

/// Records that the agent in this pane is at work, which ends whatever it
/// was waiting with: you answered it.
///
/// With `hook`, the input is what Claude Code gives a hook. A prompt starts
/// the agent anew. The other hooks only say that it is still going, and
/// they come after every tool, so they count for an agent that stopped and
/// went on, as after a question, and cost the others no more than reading
/// the record: one at work already, and one with none, which was
/// forgotten. The transcript is kept for `agents::interrupted`.
pub fn start(app: &str, hook: bool) {
    let mut input = String::new();
    if hook {
        let _ = io::stdin().read_to_string(&mut input);
    }
    let input: Value = serde_json::from_str(&input).unwrap_or_default();
    let path = state::path(app);
    if hook && input["hook_event_name"] != "UserPromptSubmit" {
        let stopped = |state: State| !state.contains_key("running");
        if !state::read(&path).is_some_and(stopped) {
            return;
        }
    }
    let _lock = state::lock();
    let closed = agents::close(&path, &mut Daemon::default()).is_some();
    // Outside tmux there is no pane to tell that it still runs in.
    if let Some(((socket, pane), server)) = tmux::own().zip(tmux::server()) {
        let mut state = State::new();
        state.insert("app".into(), app.into());
        state.insert("since".into(), state::now().into());
        state.insert("socket".into(), socket.into());
        state.insert("pane".into(), pane.into());
        state.insert("server".into(), server.into());
        let transcript = input["transcript_path"].as_str();
        // How long it is now: only what comes after is of this turn.
        let offset = transcript.and_then(|path| fs::metadata(path).ok());
        state.insert(
            "running".into(),
            json!({
                "transcript": transcript,
                "offset": offset.map_or(0, |file| file.len()),
            }),
        );
        state::write(&path, &state);
        state::publish(&state, false).finish();
    } else if !closed {
        return;
    }
    state::refresh_bar();
}

/// Records that the agent in this pane stopped, and shows a notification;
/// returns `sent` or why it was not sent.
pub fn show(app: &str, event: &'static Event, force: bool) -> String {
    let (desktop, look) = (Desktop::ask(), tmux::look(true));
    let desktop = desktop.allowed();
    let mut own = look.and_then(Look::finish);
    // The tmux that answered stays, to have the pane say what is recorded
    // of it: once, on each way out of here.
    let asked = own
        .as_mut()
        .map(|(_, server)| std::mem::take(&mut server.asked));
    let asked = asked.unwrap_or_default();
    let pane = own.as_ref().map(|(pane, _)| pane);
    // Outside tmux the desktop is all there is to tell.
    if !desktop && pane.is_none() {
        return "blocked".into();
    }
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
    // user is looking at it. Nor is it at work any more.
    if agents::close(&path, &mut daemon).is_some() {
        state::refresh_bar();
    }
    let now = state::now();
    let mut state = State::new();
    state.insert("app".into(), app.into());
    state.insert("event".into(), event.name.into());
    state.insert("since".into(), now.into());
    if let Some(pane) = pane {
        state.insert("socket".into(), pane.socket.as_str().into());
        state.insert("pane".into(), pane.id.as_str().into());
        state.insert("server".into(), pane.server.as_str().into());
    }
    if let Some((pane, server)) = &own
        && !desktop
    {
        // No desktop to notify, so the record is all: tmux shows it, by
        // the pane's option. In view is what tmux knows of that, a client
        // with focus on the pane's window, and whatever the event, since
        // there is no notification to show in spite of it. One that would
        // expire is seen as it is there.
        let visible = !force && tmux::visible(pane, &server.clients);
        if visible || event.expire_ms != 0 {
            state.insert("seen".into(), now.into());
        }
        state::write(&path, &state);
        state::publish_by(asked, &state, false);
        state::refresh_bar();
        return if visible { "visible" } else { "kept" }.into();
    }
    if let Some((pane, server)) = &own
        && event.focus_aware
        && !force
        && hyprland::snapshot().is_some_and(|hypr| desktop::visible(pane, &hypr, &server.clients))
    {
        // In view, so there is nothing to go to, but it waits all the same.
        state.insert("seen".into(), now.into());
        state::write(&path, &state);
        state::publish_by(asked, &state, false);
        state::refresh_bar();
        return "visible".into();
    }

    // Without its notification nothing is on record, nor then on the pane.
    let failed = |asked: Running, why: &str| {
        state::publish_by(asked, &state, true);
        format!("failed: {why}")
    };
    // notify-send --wait lives exactly as long as the notification. It
    // prints the id at once and the chosen action, if any, at the end.
    let mut sender = match command.spawn() {
        Ok(sender) => sender,
        Err(error) => return failed(asked, &error.to_string()),
    };
    let (Some(mut stdout), Some(mut stderr)) = (sender.stdout.take(), sender.stderr.take()) else {
        return failed(asked, "notify-send has no output");
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
        return failed(asked, reason.unwrap_or("notify-send printed no id"));
    }
    let pid = sender.id() as i32;
    let toast = json!({
        "id": id.trim(),
        "owner": daemon.owner(),
        "pid": pid,
        "started": run::start_time(pid),
    });
    state.insert("toast".into(), toast);
    state::write(&path, &state);
    // Under the lock, so that the waiter's word for the pane comes after;
    // and that tmux is gone before the waiter could keep it.
    state::publish_by(asked, &state, false);
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
    // The agent is still waiting, so its record stays until a dismiss:
    // pending if the notification was only closed, seen after the action
    // or if the pane was on screen by then, which takes no going to. A
    // notification that expires leaves it seen too: a timeout looks the
    // same as a close from here, and the user was there for what it told.
    // Outside tmux there is no pane to go back to, so nothing is kept.
    let mut seen = None;
    if let Some((pane, mut server)) = look.and_then(Look::finish) {
        let visible = hypr.as_ref().is_some_and(|hypr| {
            if acted {
                desktop::focus(&pane, hypr, &mut server).finish();
            }
            desktop::visible(&pane, hypr, &server.clients)
        });
        seen = Some(acted || visible || event.expire_ms != 0);
    }
    let _lock = state::lock();
    let mut state = state::read(&path).unwrap_or_default();
    let recorded = state::toast(&state).and_then(|toast| toast.get("pid"));
    if recorded.and_then(Value::as_i64) == Some(pid.into()) {
        if let Some(seen) = seen {
            state.remove("toast");
            if seen {
                state.insert("seen".into(), state::now().into());
            }
            state::write(&path, &state);
            state::publish(&state, false).finish();
        } else {
            let _ = fs::remove_file(&path);
        }
        state::refresh_bar();
    }
    // notify-send had this end of its stderr until now.
    drop(stderr);
    unsafe { libc::_exit(0) }
}
