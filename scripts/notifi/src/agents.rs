//! The agents on record, and going to them or forgetting them.

use std::cmp::{Ordering, Reverse};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::dbus::Daemon;
use crate::run::Running;
use crate::state::{self, Lock, State};
use crate::tmux::{self, Pane, Server};
use crate::{desktop, die, hyprland};

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

pub struct Agent {
    path: PathBuf,
    pub pane: Pane,
    pub event: &'static Event,
    since: f64,
    /// When the user last went to it, or it stopped in view; None while
    /// pending.
    pub seen: Option<f64>,
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
///
/// Call it locked.
pub fn close(path: &Path, daemon: &mut Daemon) {
    let state = state::read(path).unwrap_or_default();
    let _ = fs::remove_file(path);
    if state.is_empty() {
        return;
    }
    state::refresh_bar();
    let (Some(pid), Some(toast)) = (state::sender(&state), state::toast(&state)) else {
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
        close(&path, &mut Daemon::default());
    }
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
    let lock = state::lock();
    let mut records = Vec::new();
    let mut servers: Vec<(String, Running)> = Vec::new();
    for path in state::paths() {
        let state = state::read(&path).unwrap_or_default();
        let socket = text(&state, "socket");
        if !socket.is_empty() && servers.iter().all(|(asked, _)| asked != socket) {
            servers.push((socket.into(), tmux::survey(socket, stay)));
        }
        records.push((path, state));
    }
    Some(Asked {
        lock,
        records,
        servers,
    })
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
        let (mut agents, mut dropped) = (Vec::new(), false);
        for (path, state) in self.records {
            let notified = toast_up(&state, daemon);
            let pane = servers
                .get(text(&state, "socket"))
                .and_then(|server| server.panes.get(text(&state, "pane")))
                .filter(|pane| pane.server == text(&state, "server"));
            let event = find_event(text(&state, "event"));
            let since = state.get("since").and_then(Value::as_f64);
            if let (Some(pane), Some(event), Some(since)) = (pane, event, since) {
                let seen = state.get("seen").and_then(Value::as_f64);
                let pane = pane.clone();
                agents.push(Agent {
                    path,
                    pane,
                    event,
                    since,
                    seen,
                    notified,
                });
            } else if !notified {
                dropped = true;
                let _ = fs::remove_file(path);
            }
        }
        if dropped {
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
    /// The agents left without a notification, in the order `next` goes:
    /// the pending ones first, by how long they have waited, then the seen
    /// ones, starting with the one visited longest ago.
    pub fn waiting(&self) -> Vec<&Agent> {
        let turn = |agent: &Agent| (agent.seen.is_some(), agent.seen.unwrap_or(agent.since));
        let mut waiting: Vec<&Agent> = self.agents.iter().filter(|agent| !agent.notified).collect();
        waiting.sort_by(|a, b| turn(a).partial_cmp(&turn(b)).unwrap_or(Ordering::Equal));
        waiting
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
    let shown = desktop::focus(&pane, &hypr, found.servers.get_mut(&pane.socket)?);

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

/// Forgets the agent in the focused window; returns the titles.
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
    for agent in &here {
        close(&agent.path, &mut daemon);
    }
    here.iter().map(|agent| agent.pane.title.clone()).collect()
}
