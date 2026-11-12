//! tmux. $TMUX is "<socket>,<server pid>,<session>"; tmux itself cuts it at
//! the first comma, so the socket is passed explicitly. -N keeps a command
//! from starting a new server if that one is gone.
//!
//! Every call costs 1.6 ms however much it asks, 1.1 of them for tmux to
//! start, so each question is one call: commands are joined with ";" and
//! their output told apart by the first field. The tmux that answered can
//! stay to run what follows from its answer, which saves starting another.

use std::collections::HashMap;
use std::env;
use std::path::PathBuf;
use std::process::Command;
use std::sync::OnceLock;

use crate::run::{self, Running};

#[derive(Clone)]
pub struct Pane {
    pub id: String,
    pub socket: String,
    /// The tmux server's pid; pane ids start over when it does.
    pub server: String,
    pub session_id: String,
    pub window_id: String,
    pub title: String,
}

pub struct Client {
    pub pid: i32,
    pub tty: String,
    pub session_id: String,
    pub window_id: String,
    /// The active pane of the window it shows.
    pub pane_id: String,
    pub activity: i64,
}

/// What a tmux server answered: its panes by id, and its clients.
#[derive(Default)]
pub struct Server {
    pub panes: HashMap<String, Pane>,
    pub clients: Vec<Client>,
    /// The tmux that asked, which takes commands for `show` if it stayed.
    pub asked: Running,
}

const PANE: &str = "P\t#{pane_id}\t#{pid}\t#{session_id}\t#{window_id}\t#S:#{window_index}";
const CLIENT: &str = "C\t#{client_pid}\t#{client_tty}\t#{session_id}\
    \t#{window_id}\t#{pane_id}\t#{client_activity}";
/// The last line of an answer, which can then be read without waiting for
/// tmux to exit.
const END: &str = ".";

/// The socket of the tmux server this command runs in.
pub fn socket() -> Option<String> {
    let tmux = env::var("TMUX").ok()?;
    let parts: Vec<&str> = tmux.split(',').collect();
    let socket = parts[..parts.len().saturating_sub(2)].join(",");
    (!socket.is_empty()).then_some(socket)
}

/// The pid of that server, which its panes are told from an earlier
/// server's by.
pub fn server() -> Option<String> {
    let tmux = env::var("TMUX").ok()?;
    let pid = tmux.rsplit(',').nth(1)?;
    (!pid.is_empty()).then(|| pid.into())
}

/// The pane this command runs in, by $TMUX_PANE.
fn pane_id() -> Option<String> {
    env::var("TMUX_PANE").ok().filter(|pane| !pane.is_empty())
}

/// What identifies the agent running this command: its socket and pane id.
pub fn own() -> Option<(String, String)> {
    Some((socket()?, pane_id()?))
}

/// tmux, found on $PATH here because it is started with an empty environment.
fn program() -> &'static PathBuf {
    static PROGRAM: OnceLock<PathBuf> = OnceLock::new();
    PROGRAM.get_or_init(|| {
        env::split_paths(&env::var_os("PATH").unwrap_or_default())
            .map(|directory| directory.join("tmux"))
            .find(|path| path.is_file())
            .unwrap_or_else(|| "tmux".into())
    })
}

fn command(socket: &str, args: &[&str]) -> Command {
    // A tmux client sends its environment to the server one variable at a
    // time, 0.15 ms of the call, and no command here uses it. Without a
    // locale it takes -u to leave non-ASCII names as they are.
    let mut command = Command::new(program());
    command
        .env_clear()
        .args(["-u", "-N", "-S", socket])
        .args(args);
    command
}

pub fn start(socket: &str, args: &[&str]) -> Running {
    run::start(&mut command(socket, args))
}

/// Starts a tmux with a question. With `stay` it then reads commands from
/// its input, see `show`, and the server runs them 0.3 ms after they are
/// given instead of the 1.6 ms that another tmux takes.
fn ask(socket: &str, question: &[&str], stay: bool) -> Running {
    let mut args = question.to_vec();
    args.extend([";", "display-message", "-p", END]);
    if stay {
        args.extend([";", "source-file", "-"]);
        run::start_open(&mut command(socket, &args))
    } else {
        run::start(&mut command(socket, &args))
    }
}

/// Asks a server for every pane and client it has.
pub fn survey(socket: &str, stay: bool) -> Running {
    let panes = ["list-panes", "-a", "-F", PANE];
    let clients = [";", "list-clients", "-F", CLIENT];
    ask(socket, &[&panes[..], &clients[..]].concat(), stay)
}

/// Has tmux show a pane: selects it in its window and session and, given a
/// client, switches that one to its session. `asked` is a tmux that stayed.
pub fn show(asked: &mut Running, pane: &Pane, client: Option<&Client>) {
    // tmux reads these as it reads its configuration, where nothing between
    // single quotes is special: not the $ of a session id either.
    let mut commands = format!("select-window -t '{0}'\nselect-pane -t '{0}'\n", pane.id);
    if let Some(client) = client {
        let switch = format!(
            "switch-client -c '{}' -t '{}'\n",
            client.tty, pane.session_id
        );
        commands.push_str(&switch);
    }
    // The ids and the tty are tmux's own, which have no quote in them.
    let values = [
        &pane.id,
        &pane.session_id,
        client.map_or(&pane.id, |client| &client.tty),
    ];
    if values.iter().all(|value| !value.contains(['\'', '\n'])) {
        asked.tell(&commands);
    }
}

/// The panes and clients that a tmux answers with, in PANE and CLIENT.
pub fn read(socket: &str, mut asked: Running) -> Server {
    let listing = asked.answer(END).unwrap_or_default();
    let mut server = Server {
        asked,
        ..Server::default()
    };
    for line in listing.lines() {
        if let Some(pane) = line.strip_prefix("P\t") {
            let fields: Vec<&str> = pane.splitn(5, '\t').collect();
            // tmux answers for a dead pane too, with an empty id, session
            // and window.
            if fields.len() == 5 && fields[..4].iter().all(|f| !f.is_empty()) {
                let pane = Pane {
                    id: fields[0].into(),
                    socket: socket.into(),
                    server: fields[1].into(),
                    session_id: fields[2].into(),
                    window_id: fields[3].into(),
                    title: fields[4].into(),
                };
                server.panes.insert(pane.id.clone(), pane);
            }
        } else if let Some(client) = line.strip_prefix("C\t") {
            let fields: Vec<&str> = client.split('\t').collect();
            let numbers = (
                fields.first().and_then(|pid| pid.parse().ok()),
                fields.get(5).and_then(|activity| activity.parse().ok()),
            );
            if let (6, (Some(pid), Some(activity))) = (fields.len(), numbers) {
                server.clients.push(Client {
                    pid,
                    tty: fields[1].into(),
                    session_id: fields[2].into(),
                    window_id: fields[3].into(),
                    pane_id: fields[4].into(),
                    activity,
                });
            }
        }
    }
    server
}

/// A question to tmux about the pane this command runs in.
pub struct Look {
    socket: String,
    pane: String,
    asked: Running,
}

/// Asks for the agent's own pane as it is now, because panes move, and for
/// the clients of its server.
pub fn look(stay: bool) -> Option<Look> {
    let (socket, pane) = own()?;
    let own = ["display-message", "-p", "-t", &pane, PANE];
    let clients = [";", "list-clients", "-F", CLIENT];
    let asked = ask(&socket, &[&own[..], &clients[..]].concat(), stay);
    Some(Look {
        socket,
        pane,
        asked,
    })
}

impl Look {
    /// The pane and the rest of its server, or None if the pane is gone.
    pub fn finish(self) -> Option<(Pane, Server)> {
        let mut server = read(&self.socket, self.asked);
        Some((server.panes.remove(&self.pane)?, server))
    }
}
