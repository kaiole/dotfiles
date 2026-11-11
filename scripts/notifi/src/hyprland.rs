//! Hyprland, asked over its request socket the way hyprctl asks it. Starting
//! hyprctl takes 4 ms a question; a connection takes 0.1 ms.

use std::env;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use serde_json::Value;

const TIMEOUT: Duration = Duration::from_secs(3);

/// A window that is mapped and not hidden.
pub struct Window {
    address: String,
    pub pid: i32,
    workspace: Option<i64>,
    /// 0 for the focused window, counting up through the ones before it.
    pub history: i64,
}

impl Window {
    /// How long ago it had focus, as a sort key.
    pub fn rank(&self) -> i64 {
        if self.history >= 0 {
            self.history
        } else {
            i64::MAX
        }
    }
}

/// Snapshot of the running Hyprland.
pub struct Hyprland {
    pub signature: String,
    pub wl_socket: String,
    pub windows: Vec<Window>,
    visible_workspaces: Vec<i64>,
}

fn directory() -> PathBuf {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .filter(|runtime| !runtime.is_empty())
        .map_or_else(
            || format!("/run/user/{}", unsafe { libc::getuid() }).into(),
            PathBuf::from,
        );
    runtime.join("hypr")
}

/// Hyprland's reply to a request, or None if that instance is gone.
fn ask(signature: &str, request: &str) -> Option<String> {
    let socket = directory().join(signature).join(".socket.sock");
    let mut connection = UnixStream::connect(socket).ok()?;
    connection.set_read_timeout(Some(TIMEOUT)).ok()?;
    connection.set_write_timeout(Some(TIMEOUT)).ok()?;
    connection.write_all(request.as_bytes()).ok()?;
    let mut reply = Vec::new();
    connection.read_to_end(&mut reply).ok()?;
    Some(String::from_utf8_lossy(&reply).into_owned())
}

fn ask_list(signature: &str, request: &str) -> Option<Vec<Value>> {
    match serde_json::from_str(&ask(signature, request)?).ok()? {
        Value::Array(list) => Some(list),
        _ => None,
    }
}

/// The running Hyprland, or None without one.
///
/// The agent inherits HYPRLAND_INSTANCE_SIGNATURE from tmux, and a tmux
/// server outlives Hyprland restarts, so that signature is used only while
/// its instance is still running; otherwise the newest is.
pub fn snapshot() -> Option<Hyprland> {
    // Each instance has a directory named by its signature, with its socket
    // and a lock file: its pid and Wayland socket. A crash leaves them behind.
    let inherited = env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default();
    let mut newest: Option<(SystemTime, String, String)> = None;
    for instance in fs::read_dir(directory()).ok()?.flatten() {
        let lock = instance.path().join("hyprland.lock");
        let (Ok(signature), Ok(text), Ok(modified)) = (
            instance.file_name().into_string(),
            fs::read_to_string(&lock),
            fs::metadata(&lock).and_then(|lock| lock.modified()),
        ) else {
            continue;
        };
        let mut lines = text.split('\n');
        let (Some(pid), Some(wl_socket)) = (lines.next(), lines.next()) else {
            continue;
        };
        let running = pid
            .trim()
            .parse()
            .is_ok_and(|pid: i32| pid > 0 && unsafe { libc::kill(pid, 0) } == 0);
        if !running {
            continue;
        }
        let found = (modified, signature, wl_socket.to_string());
        if found.1 == inherited {
            newest = Some(found);
            break;
        }
        if newest.as_ref().is_none_or(|(best, ..)| modified > *best) {
            newest = Some(found);
        }
    }
    let (_, signature, wl_socket) = newest?;

    let windows = ask_list(&signature, "j/clients")?
        .iter()
        .filter(|window| {
            window["mapped"].as_bool().unwrap_or(false)
                && !window["hidden"].as_bool().unwrap_or(false)
        })
        .map(|window| Window {
            address: window["address"].as_str().unwrap_or("").into(),
            pid: window["pid"].as_i64().map_or(-1, |pid| pid as i32),
            workspace: window["workspace"]["id"].as_i64(),
            history: window["focusHistoryID"].as_i64().unwrap_or(-1),
        })
        .collect();
    let mut visible_workspaces = Vec::new();
    for monitor in ask_list(&signature, "j/monitors")? {
        for shown in ["activeWorkspace", "specialWorkspace"] {
            match monitor[shown]["id"].as_i64() {
                Some(0) | None => {}
                Some(workspace) => visible_workspaces.push(workspace),
            }
        }
    }
    Some(Hyprland {
        signature,
        wl_socket,
        windows,
        visible_workspaces,
    })
}

impl Hyprland {
    /// Whether the window is on a workspace that some monitor is showing.
    pub fn shows(&self, window: &Window) -> bool {
        window
            .workspace
            .is_some_and(|workspace| self.visible_workspaces.contains(&workspace))
    }

    pub fn focus(&self, window: &Window) {
        let digits = window.address.strip_prefix("0x").unwrap_or("");
        if !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_hexdigit()) {
            let address = &window.address;
            let focus = format!("hl.dsp.focus({{ window = \"address:{address}\" }})");
            ask(&self.signature, &format!("/dispatch {focus}"));
        }
    }
}
