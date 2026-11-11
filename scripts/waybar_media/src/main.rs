//! Waybar's music module: `waybar_media <player> <width>`.
//!
//! Prints what one MPRIS player is playing, "artist - title", as a line of
//! waybar JSON each time it changes, and an empty line, which hides the
//! module, when the player is closed. Waybar keeps the module `width`
//! characters wide at most (max-length in config.jsonc, which must match).
//! The title always ends with MARK, which also parts it from the visualizer
//! next to the module. A title that fits, or is paused, is printed once (cut,
//! if paused and too long), only as wide as it is, so the visualizer follows
//! it; the process then sleeps until the player's next signal. A longer
//! title scrolls while it plays, always at the full width, blank space and
//! all, so that nothing after it jitters: it rests at its start for HOLD,
//! then moves one cell every STEP, with GAP between its end and its start.

use std::io::Write;
use std::process::exit;
use std::time::{Duration, Instant};

use dbus::Message;
use dbus::arg::{PropMap, RefArg, prop_cast};
use dbus::blocking::Connection;
use unicode_width::UnicodeWidthChar;

const GAP: &str = "  ";
/// What follows the title, whatever it is.
const MARK: &str = "...";
const STEP: Duration = Duration::from_millis(300);
const HOLD: Duration = Duration::from_secs(2);
/// How long to wait for the bus when nothing scrolls; the length is arbitrary.
const IDLE: Duration = Duration::from_secs(3600);
const CALL_TIMEOUT: Duration = Duration::from_secs(2);

const PATH: &str = "/org/mpris/MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";
const PROPERTIES: &str = "org.freedesktop.DBus.Properties";

/// One per character's width of text. A wide character (CJK, emoji) takes
/// two cells, the second being None; a zero-width one (a combining mark)
/// joins the cell before it. Control characters are dropped.
type Cells = Vec<Option<String>>;

fn to_cells(text: &str) -> Cells {
    let mut cells = Cells::new();
    for ch in text.chars().filter(|ch| !ch.is_control()) {
        match ch.width() {
            Some(0) | None => {
                if let Some(before) = cells.iter_mut().rev().flatten().next() {
                    before.push(ch);
                }
            }
            Some(width) => {
                cells.push(Some(ch.to_string()));
                if width == 2 {
                    cells.push(None);
                }
            }
        }
    }
    cells
}

/// The `width` cells of the loop from `start` on, as text. A wide character
/// cut by either edge shows as a space, so the result is always `width` wide.
fn window(cells: &Cells, start: usize, width: usize) -> String {
    let count = cells.len();
    let mut text = String::new();
    for i in 0..width {
        match &cells[(start + i) % count] {
            None if i == 0 => text.push(' '),
            None => {}
            Some(_) if i == width - 1 && cells[(start + width) % count].is_none() => {
                text.push(' ');
            }
            Some(cell) => text.push_str(cell),
        }
    }
    text
}

/// The module's text over time.
struct Banner {
    width: usize,
    /// The player's text and whether it was playing, as last shown.
    shown: Option<(String, bool)>,
    /// The scrolling title and GAP.
    cells: Cells,
    /// The cell of `cells` at the module's left edge.
    offset: usize,
    /// When to scroll one cell on; None if nothing scrolls.
    next: Option<Instant>,
}

impl Banner {
    fn new(width: usize) -> Banner {
        Banner {
            width,
            shown: None,
            cells: Cells::new(),
            offset: 0,
            next: None,
        }
    }

    /// The module's text now that the player has `text`; None if that is
    /// what it had. Spotify sends the same properties several times a track,
    /// and a repeat must not restart the scroll.
    fn show(&mut self, text: &str, playing: bool, now: Instant) -> Option<String> {
        if matches!(&self.shown, Some((was, played)) if was == text && *played == playing) {
            return None;
        }
        self.shown = Some((text.to_string(), playing));
        if text.is_empty() {
            self.next = None;
            return Some(String::new()); // hides the module
        }
        let room = self.width - MARK.len();
        let cells = to_cells(text);
        if cells.len() <= room {
            self.next = None;
            let text: String = cells.into_iter().flatten().collect();
            Some(format!("{text}{MARK}"))
        } else if playing {
            self.cells = to_cells(&format!("{text}{GAP}"));
            self.offset = 0;
            self.next = Some(now + HOLD);
            Some(format!("{}{MARK}", window(&self.cells, 0, room)))
        } else {
            self.next = None;
            Some(format!("{}{MARK}", window(&cells, 0, room)))
        }
    }

    /// The module's text one cell on, if it is time for that.
    fn step(&mut self, now: Instant) -> Option<String> {
        if now < self.next? {
            return None;
        }
        self.offset = (self.offset + 1) % self.cells.len();
        self.next = Some(now + if self.offset == 0 { HOLD } else { STEP });
        let room = self.width - MARK.len();
        Some(format!("{}{MARK}", window(&self.cells, self.offset, room)))
    }
}

/// What the player has said of itself.
#[derive(Default)]
struct Player {
    playing: bool,
    text: String,
}

impl Player {
    /// Takes the properties that are in `properties`; a signal has only
    /// those that changed.
    fn update(&mut self, properties: &PropMap) {
        if let Some(status) = prop_cast::<String>(properties, "PlaybackStatus") {
            self.playing = status == "Playing";
        }
        if let Some(metadata) = prop_cast::<PropMap>(properties, "Metadata") {
            self.text = label(metadata);
        }
    }
}

/// "artist - title", the title alone if there is no artist, or
/// "Advertisement" for one of Spotify's.
fn label(metadata: &PropMap) -> String {
    let id = metadata.get("mpris:trackid").and_then(|id| id.0.as_str());
    if id.is_some_and(|id| id.contains(":ad:") || id.contains("/ad/")) {
        return "Advertisement".to_string();
    }
    let title = prop_cast::<String>(metadata, "xesam:title").map_or("", String::as_str);
    let artist =
        prop_cast::<Vec<String>>(metadata, "xesam:artist").map(|artists| artists.join(", "));
    match artist {
        Some(artist) if !artist.is_empty() => format!("{artist} - {title}"),
        _ => title.to_string(),
    }
}

/// All of the player's properties; None if it is not running. Flagged so
/// that the bus doesn't start the player to answer.
fn properties(connection: &Connection, name: &str) -> Option<PropMap> {
    let mut call = Message::new_method_call(name, PATH, PROPERTIES, "GetAll")
        .ok()?
        .append1(PLAYER);
    call.set_auto_start(false);
    let reply = connection
        .channel()
        .send_with_reply_and_block(call, CALL_TIMEOUT);
    reply.ok()?.read1().ok()
}

fn quoted(text: &str) -> String {
    let mut json = String::from('"');
    for ch in text.chars() {
        match ch {
            '"' | '\\' => json.extend(['\\', ch]),
            ch if ch < ' ' => json.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => json.push(ch),
        }
    }
    json.push('"');
    json
}

/// The line that makes waybar show `text`; empty, which hides the module,
/// if there is none.
fn line(text: &str, player: &str) -> String {
    if text.is_empty() {
        return String::new();
    }
    format!(
        r#"{{"text": {}, "class": {}, "alt": {}}}"#,
        quoted(text),
        quoted(&format!("custom-{player}")),
        quoted(player),
    )
}

fn fail(why: impl std::fmt::Display) -> ! {
    eprintln!("waybar_media: {why}");
    exit(1);
}

fn main() {
    let mut arguments = std::env::args().skip(1);
    let player_name = arguments.next();
    let width = arguments.next().and_then(|width| width.parse().ok());
    let (Some(player_name), Some(width @ 4usize..), None) = (player_name, width, arguments.next())
    else {
        eprintln!("usage: waybar_media <player> <width of 4 or more>");
        exit(2);
    };
    let name = format!("org.mpris.MediaPlayer2.{player_name}");

    // Signals for the player coming and going, and for its properties. The
    // bus matches the second against whichever connection owns the name.
    let connection = Connection::new_session().unwrap_or_else(|error| fail(error));
    let owner = format!(
        "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',\
         member='NameOwnerChanged',arg0='{name}'"
    );
    let changed = format!(
        "type='signal',sender='{name}',path='{PATH}',interface='{PROPERTIES}',\
         member='PropertiesChanged',arg0='{PLAYER}'"
    );
    for rule in [owner, changed] {
        connection
            .add_match_no_cb(&rule)
            .unwrap_or_else(|error| fail(error));
    }

    let mut banner = Banner::new(width);
    let mut player = properties(&connection, &name).map(|all| {
        let mut player = Player::default();
        player.update(&all);
        player
    });
    let mut stdout = std::io::stdout();
    loop {
        let now = Instant::now();
        let (text, playing) = match &player {
            Some(player) => (player.text.as_str(), player.playing),
            None => ("", false),
        };
        let text = banner.show(text, playing, now).or_else(|| banner.step(now));
        if let Some(text) = text
            && (writeln!(stdout, "{}", line(&text, &player_name)).is_err()
                || stdout.flush().is_err())
        {
            return; // waybar is gone
        }

        // This returns early, with nothing, when the bus sent only part of
        // a message, so the loop above asks the clock, not this, what is due.
        let wait = banner
            .next
            .map_or(IDLE, |at| at.saturating_duration_since(now));
        let message = match connection.channel().blocking_pop_message(wait) {
            Ok(Some(message)) => message,
            Ok(None) => continue,
            Err(error) => fail(error),
        };
        match message.member().as_deref() {
            Some("NameOwnerChanged") => {
                let Ok((_, _, new)) = message.read3::<String, String, String>() else {
                    continue;
                };
                // Just started, it may not answer yet; its first signal will.
                player = None;
                if !new.is_empty()
                    && let Some(all) = properties(&connection, &name)
                {
                    player.get_or_insert_default().update(&all);
                }
            }
            Some("PropertiesChanged") => {
                let Ok((_, changed, _)) = message.read3::<String, PropMap, Vec<String>>() else {
                    continue;
                };
                match &mut player {
                    Some(player) => player.update(&changed),
                    // The first that is known of it: ask for the rest too.
                    None => {
                        let all = properties(&connection, &name);
                        player
                            .get_or_insert_default()
                            .update(all.as_ref().unwrap_or(&changed));
                    }
                }
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dbus::arg::Variant;

    fn variant(value: impl RefArg + 'static) -> Variant<Box<dyn RefArg>> {
        Variant(Box::new(value))
    }

    fn metadata(artists: &[&str], title: &str, id: &str) -> PropMap {
        let artists: Vec<String> = artists.iter().map(|artist| artist.to_string()).collect();
        PropMap::from([
            ("xesam:artist".to_string(), variant(artists)),
            ("xesam:title".to_string(), variant(title.to_string())),
            ("mpris:trackid".to_string(), variant(id.to_string())),
        ])
    }

    #[test]
    fn a_window_is_always_as_wide_as_asked() {
        let cells = to_cells("ab日本語cd  ");
        assert_eq!(cells.len(), 12);
        let windows: Vec<String> = (0..5).map(|start| window(&cells, start, 6)).collect();
        // A space stands for each half of a wide character that is cut.
        assert_eq!(windows, ["ab日本", "b日本 ", "日本語", " 本語c", "本語cd"]);
        assert_eq!(window(&cells, 10, 6), "  ab日");
        assert_eq!(window(&cells, 11, 6), " ab日 ");
    }

    #[test]
    fn marks_join_and_control_characters_go() {
        let cells = to_cells("e\u{301}a\nb");
        let expected: Cells = vec![Some("e\u{301}".into()), Some("a".into()), Some("b".into())];
        assert_eq!(cells, expected);
    }

    #[test]
    fn a_long_title_scrolls_only_while_playing() {
        let start = Instant::now();
        let mut banner = Banner::new(7);
        assert_eq!(banner.show("abcdef", false, start).as_deref(), Some("abcd..."));
        assert_eq!(banner.next, None);

        assert_eq!(banner.show("abcdef", true, start).as_deref(), Some("abcd..."));
        assert_eq!(banner.show("abcdef", true, start), None);
        assert_eq!(banner.step(start + HOLD - STEP), None);
        assert_eq!(banner.step(start + HOLD).as_deref(), Some("bcde..."));
        assert_eq!(banner.next, Some(start + HOLD + STEP));

        // Round the loop, title and GAP, to rest at the start again.
        let mut now = start + HOLD;
        for _ in 0.."abcdef".len() + GAP.len() - 1 {
            now += STEP;
            banner.step(now);
        }
        assert_eq!(banner.offset, 0);
        assert_eq!(banner.next, Some(now + HOLD));

        assert_eq!(banner.show("abcdef", false, now).as_deref(), Some("abcd..."));
        assert_eq!(banner.step(now + HOLD), None);
    }

    #[test]
    fn a_title_that_fits_stays_still_and_only_as_wide_as_it_is() {
        let now = Instant::now();
        let mut banner = Banner::new(8);
        assert_eq!(banner.show("abcde", true, now).as_deref(), Some("abcde..."));
        assert_eq!(banner.next, None);
        assert_eq!(banner.show("ab", false, now).as_deref(), Some("ab..."));
        assert_eq!(banner.show("", false, now).as_deref(), Some(""));
    }

    #[test]
    fn the_mark_stays_after_blank_space() {
        let now = Instant::now();
        let mut banner = Banner::new(8);
        assert_eq!(banner.show("abcd efg", false, now).as_deref(), Some("abcd ..."));
        assert_eq!(banner.show("abcd efg", true, now).as_deref(), Some("abcd ..."));
    }

    #[test]
    fn labels() {
        let track = "/com/spotify/track/1";
        assert_eq!(label(&metadata(&["A", "B"], "Song", track)), "A, B - Song");
        assert_eq!(label(&metadata(&[""], "Episode", track)), "Episode");
        assert_eq!(label(&metadata(&[], "Song", track)), "Song");
        assert_eq!(
            label(&metadata(&["A"], "Song", "/com/spotify/ad/1")),
            "Advertisement"
        );
        assert_eq!(
            label(&metadata(&["A"], "Song", "spotify:ad:1")),
            "Advertisement"
        );
        assert_eq!(label(&PropMap::new()), "");
    }

    #[test]
    fn a_signal_changes_only_what_it_carries() {
        let mut player = Player::default();
        let mut all = PropMap::new();
        all.insert("PlaybackStatus".to_string(), variant("Playing".to_string()));
        all.insert(
            "Metadata".to_string(),
            variant(metadata(&["A"], "Song", "")),
        );
        player.update(&all);
        assert!(player.playing);
        assert_eq!(player.text, "A - Song");

        let mut paused = PropMap::new();
        paused.insert("PlaybackStatus".to_string(), variant("Paused".to_string()));
        player.update(&paused);
        assert!(!player.playing);
        assert_eq!(player.text, "A - Song");
    }

    #[test]
    fn lines() {
        assert_eq!(line("", "spotify"), "");
        assert_eq!(
            line("a \"b\" \\ c", "spotify"),
            r#"{"text": "a \"b\" \\ c", "class": "custom-spotify", "alt": "spotify"}"#
        );
    }
}
