//! `pick`: the agents of this tmux server in a list, to go to one or to
//! forget it. It is run in a tmux popup (`prefix g` in tmux.conf), and what
//! it goes to is shown by tmux alone, so it needs no desktop.
//!
//! The list is in the order `next` goes, the agents at work last. It is
//! read again every second, and the records are not locked in between.

use std::fs;
use std::io::{self, ErrorKind, Write};
use std::sync::OnceLock;

use crate::agents::{self, Agent, Event};
use crate::dbus::Daemon;
use crate::{die, long, state, tmux};

/// How long the list is shown before it is read again, in ms.
const RELOAD: libc::c_int = 1000;
const GROUPS: [&str; 3] = ["pending", "seen", "running"];

const RESET: &str = "\x1b[m";
/// The column names start in: after the selection's bar, the key and the
/// cross of the agent the popup is over.
const NAME: usize = 6;
/// The other screen, with no cursor, and with lines cut at the edge, not
/// wrapped: a wide character counts as one here.
const ENTER: &str = "\x1b[?1049h\x1b[?25l\x1b[?7l";
const LEAVE: &str = "\x1b[?7h\x1b[?25h\x1b[?1049l";
/// A screen is drawn between these, at once.
const BEGIN: &str = "\x1b[?2026h\x1b[H";
const END: &str = "\x1b[?2026l";

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

/// The palette's colors, as `theme` renders them from
/// theme/templates/scripts/notifi/colors, each as the escape that sets it.
/// Without that file there is no color, and the selected row is reversed.
struct Colors {
    text: String,
    muted: String,
    dim: String,
    faint: String,
    selected: String,
    marker: String,
    attention: String,
    failed: String,
}

impl Colors {
    fn load() -> Colors {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/colors");
        let file = fs::read_to_string(path).unwrap_or_default();
        let rgb = |role: &str| {
            let (_, value) = file
                .lines()
                .filter_map(|line| line.split_once('='))
                .find(|(key, _)| key.trim() == role)?;
            let hex = u32::from_str_radix(value.trim().strip_prefix('#')?, 16).ok()?;
            let [_, red, green, blue] = hex.to_be_bytes();
            Some(format!("{red};{green};{blue}"))
        };
        let fg = |role| rgb(role).map_or("\x1b[39m".into(), |rgb| format!("\x1b[38;2;{rgb}m"));
        Colors {
            text: fg("text"),
            muted: fg("muted"),
            dim: fg("dim"),
            faint: fg("faint"),
            selected: rgb("selected").map_or("\x1b[7m".into(), |rgb| format!("\x1b[48;2;{rgb}m")),
            marker: fg("marker"),
            attention: fg("attention"),
            failed: fg("failed"),
        }
    }

    /// The color an event's words are in.
    fn of(&self, event: &Event) -> &str {
        match event.name {
            "attention" => &self.attention,
            "error" | "aborted" => &self.failed,
            "running" => &self.faint,
            _ => &self.muted,
        }
    }
}

struct Row {
    pane: String,
    session: String,
    /// Its window's index, shown where another agent is in that session.
    window: String,
    /// Its harness, claude or pi.
    app: String,
    event: &'static Event,
    /// Which of GROUPS it is in.
    group: usize,
    /// How long it has waited, or worked.
    long: String,
    /// It is in the pane the popup was opened over.
    here: bool,
}

fn load(socket: &str, session: &str) -> Vec<Row> {
    let found = agents::ask_on(socket, false).finish(&mut Daemon::default());
    let now = state::now();
    let shown = found.shown(socket, session);
    let row = |agent: &Agent| {
        // tmux has no ':' in a session's name.
        let title = &agent.pane.title;
        let (session, window) = title.rsplit_once(':').unwrap_or((title, ""));
        Row {
            pane: agent.pane.id.clone(),
            session: session.into(),
            window: window.into(),
            app: agent.app.clone(),
            event: agent.event,
            group: match (agent.running, agent.seen) {
                (true, _) => 2,
                (false, Some(_)) => 1,
                (false, None) => 0,
            },
            long: long(agent.since, now),
            here: shown == Some(agent.pane.id.as_str()),
        }
    };
    let stopped = found.stopped().into_iter();
    stopped.chain(found.running()).map(row).collect()
}

/// A line of the screen and the columns it takes so far, a character each.
#[derive(Default)]
struct Line {
    text: String,
    columns: usize,
}

impl Line {
    fn put(&mut self, color: &str, text: &str) {
        self.text.push_str(color);
        self.text.push_str(text);
        self.columns += text.chars().count();
    }

    /// Spaces up to `column`.
    fn pad(&mut self, column: usize) {
        let spaces = column.saturating_sub(self.columns);
        self.text.extend(std::iter::repeat_n(' ', spaces));
        self.columns += spaces;
    }
}

/// `text` in `columns`, its end given up for a '…' if it is longer.
fn cut(text: &str, columns: usize) -> String {
    if text.chars().count() <= columns {
        return text.into();
    }
    let kept: String = text.chars().take(columns.saturating_sub(1)).collect();
    if columns == 0 { kept } else { kept + "…" }
}

/// The rows of the list. A name is its session's, and its window's where
/// another agent is in that session too.
fn list(rows: &[Row], selected: usize, width: usize, colors: &Colors) -> (Vec<String>, usize) {
    let shared = |row: &Row| {
        rows.iter()
            .filter(|other| other.session == row.session)
            .count()
            > 1
    };
    let name = |row: &Row| {
        let window = row.window.chars().count() + 1;
        row.session.chars().count() + if shared(row) { window } else { 0 }
    };
    let widest = |each: &dyn Fn(&Row) -> usize| rows.iter().map(each).max().unwrap_or(0);
    let app = widest(&|row| row.app.chars().count());
    let body = widest(&|row| row.event.body.chars().count());
    let time = widest(&|row| row.long.chars().count());
    // Marker, key, cross and margins, then each column after the name with
    // its gap.
    let rest = NAME + if app > 0 { app + 2 } else { 0 } + body + 2 + time + 2 + 1;
    let names = widest(&name).min(width.saturating_sub(rest).max(6));

    let mut lines = Vec::new();
    let mut at = 0;
    if rows.is_empty() {
        let mut line = Line::default();
        line.pad(width.saturating_sub(9) / 2);
        line.put(&colors.faint, "No agents");
        lines.push(line.text);
    }
    for (group, title) in GROUPS.iter().enumerate() {
        if !rows.iter().any(|row| row.group == group) {
            continue;
        }
        if !lines.is_empty() {
            lines.push(String::new());
        }
        lines.push(format!("  {}{title}", colors.dim));
        for (index, row) in rows.iter().enumerate() {
            if row.group != group {
                continue;
            }
            let mut line = Line::default();
            if index == selected {
                at = lines.len();
                line.text.push_str(&colors.selected);
                line.put(&colors.marker, "▌ ");
            } else {
                line.put("", "  ");
            }
            let key = match index {
                0..9 => (index + 1).to_string(),
                _ => " ".into(),
            };
            line.put(&colors.faint, &key);
            if row.here {
                line.pad(4);
                line.put(&colors.marker, "⸸");
            }
            line.pad(NAME);

            let at_work = row.group == 2;
            let color = if at_work { &colors.dim } else { &colors.text };
            if shared(row) {
                let session = names.saturating_sub(row.window.chars().count() + 1);
                line.put(color, &cut(&row.session, session));
                line.put(&colors.faint, &format!(":{}", row.window));
            } else {
                line.put(color, &cut(&row.session, names));
            }
            line.pad(NAME + names);
            if app > 0 {
                line.pad(line.columns + 2);
                line.put(&colors.dim, &row.app);
                line.pad(NAME + names + 2 + app);
            }
            line.pad(line.columns + 2);
            let start = line.columns;
            line.put(colors.of(row.event), row.event.body);
            line.pad(start + body + 2 + time - row.long.chars().count());
            line.put(&colors.faint, &row.long);
            if index == selected {
                line.pad(width);
            }
            lines.push(line.text);
        }
    }
    (lines, at)
}

/// The list. Every line is drawn, so nothing of the last screen is left.
fn draw(rows: &[Row], selected: usize, colors: &Colors) {
    let (width, height) = size();
    let (mut lines, at) = list(rows, selected, width, colors);
    // The list keeps the selected one in view.
    let top = (at + 1).saturating_sub(height);
    lines.drain(..top);
    lines.resize(height, String::new());

    let mut screen = String::from(BEGIN);
    for (index, line) in lines.iter().enumerate() {
        if index > 0 {
            screen.push_str("\r\n");
        }
        screen.push_str("\x1b[2K");
        screen.push_str(line);
        screen.push_str(RESET);
    }
    screen.push_str(END);
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
    let colors = Colors::load();
    let mut rows = load(&socket, &session);
    let mut selected = 0;
    loop {
        draw(&rows, selected, &colors);

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
            rows = load(&socket, &session);
            let same = rows.iter().position(|row| Some(&row.pane) == pane.as_ref());
            selected = same.unwrap_or(selected.min(rows.len().saturating_sub(1)));
        }
    }
}
