//! Records. Each agent has at most one: a file that says that it is at
//! work (running) or what it is waiting with and, while its notification is
//! up, how to close it. Without the notification a waiting agent is
//! pending, or seen once the user went to it or if it stopped in view.

use std::env;
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{Map, Value};

use crate::{die, run, tmux};

pub type State = Map<String, Value>;

/// custom/agents and custom/running in waybar/config.jsonc count the
/// agents again on SIGRTMIN+8.
const WAYBAR_SIGNAL: i32 = 8;

pub fn directory() -> PathBuf {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .filter(|runtime| !runtime.is_empty())
        .map_or_else(
            || format!("/tmp/notifi-{}", unsafe { libc::getuid() }).into(),
            PathBuf::from,
        );
    runtime.join("notifi")
}

/// Serializes reads and changes of the records, until it is dropped.
pub struct Lock(#[allow(dead_code)] File);

pub fn lock() -> Lock {
    let directory = directory();
    let locked = DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&directory)
        .and_then(|()| {
            let mut lock = OpenOptions::new();
            lock.read(true).write(true).create(true).truncate(false);
            lock.mode(0o600).open(directory.join("lock"))
        })
        .and_then(|lock| lock.lock().map(|()| lock));
    match locked {
        Ok(lock) => Lock(lock),
        Err(error) => die(format!("notifi: {}: {error}", directory.display())),
    }
}

/// One record per tmux pane, or per app outside tmux.
pub fn path(app: &str) -> PathBuf {
    let key = tmux::own().map_or(app.into(), |(socket, pane)| socket + &pane);
    let name = key.replace('%', "%25").replace('/', "%2F");
    directory().join(name + ".json")
}

pub fn paths() -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir(directory()) else {
        return Vec::new();
    };
    entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|kind| kind == "json"))
        .collect()
}

pub fn read(path: &Path) -> Option<State> {
    match serde_json::from_str(&fs::read_to_string(path).ok()?).ok()? {
        Value::Object(state) => Some(state),
        _ => None,
    }
}

pub fn write(path: &Path, state: &State) {
    let text = Value::Object(state.clone()).to_string();
    if let Err(error) = fs::write(path, text) {
        die(format!("notifi: {}: {error}", path.display()));
    }
}

pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0.0, |now| now.as_secs_f64())
}

/// What the record says of its notification, while it has one.
pub fn toast(state: &State) -> Option<&State> {
    state.get("toast")?.as_object()
}

/// The live notify-send of the record's notification, if it has one.
///
/// notify-send exits with its notification, so without it the notification
/// is gone. It lingers if the daemon died (dunst exits with Hyprland).
pub fn sender(state: &State) -> Option<i32> {
    let toast = toast(state)?;
    let pid = i32::try_from(toast.get("pid")?.as_i64()?).ok()?;
    let started = toast.get("started")?.as_str()?;
    let same = pid > 0 && !started.is_empty() && run::start_time(pid).as_deref() == Some(started);
    same.then_some(pid)
}

/// Has waybar count the agents again.
///
/// killall takes 3 ms to find waybar and reading /proc here takes 1, so
/// the pids found are kept in a file and only checked from then on: for a
/// second bar started while the first runs, remove the file.
pub fn refresh_bar() {
    let bar = env::var("NOTIFI_BAR").unwrap_or_else(|_| "waybar".into());
    let is_bar = |pid: &i32| {
        fs::read_to_string(format!("/proc/{pid}/comm")).is_ok_and(|name| name.trim_end() == bar)
    };
    // Never 0 or less, which kill takes for whole groups of processes.
    let pids = |text: &str| -> Vec<i32> {
        let pids = text.split_whitespace().filter_map(|pid| pid.parse().ok());
        pids.filter(|pid| *pid > 1).collect()
    };
    let known = directory().join("bar");
    let mut bars = pids(&fs::read_to_string(&known).unwrap_or_default());
    if bars.is_empty() || !bars.iter().all(is_bar) {
        let running = fs::read_dir("/proc").into_iter().flatten().flatten();
        let names = running.map(|entry| entry.file_name().to_string_lossy().into_owned());
        bars = pids(&names.collect::<Vec<_>>().join(" "));
        bars.retain(is_bar);
        let found: Vec<String> = bars.iter().map(i32::to_string).collect();
        let _ = fs::write(&known, found.join(" "));
    }
    for pid in bars {
        unsafe { libc::kill(pid, libc::SIGRTMIN() + WAYBAR_SIGNAL) };
    }
}
