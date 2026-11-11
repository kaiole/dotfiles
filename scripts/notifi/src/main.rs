//! Desktop notifications for coding agents in tmux, on Hyprland with dunst.
//!
//! `show` notifies for the agent in this tmux pane and returns at once; a
//! detached waiter stays until the notification closes and runs its Focus
//! action. An agent whose notification is closed without that stays pending,
//! and one that was gone to stays seen: `pending` lists both and `next`
//! focuses the pending ones, then goes round the seen ones. `go` is `next`
//! unless a notification is on screen, whose action it runs. `dismiss`
//! forgets the agent from any later process. See README.md.
//!
//! Key binds run this, so what it starts and what it waits for is kept
//! short: read "Speed" in README.md before adding to either.

mod agents;
mod dbus;
mod desktop;
mod hyprland;
mod run;
mod show;
mod state;
mod tmux;

use std::env;
use std::fmt::Display;
use std::io::{self, Write};
use std::process;

use agents::Event;
use dbus::Daemon;

const USAGE: &str = "    notifi show [--event EVENT] [--app NAME] [--force] [-v]
    notifi dismiss [--app NAME | --focused]
    notifi pending [--waybar]
    notifi next
    notifi go
    notifi status";

/// Each command's options; those that take an argument end in "=".
const OPTIONS: [(&str, &[&str]); 6] = [
    (
        "show",
        &["-v", "--verbose", "--force", "--event=", "--app="],
    ),
    ("dismiss", &["--app=", "--focused"]),
    ("pending", &["--waybar"]),
    ("next", &[]),
    ("go", &[]),
    ("status", &[]),
];

/// Ends with status 1, never 2, which Claude Code reads from a hook as
/// "block this".
pub fn die(message: impl Display) -> ! {
    let _ = writeln!(io::stderr(), "{message}");
    process::exit(1)
}

fn print(line: impl Display) {
    let _ = writeln!(io::stdout(), "{line}");
}

struct Options {
    app: String,
    event: &'static Event,
    flags: Vec<String>,
}

impl Options {
    fn has(&self, flag: &str) -> bool {
        self.flags.iter().any(|given| given == flag)
    }
}

fn options(allowed: &[&str], words: &[String]) -> Result<Options, String> {
    let (mut app, mut event) = ("agent".to_string(), "finished".to_string());
    let mut flags = Vec::new();
    let mut words = words.iter();
    while let Some(word) = words.next() {
        if !word.starts_with('-') {
            return Err(format!("unexpected argument '{word}'"));
        }
        let (name, value) = match word.split_once('=') {
            Some((name, value)) => (name, Some(value)),
            None => (word.as_str(), None),
        };
        if allowed.contains(&name) {
            if value.is_some() {
                return Err(format!("option {name} must not have an argument"));
            }
            flags.push(name.to_string());
        } else if allowed.contains(&format!("{name}=").as_str()) {
            let Some(value) = value.or(words.next().map(String::as_str)) else {
                return Err(format!("option {name} requires argument"));
            };
            *(if name == "--app" {
                &mut app
            } else {
                &mut event
            }) = value.into();
        } else {
            return Err(format!("option {name} not recognized"));
        }
    }
    let Some(event) = agents::find_event(&event) else {
        let events: Vec<&str> = agents::EVENTS.iter().map(|event| event.name).collect();
        return Err(format!("--event is one of {}", events.join(", ")));
    };
    Ok(Options { app, event, flags })
}

fn main() {
    let words: Vec<String> = env::args_os()
        .skip(1)
        .map(|word| word.to_string_lossy().into_owned())
        .collect();
    let command = words.first().map_or("", String::as_str);
    if command == "-h" || command == "--help" {
        return print(format!("usage:\n{USAGE}"));
    }
    let Some((_, allowed)) = OPTIONS.iter().find(|(name, _)| *name == command) else {
        die(format!("usage:\n{USAGE}"));
    };
    let options = match options(allowed, &words[1..]) {
        Ok(options) => options,
        Err(error) => die(format!("notifi {command}: {error}\n{USAGE}")),
    };

    match command {
        "status" => {
            let allowed = show::Desktop::ask().allowed();
            print(if allowed { "allowed" } else { "blocked" });
        }
        "dismiss" if options.has("--focused") => {
            agents::dismiss_focused().iter().for_each(print);
        }
        "dismiss" => agents::dismiss(&options.app),
        "pending" => pending(options.has("--waybar")),
        "next" => {
            agents::next(agents::ask(true), &mut Daemon::default())
                .iter()
                .for_each(print);
        }
        "go" => agents::go().iter().for_each(print),
        _ => {
            let outcome = show::show(&options.app, options.event, options.has("--force"));
            if options.has("-v") || options.has("--verbose") {
                print(&outcome);
            }
            if outcome.starts_with("failed") {
                die(format!("notifi: notify-send {outcome}"));
            }
        }
    }
}

/// Lists the agents left without a notification or, for waybar, counts
/// them.
fn pending(waybar: bool) {
    let Some(asked) = agents::ask(false) else {
        return;
    };
    let found = asked.finish(&mut Daemon::default());
    let waiting = found.waiting();
    let unseen = waiting.iter().filter(|agent| agent.seen.is_none()).count();
    if !waybar {
        for agent in waiting {
            let state = if agent.seen.is_none() {
                "pending"
            } else {
                "seen"
            };
            print(format!(
                "{}\t{}\t{state}",
                agent.pane.title, agent.event.body
            ));
        }
    } else if unseen > 0 {
        print(format!(r#"{{"text": "{unseen}", "class": "pending"}}"#));
    } else if !waiting.is_empty() {
        // Only once all were gone to, the seen ones.
        print(format!(
            r#"{{"text": "{}", "class": "seen"}}"#,
            waiting.len()
        ));
    }
}
