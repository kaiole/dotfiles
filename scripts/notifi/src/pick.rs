//! `pick`: the agents of this tmux server in a list, to go to one or to
//! forget it. It is run in a tmux popup (`prefix a` in tmux.conf), and what
//! it goes to is shown by tmux alone, so it needs no desktop.
//!
//! The list is in the order `next` goes, the agents at work last. It is
//! read again every second, and the records are not locked in between.

use std::io::{self, ErrorKind, Write};
use std::sync::OnceLock;

use crate::agents::{self, Agent};
use crate::dbus::Daemon;
use crate::{die, long, state, tmux};

/// How long the list is shown before it is read again, in ms.
const RELOAD: libc::c_int = 1000;
const GROUPS: [&str; 3] = ["pending", "seen", "running"];

// Only what a terminal has of its own, so that there is no color to theme.
const BOLD: &str = "\x1b[1m";
const DIM: &str = "\x1b[2m";
const REVERSE: &str = "\x1b[7m";
const RESET: &str = "\x1b[m";
/// The other screen, with no cursor, and with lines cut at the edge, not
/// wrapped: a wide character counts as one here.
const ENTER: &str = "\x1b[?1049h\x1b[?25l\x1b[?7l";
const LEAVE: &str = "\x1b[?7h\x1b[?25h\x1b[?1049l";

/// The terminal as it was, to leave it so.
static COOKED: OnceLock<libc::termios> = OnceLock::new();

extern "C" fn restore() {
    if let Some(cooked) = COOKED.get() {
        unsafe {
            libc::write(1, LEAVE.as_ptr().cast(), LEAVE.len());
            libc::tcsetattr(0, libc::TCSAFLUSH, cooked);
        }
    }
}

/// Takes the terminal: keys come as they are pressed and are not shown.
/// It is given back when this exits, however it does.
fn take_terminal() {
    let mut cooked: libc::termios = unsafe { std::mem::zeroed() };
    if unsafe { libc::tcgetattr(0, &mut cooked) } != 0 {
        die("notifi: pick needs a terminal");
    }
    let _ = COOKED.set(cooked);
    let mut raw = cooked;
    unsafe {
        libc::cfmakeraw(&mut raw);
        libc::tcsetattr(0, libc::TCSAFLUSH, &raw);
        libc::atexit(restore);
    }
    write(ENTER);
}

fn write(text: &str) {
    let mut terminal = io::stdout();
    let _ = terminal.write_all(text.as_bytes());
    let _ = terminal.flush();
}

/// Columns and lines.
fn size() -> (usize, usize) {
    let mut size: libc::winsize = unsafe { std::mem::zeroed() };
    let known = unsafe { libc::ioctl(1, libc::TIOCGWINSZ, &mut size) } == 0;
    if known && size.ws_col > 0 && size.ws_row > 0 {
        (size.ws_col.into(), size.ws_row.into())
    } else {
        (80, 24)
    }
}

struct Row {
    pane: String,
    title: String,
    body: &'static str,
    /// Which of GROUPS it is in.
    group: usize,
    /// How long it has waited, or worked.
    long: String,
}

fn load(socket: &str) -> Vec<Row> {
    let found = agents::ask_on(socket, false).finish(&mut Daemon::default());
    let now = state::now();
    let row = |agent: &Agent| Row {
        pane: agent.pane.id.clone(),
        title: agent.pane.title.clone(),
        body: if agent.running { "" } else { agent.event.body },
        group: match (agent.running, agent.seen) {
            (true, _) => 2,
            (false, Some(_)) => 1,
            (false, None) => 0,
        },
        long: long(agent.since, now),
    };
    let stopped = found.stopped().into_iter();
    stopped.chain(found.running()).map(row).collect()
}

fn draw(rows: &[Row], selected: usize) {
    let (width, height) = size();
    let fit = |text: &str| text.chars().take(width).collect::<String>();
    let titles = rows.iter().map(|row| row.title.chars().count());
    let title = titles
        .max()
        .unwrap_or(0)
        .min(width.saturating_sub(30).max(8));

    let mut list = Vec::new();
    let mut at = 0;
    // Every group has its header, empty or not.
    for (group, name) in GROUPS.iter().enumerate() {
        list.push(format!("{DIM}{}{RESET}", fit(&format!(" {name}"))));
        for (index, row) in rows.iter().enumerate() {
            if row.group != group {
                continue;
            }
            let key = match index {
                0..9 => (index + 1).to_string(),
                _ => " ".into(),
            };
            let name: String = row.title.chars().take(title).collect();
            let text = format!("   {key} {name:<title$}  {:<13}  {:>6}", row.body, row.long);
            let style = [BOLD, "", DIM][row.group];
            if index == selected {
                at = list.len();
                list.push(format!("{style}{REVERSE}{:<width$}{RESET}", fit(&text)));
            } else {
                list.push(format!("{style}{}{RESET}", fit(&text)));
            }
        }
    }

    // The list keeps the selected one in view.
    let top = (at + 1).saturating_sub(height);
    let lines: Vec<String> = list.into_iter().skip(top).take(height).collect();

    let mut screen = String::from("\x1b[H");
    screen.push_str(&lines.join("\x1b[K\r\n"));
    screen.push_str("\x1b[K\x1b[J");
    write(&screen);
}

enum Key {
    Up,
    Down,
    Go,
    /// Go to the row with this index.
    Row(usize),
    Forget,
    Close,
}

/// The keys in what the terminal sent. An escape on its own is the key;
/// one that starts a sequence is an arrow, or is passed over with it.
fn keys(bytes: &[u8]) -> Vec<Key> {
    let mut keys = Vec::new();
    let mut rest = bytes;
    while let Some((&byte, after)) = rest.split_first() {
        rest = after;
        keys.push(match byte {
            b'k' | 0x10 => Key::Up,
            b'j' | 0x0e => Key::Down,
            b'\r' | b'\n' => Key::Go,
            b'1'..=b'9' => Key::Row(usize::from(byte - b'1')),
            b'x' => Key::Forget,
            b'q' | 0x03 => Key::Close,
            0x1b if after.is_empty() => Key::Close,
            0x1b => {
                let last = after
                    .iter()
                    .skip(1)
                    .position(|byte| (0x40..=0x7e).contains(byte));
                let end = last.map_or(after.len(), |last| last + 2);
                rest = &after[end..];
                match after[..end].last() {
                    Some(b'A') => Key::Up,
                    Some(b'B') => Key::Down,
                    _ => continue,
                }
            }
            _ => continue,
        });
    }
    keys
}

/// Whether a key was pressed before the list is due again; None once the
/// terminal is gone.
fn pressed() -> Option<bool> {
    let mut terminal = libc::pollfd {
        fd: 0,
        events: libc::POLLIN,
        revents: 0,
    };
    loop {
        let ready = unsafe { libc::poll(&mut terminal, 1, RELOAD) };
        if ready >= 0 {
            return Some(ready > 0);
        }
        if io::Error::last_os_error().kind() != ErrorKind::Interrupted {
            return None;
        }
    }
}

pub fn pick() {
    let Some((socket, session)) = tmux::here() else {
        die("notifi: pick is for a tmux popup");
    };
    take_terminal();
    let mut rows = load(&socket);
    let mut selected = 0;
    loop {
        draw(&rows, selected);

        let Some(pressed) = pressed() else {
            return;
        };
        let mut reload = !pressed;
        if pressed {
            let mut sent = [0u8; 64];
            let count = unsafe { libc::read(0, sent.as_mut_ptr().cast(), sent.len()) };
            let Ok(count @ 1..) = usize::try_from(count) else {
                return;
            };
            for key in keys(&sent[..count]) {
                let row = match key {
                    Key::Up => {
                        selected = selected.saturating_sub(1);
                        continue;
                    }
                    Key::Down => {
                        selected = (selected + 1).min(rows.len().saturating_sub(1));
                        continue;
                    }
                    Key::Close => return,
                    Key::Row(index) => rows.get(index),
                    Key::Go | Key::Forget => rows.get(selected),
                };
                let Some(row) = row else {
                    continue;
                };
                let mut daemon = Daemon::default();
                if matches!(key, Key::Forget) {
                    let found = agents::ask_on(&socket, false).finish(&mut daemon);
                    found.forget(&row.pane, &mut daemon);
                    reload = true;
                    break;
                }
                let mut found = agents::ask_on(&socket, true).finish(&mut daemon);
                found.visit(&row.pane, &session, &mut daemon);
                return;
            }
        }
        if reload {
            let pane = rows.get(selected).map(|row| row.pane.clone());
            rows = load(&socket);
            let same = rows.iter().position(|row| Some(&row.pane) == pane.as_ref());
            selected = same.unwrap_or(selected.min(rows.len().saturating_sub(1)));
        }
    }
}
