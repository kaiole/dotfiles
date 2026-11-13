//! The agents on record, and going to them or forgetting them.

use std::cmp::{Ordering, Reverse};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::dbus::Daemon;
use crate::run::Running;
use crate::state::{self, Lock, State};
use crate::tmux::{self, Pane, Server};
use crate::{desktop, die, hyprland};

/// What `next --tmux` says in tmux's status line when there is none.
const NONE_WAITING: &str = "No agent waiting";

pub struct Event {
    pub name: &'static str,
    pub body: &'static str,
    pub urgency: &'static str,
    /// 0 keeps the notification until it is dismissed.
    pub expire_ms: u32,
    /// Skipped while the agent's tmux window is on screen.
    pub focus_aware: bool,
}

const fn event(
    name: &'static str,
    body: &'static str,
    urgency: &'static str,
    expire_ms: u32,
    focus_aware: bool,
) -> Event {
    Event {
        name,
        body,
        urgency,
        expire_ms,
        focus_aware,
    }
}

pub const EVENTS: [Event; 4] = [
    event("finished", "Task Finished", "normal", 0, true),
    event("attention", "Needs Input", "normal", 0, true),
    event("error", "Task Failed", "critical", 0, false),
    event("aborted", "Task Aborted", "critical", 5000, false),
];

pub fn find_event(name: &str) -> Option<&'static Event> {
    EVENTS.iter().find(|event| event.name == name)
}

/// What an agent at work is listed with. It is no event to `show`: `start`
/// records it, and nothing is notified.
static WORKING: Event = event("running", "Working", "low", 0, false);

pub struct Agent {
    path: PathBuf,
    pub pane: Pane,
    /// The harness it runs in, as its `--app` named it: claude, pi. Empty
    /// for a record written before that was kept.
    pub app: String,
    pub event: &'static Event,
    /// When it stopped or, if it is running, started.
    pub since: f64,
    /// It is at work, so there is nothing to go to it for.
    pub running: bool,
    /// When the user last went to it, or it stopped in view; None while
    /// pending.
    pub seen: Option<f64>,
    /// When `next --running` last went to it, while it is at work.
    visited: Option<f64>,
    /// Its notification is still up.
    notified: bool,
}

/// Whether the record's notification is still on the desktop.
fn toast_up(state: &State, daemon: &mut Daemon) -> bool {
    if state::sender(state).is_none() {
        return false;
    }
    // A daemon started since then never had it.
    match state::toast(state).and_then(|toast| toast.get("owner")) {
        None | Some(Value::Null) => true,
        Some(owner) => owner.as_str().is_some_and(|o| daemon.owner() == Some(o)),
    }
}

/// Forgets the record at `path`, closing its notification if that is up.
/// Returns the record if there was one: the bar and the record's pane
/// (`state::publish`) are then to be told, which is left to the caller, who
/// may be about to write another.
///
/// Call it locked.
#[must_use]
pub fn close(path: &Path, daemon: &mut Daemon) -> Option<State> {
    let state = state::read(path);
    let _ = fs::remove_file(path);
    let state = state.filter(|state| !state.is_empty())?;
    end_toast(&state, daemon);
    Some(state)
}

/// Closes the record's notification, if that is up.
fn end_toast(state: &State, daemon: &mut Daemon) {
    let (Some(pid), Some(toast)) = (state::sender(state), state::toast(state)) else {
        return;
    };
    // Stop a lingering notify-send too.
    unsafe { libc::kill(pid, libc::SIGTERM) };
    // Ids restart with the daemon, so only close one that the running daemon
    // issued; otherwise this could close someone else's.
    let owner = toast.get("owner").and_then(Value::as_str);
    let id = toast.get("id").and_then(Value::as_str);
    if let (Some(owner), Some(Ok(id))) = (owner, id.map(str::parse))
        && !owner.is_empty()
        && daemon.owner() == Some(owner)
    {
        daemon.close(id);
    }
}

/// Forgets the agent running this command.
pub fn dismiss(app: &str) {
    let path = state::path(app);
    if path.exists() {
        let _lock = state::lock();
        if let Some(state) = close(&path, &mut Daemon::default()) {
            state::publish(&state, true).finish();
            state::refresh_bar();
        }
    }
}

/// How much of the end of a transcript is read: the rows after an
/// interrupt are a few hundred bytes each.
const TAIL: u64 = 64 * 1024;
/// What Claude Code writes as the user's turn when a turn is interrupted,
/// followed by "]" or by " for tool use]".
const INTERRUPT: &str = "[Request interrupted by user";

/// Whether a running agent was interrupted since it started, which no hook
/// of Claude Code tells: `running` is what `start` recorded, the session's
/// transcript and how long that was then. Its last turn is then the
/// interrupt, and it is the user's.
///
/// The format is not documented (measured on v2.1.321). If it changes this
/// is false, and the agent stays running until its next prompt.
fn interrupted(running: &Value) -> bool {
    let read = || {
        let offset = running.get("offset")?.as_u64()?;
        let mut file = File::open(running.get("transcript")?.as_str()?).ok()?;
        let length = file.metadata().ok()?.len();
        // The prompt it started with is written after its hook has run.
        if length <= offset {
            return None;
        }
        let from = offset.max(length.saturating_sub(TAIL));
        file.seek(SeekFrom::Start(from)).ok()?;
        let mut tail = Vec::new();
        file.read_to_end(&mut tail).ok()?;
        Some(tail)
    };
    let tail = read().unwrap_or_default();
    // A row cut by `from` is no JSON, and is passed over like the rows
    // that are no turn.
    let rows = String::from_utf8_lossy(&tail);
    let rows = rows
        .lines()
        .rev()
        .filter_map(|row| serde_json::from_str(row).ok());
    for row in rows {
        let row: Value = row;
        match row.get("type").and_then(Value::as_str) {
            Some("user") => {
                let content = &row["message"]["content"];
                let said = content.as_str().or_else(|| content[0]["text"].as_str());
                return said.is_some_and(|said| said.starts_with(INTERRUPT));
            }
            Some("assistant") => return false,
            _ => {}
        }
    }
    false
}

/// The records, and the tmux servers they name, each asked for its panes
/// and clients but not answered yet. Holds the lock on the records.
pub struct Asked {
    lock: Lock,
    records: Vec<(PathBuf, State)>,
    servers: Vec<(String, Running)>,
}

/// None without a record, the usual case: waybar asks every 30 s. With
/// `stay`, the tmux that asks a server waits to show a pane on it.
pub fn ask(stay: bool) -> Option<Asked> {
    if state::paths().is_empty() {
        return None;
    }
    Some(gather(None, stay))
}

/// The agents of the tmux server at `socket` alone, which is asked even
/// with none on record: what a key bind in tmux lists and goes to, on the
/// server that it was pressed in.
pub fn ask_on(socket: &str, stay: bool) -> Asked {
    gather(Some(socket), stay)
}

fn gather(only: Option<&str>, stay: bool) -> Asked {
    let lock = state::lock();
    let mut records = Vec::new();
    let mut servers: Vec<(String, Running)> = Vec::new();
    if let Some(socket) = only {
        servers.push((socket.into(), tmux::survey(socket, stay)));
    }
    for path in state::paths() {
        let state = state::read(&path).unwrap_or_default();
        let socket = text(&state, "socket");
        if only.is_some_and(|only| only != socket) {
            continue;
        }
        if !socket.is_empty() && servers.iter().all(|(asked, _)| asked != socket) {
            servers.push((socket.into(), tmux::survey(socket, stay)));
        }
        records.push((path, state));
    }
    Asked {
        lock,
        records,
        servers,
    }
}

fn text<'a>(state: &'a State, key: &str) -> &'a str {
    state.get(key).and_then(Value::as_str).unwrap_or("")
}

/// The agents on record that have a pane to go to, with what their tmux
/// servers answered. Holds the lock on the records.
pub struct Found {
    _lock: Lock,
    agents: Vec<Agent>,
    servers: HashMap<String, Server>,
}

impl Asked {
    /// Without its notification, an agent needs a live pane: other records
    /// are dropped, those whose pane died without a dismiss or belonged to
    /// an earlier tmux server on the same socket.
    pub fn finish(self, daemon: &mut Daemon) -> Found {
        let mut servers = HashMap::new();
        for (socket, asked) in self.servers {
            let server = tmux::read(&socket, asked);
            servers.insert(socket, server);
        }
        let (mut agents, mut changed) = (Vec::new(), false);
        for (path, mut state) in self.records {
            let notified = toast_up(&state, daemon);
            let pane = servers
                .get(text(&state, "socket"))
                .and_then(|server| server.panes.get(text(&state, "pane")))
                .filter(|pane| pane.server == text(&state, "server"));
            // Interrupted, it waits like one that was aborted: seen,
            // because the user was there to do it.
            if pane.is_some() && state.get("running").is_some_and(interrupted) {
                state.remove("running");
                state.insert("event".into(), "aborted".into());
                state.insert("since".into(), state::now().into());
                state.insert("seen".into(), state::now().into());
                state::write(&path, &state);
                state::publish(&state, false).finish();
                changed = true;
            }
            let running = state.contains_key("running");
            let event = if running {
                Some(&WORKING)
            } else {
                find_event(text(&state, "event"))
            };
            let since = state.get("since").and_then(Value::as_f64);
            if let (Some(pane), Some(event), Some(since)) = (pane, event, since) {
                let seen = state.get("seen").and_then(Value::as_f64);
                let visited = state.get("visited").and_then(Value::as_f64);
                let pane = pane.clone();
                agents.push(Agent {
                    app: text(&state, "app").into(),
                    path,
                    pane,
                    event,
                    since,
                    running,
                    seen,
                    visited,
                    notified,
                });
            } else if !notified {
                changed = true;
                let _ = fs::remove_file(path);
                // A dead pane says nothing any more; a live one, of a
                // record that makes no sense, is not to say it for good.
                if pane.is_some() {
                    drop(state::publish(&state, true));
                }
            }
        }
        if changed {
            state::refresh_bar();
        }
        Found {
            _lock: self.lock,
            agents,
            servers,
        }
    }
}

impl Found {
    /// The agents that stopped, in the order `next` goes: the pending ones
    /// first, by how long they have waited, then the seen ones, starting
    /// with the one visited longest ago. One whose notification is still up
    /// is pending too.
    pub fn stopped(&self) -> Vec<&Agent> {
        let turn = |agent: &Agent| (agent.seen.is_some(), agent.seen.unwrap_or(agent.since));
        let stopped = |agent: &&Agent| !agent.running;
        let mut waiting: Vec<&Agent> = self.agents.iter().filter(stopped).collect();
        waiting.sort_by(|a, b| turn(a).partial_cmp(&turn(b)).unwrap_or(Ordering::Equal));
        waiting
    }

    /// Those of them that are left without a notification, which is what
    /// goes to the others on a desktop.
    pub fn waiting(&self) -> Vec<&Agent> {
        let mut waiting = self.stopped();
        waiting.retain(|agent| !agent.notified);
        waiting
    }

    /// The pane that the client on `session` used last shows, as `visit`
    /// picks that client: the one a key was pressed in. None if no client
    /// of the server is on that session.
    pub fn shown(&self, socket: &str, session: &str) -> Option<&str> {
        let server = self.servers.get(socket)?;
        let client = tmux::latest(&server.clients, session)?;
        (client.session_id == session).then_some(client.pane_id.as_str())
    }

    /// The agents at work, the one that has been longest first.
    pub fn running(&self) -> Vec<&Agent> {
        let mut running: Vec<&Agent> = self.agents.iter().filter(|agent| agent.running).collect();
        running.sort_by(|a, b| a.since.partial_cmp(&b.since).unwrap_or(Ordering::Equal));
        running
    }

    /// Has tmux show the agent in `pane`, and nothing else: to the client
    /// that a key was pressed in, the one on `session` used last. An agent
    /// that stopped is seen from then on and loses its notification; one at
    /// work stays as it is. Returns its title, or None if it has gone.
    ///
    /// For the agents of one server (`ask_on`), asked to stay.
    pub fn visit(&mut self, pane: &str, session: &str, daemon: &mut Daemon) -> Option<String> {
        let agent = self.agents.iter().find(|agent| agent.pane.id == pane)?;
        let (path, pane, stopped) = (agent.path.clone(), agent.pane.clone(), !agent.running);
        let server = self.servers.get_mut(&pane.socket)?;
        let client = tmux::latest(&server.clients, session);
        tmux::show(&mut server.asked, &pane, client, stopped);
        if stopped {
            let mut state = state::read(&path).unwrap_or_default();
            end_toast(&state, daemon);
            state.remove("toast");
            state.insert("seen".into(), state::now().into());
            state::write(&path, &state);
            state::refresh_bar();
        }
        std::mem::take(&mut server.asked).finish();
        Some(pane.title)
    }

    /// Forgets the agent in `pane`, at work or not.
    pub fn forget(&self, pane: &str, daemon: &mut Daemon) {
        let agent = self.agents.iter().find(|agent| agent.pane.id == pane);
        if let Some(state) = agent.and_then(|agent| close(&agent.path, daemon)) {
            state::publish(&state, true).finish();
            state::refresh_bar();
        }
    }
}

/// Focuses the first waiting agent, which is seen from then on.
///
/// Returns its title, or None if no agent is waiting.
pub fn next(asked: Option<Asked>, daemon: &mut Daemon) -> Option<String> {
    let asked = asked?;
    let hypr = hyprland::snapshot(); // while tmux answers
    let mut found = asked.finish(daemon);
    let agent = *found.waiting().first()?;
    let (path, pane) = (agent.path.clone(), agent.pane.clone());
    let Some(hypr) = hypr else {
        die("notifi: no Hyprland to focus a window in");
    };
    let shown = desktop::focus(&pane, &hypr, found.servers.get_mut(&pane.socket)?, true);

    let mut state = state::read(&path).unwrap_or_default();
    // A notify-send left behind by a daemon that died.
    if let Some(pid) = state::sender(&state) {
        unsafe { libc::kill(pid, libc::SIGTERM) };
    }
    state.remove("toast");
    state.insert("seen".into(), state::now().into());
    state::write(&path, &state);
    state::refresh_bar();
    shown.finish();
    Some(pane.title)
}

/// Focuses the agents at work in turn: the ones not gone to yet, the one
/// at work longest first, then the one gone to longest ago. It stays
/// running.
///
/// Returns its title, or None if no agent is at work.
pub fn next_running(asked: Option<Asked>, daemon: &mut Daemon) -> Option<String> {
    let asked = asked?;
    let hypr = hyprland::snapshot(); // while tmux answers
    let mut found = asked.finish(daemon);
    let turn = |agent: &&Agent| (agent.visited.is_some(), agent.visited.unwrap_or(agent.since));
    let mut running = found.running();
    running.sort_by(|a, b| turn(a).partial_cmp(&turn(b)).unwrap_or(Ordering::Equal));
    let agent = *running.first()?;
    let (path, pane) = (agent.path.clone(), agent.pane.clone());
    let Some(hypr) = hypr else {
        die("notifi: no Hyprland to focus a window in");
    };
    let shown = desktop::focus(&pane, &hypr, found.servers.get_mut(&pane.socket)?, false);
    // The counts are as they were: waybar needs no telling.
    let mut state = state::read(&path).unwrap_or_default();
    state.insert("visited".into(), state::now().into());
    state::write(&path, &state);
    shown.finish();
    Some(pane.title)
}

/// `next` for a key bind in tmux, with no desktop asked: the first agent
/// that stopped on the server the key was pressed in is shown to the client
/// it was pressed in. With none, that client is told so.
///
/// Prints nothing: tmux would show it over the pane.
pub fn next_here() {
    let Some((socket, session)) = tmux::here() else {
        die("notifi: next --tmux is for a tmux key bind");
    };
    let mut daemon = Daemon::default();
    let mut found = ask_on(&socket, true).finish(&mut daemon);
    let first = found.stopped().first().map(|agent| agent.pane.id.clone());
    if let Some(pane) = first {
        found.visit(&pane, &session, &mut daemon);
    } else if let Some(server) = found.servers.get_mut(&socket) {
        if let Some(client) = tmux::latest(&server.clients, &session) {
            tmux::say(&mut server.asked, client, NONE_WAITING);
        }
        std::mem::take(&mut server.asked).finish();
    }
}

/// What Super+Y does: the action of the notification on screen or, with
/// none there, `next`.
pub fn go() -> Option<String> {
    let asked = ask(true);
    let mut daemon = Daemon::default();
    if daemon.displayed() == 0 {
        return next(asked, &mut daemon);
    }
    // The action may be an agent's Focus, which changes its record.
    drop(asked);
    daemon.act();
    None
}

/// Forgets the agent in the focused window, at work or not; returns the
/// titles.
///
/// That is the agent in the active pane of the tmux window that the focused
/// Hyprland window shows or, if that pane has none, every agent in that
/// tmux window.
pub fn dismiss_focused() -> Vec<String> {
    let Some(asked) = ask(false) else {
        return Vec::new();
    };
    let Some(hypr) = hyprland::snapshot() else {
        die("notifi: no Hyprland to find the focused window in");
    };
    let mut daemon = Daemon::default();
    let found = asked.finish(&mut daemon);

    let mut shown = Vec::new();
    for (socket, server) in &found.servers {
        if found
            .agents
            .iter()
            .all(|agent| agent.pane.socket != *socket)
        {
            continue;
        }
        for attached in desktop::attached(&hypr, &server.clients) {
            let focused = |window: &&hyprland::Window| window.history == 0 && hypr.shows(window);
            if attached.windows.iter().any(focused) {
                shown.push((attached.client, socket));
            }
        }
    }
    // A single-instance Ghostty has every client in one process, so several
    // may match the focused window: take the one used last.
    let latest = shown
        .into_iter()
        .min_by_key(|(client, _)| Reverse(client.activity));
    let Some((client, socket)) = latest else {
        return Vec::new();
    };
    let mut here: Vec<&Agent> = found.agents.iter().collect();
    here.retain(|agent| {
        agent.pane.socket == *socket
            && agent.pane.session_id == client.session_id
            && agent.pane.window_id == client.window_id
    });
    if here.iter().any(|agent| agent.pane.id == client.pane_id) {
        here.retain(|agent| agent.pane.id == client.pane_id);
    }
    let mut closed = false;
    for agent in &here {
        if let Some(state) = close(&agent.path, &mut daemon) {
            // Not waited for: this is a key, and nothing follows it.
            drop(state::publish(&state, true));
            closed = true;
        }
    }
    if closed {
        state::refresh_bar();
    }
    here.iter().map(|agent| agent.pane.title.clone()).collect()
}
