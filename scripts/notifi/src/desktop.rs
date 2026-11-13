//! Where a tmux pane is on the desktop, and bringing it to the front.

use std::cmp::Reverse;
use std::process::{Command, Stdio};

use crate::hyprland::{Hyprland, Window};
use crate::run::Running;
use crate::tmux::{self, Client, Pane, Server};

/// A tmux client and the Hyprland windows it may be in.
pub struct Attached<'a> {
    pub client: &'a Client,
    pub windows: Vec<&'a Window>,
}

/// The tmux clients running inside a Hyprland window, by process ancestry.
///
/// A single-instance Ghostty serves every window from one process, so a
/// client can match several windows.
pub fn attached<'a>(hypr: &'a Hyprland, clients: &'a [Client]) -> Vec<Attached<'a>> {
    let mut attached = Vec::new();
    for client in clients {
        let tree = crate::run::ancestors(client.pid);
        let inside = |window: &&Window| tree.contains(&window.pid);
        let windows: Vec<&Window> = hypr.windows.iter().filter(inside).collect();
        if !windows.is_empty() {
            attached.push(Attached { client, windows });
        }
    }
    attached
}

/// Whether a tmux client shows the pane's window in a window on screen.
pub fn visible(pane: &Pane, hypr: &Hyprland, clients: &[Client]) -> bool {
    attached(hypr, clients).iter().any(|attached| {
        attached.client.session_id == pane.session_id
            && attached.client.window_id == pane.window_id
            && attached.windows.iter().any(|window| hypr.shows(window))
    })
}

/// Brings a pane to the front.
///
/// Selects it in tmux, switches the best attached client to its session and
/// focuses that client's Hyprland window. Opens a new Ghostty only when no
/// attached client lives in a Hyprland window. All of it is worked out now,
/// not when the notification was sent. `server` is the pane's, asked to
/// stay. With `seen`, the pane then says its agent is seen.
///
/// Returns the tmux that is told to show the pane. The server then draws
/// the client again, which takes it 1 to 2 ms, before that tmux exits.
#[must_use]
pub fn focus(pane: &Pane, hypr: &Hyprland, server: &mut Server, seen: bool) -> Running {
    // Prefer a client already on the pane's session, then the most recently
    // used one.
    let attached = attached(hypr, &server.clients);
    let best = attached.iter().min_by_key(|attached| {
        let elsewhere = attached.client.session_id != pane.session_id;
        (elsewhere, Reverse(attached.client.activity))
    });

    // tmux and Hyprland are told one after the other, and work at once.
    let elsewhere = |client: &&Client| client.session_id != pane.session_id;
    let switched = best.map(|attached| attached.client).filter(elsewhere);
    tmux::show(&mut server.asked, pane, switched, seen);
    match best {
        None => open_terminal(hypr, pane),
        // With several windows in one process, assume the client is in the
        // one focused most recently.
        Some(attached) => {
            if let Some(window) = attached.windows.iter().min_by_key(|w| w.rank()) {
                hypr.focus(window);
            }
        }
    }
    std::mem::take(&mut server.asked)
}

fn open_terminal(hypr: &Hyprland, pane: &Pane) {
    let attach = [
        "tmux",
        "-S",
        &pane.socket,
        "attach-session",
        "-t",
        &pane.session_id,
    ];
    let mut terminal = Command::new("ghostty");
    terminal
        .arg("-e")
        .args(attach)
        .env("HYPRLAND_INSTANCE_SIGNATURE", &hypr.signature)
        .env("WAYLAND_DISPLAY", &hypr.wl_socket)
        .env_remove("TMUX")
        .env_remove("TMUX_PANE")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    crate::run::detach(&mut terminal);
    let _ = terminal.spawn();
}
