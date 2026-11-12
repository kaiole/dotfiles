//! Desktop notifications for coding agents in tmux, on Hyprland with dunst.
//!
//! `show` notifies for the agent in this tmux pane and returns at once; a
//! detached waiter stays until the notification closes and runs its Focus
//! action. An agent whose notification is closed without that stays pending,
//! and one that was gone to, or that stopped in view, stays seen: `pending`
//! lists both, `seen` the seen ones, and `next` focuses the pending ones,
//! then goes round the seen ones. Only a dismiss forgets an agent that
//! stopped. `go` is `next` unless a notification is on screen, whose action
//! it runs. `dismiss` forgets the agent from any later process. `start`
//! says that the agent is at work again, and `running` lists those. See
//! README.md.
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
use serde_json::json;

const USAGE: &str = "    notifi show [--event EVENT] [--app NAME] [--force] [-v]
    notifi start [--app NAME] [--hook]
    notifi dismiss [--app NAME | --focused]
    notifi pending [--waybar]
    notifi seen [--waybar]
    notifi running [--waybar]
    notifi next
    notifi go
    notifi status";

/// Each command's options; those that take an argument end in "=".
const OPTIONS: [(&str, &[&str]); 9] = [
    (
        "show",
        &["-v", "--verbose", "--force", "--event=", "--app="],
    ),
    ("start", &["--app=", "--hook"]),
    ("dismiss", &["--app=", "--focused"]),
    ("pending", &["--waybar"]),
    ("seen", &["--waybar"]),
    ("running", &["--waybar"]),
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
        "start" => show::start(&options.app, options.has("--hook")),
        "pending" => pending(options.has("--waybar")),
        "seen" => seen(options.has("--waybar")),
        "running" => running(options.has("--waybar")),
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

/// What waybar shows of the agents in one state: their count, and these
/// lines, one per agent, as its tooltip. With none it still shows the
/// module, with no count and class "none"; `alt` tells waybar which icon,
/// with or without the space before a count, to use.
fn module(state: &str, lines: &[String]) -> serde_json::Value {
    if lines.is_empty() {
        return json!({
            "text": "",
            "alt": "none",
            "tooltip": format!("No agent {state}"),
            "class": "none",
        });
    }
    // waybar reads a tooltip as Pango markup.
    let tooltip = lines.join("\n").replace('&', "&amp;");
    json!({
        "text": lines.len().to_string(),
        "alt": "some",
        "tooltip": tooltip.replace('<', "&lt;").replace('>', "&gt;"),
        "class": state,
    })
}

/// The agents as they are now; None without a record, which `ask` tells
/// without asking tmux (0.35 ms).
fn found() -> Option<agents::Found> {
    Some(agents::ask(false)?.finish(&mut Daemon::default()))
}

/// Lists the agents at work with how long each has been or, for waybar,
/// counts them, with that list as the tooltip.
fn running(waybar: bool) {
    let found = found();
    let now = state::now();
    let lines: Vec<String> = found
        .iter()
        .flat_map(|found| found.running())
        .map(|agent| {
            let minutes = ((now - agent.since) / 60.0) as u64;
            let long = match minutes {
                0 => "<1m".into(),
                1..60 => format!("{minutes}m"),
                _ => format!("{}h{:02}m", minutes / 60, minutes % 60),
            };
            format!("{}\t{long}", agent.pane.title)
        })
        .collect();
    if waybar {
        print(module("running", &lines));
    } else {
        lines.iter().for_each(print);
    }
}

/// Lists the waiting agents, pending and seen, in the order `next` takes
/// them or, for waybar, counts the pending ones.
fn pending(waybar: bool) {
    let found = found();
    let waiting = found
        .as_ref()
        .map(agents::Found::waiting)
        .unwrap_or_default();
    if waybar {
        let lines = waiting.iter().filter(|agent| agent.seen.is_none());
        print(module(
            "pending",
            &lines.map(|agent| line(agent)).collect::<Vec<_>>(),
        ));
        return;
    }
    for agent in waiting {
        let state = if agent.seen.is_none() {
            "pending"
        } else {
            "seen"
        };
        print(format!("{}\t{state}", line(agent)));
    }
}

/// Lists the seen agents, the one seen longest ago first, or, for waybar,
/// counts them.
fn seen(waybar: bool) {
    let found = found();
    let waiting = found
        .as_ref()
        .map(agents::Found::waiting)
        .unwrap_or_default();
    let lines: Vec<String> = waiting
        .iter()
        .filter(|agent| agent.seen.is_some())
        .map(|agent| line(agent))
        .collect();
    if waybar {
        print(module("seen", &lines));
    } else {
        lines.iter().for_each(print);
    }
}

fn line(agent: &agents::Agent) -> String {
    format!("{}\t{}", agent.pane.title, agent.event.body)
}
