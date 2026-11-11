//! Other programs, and what /proc says of a process.

use std::fs;
use std::io::{ErrorKind, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const TIMEOUT: Duration = Duration::from_secs(3);

/// A command that was started and is not waited for yet. Starting one takes
/// 0.1 ms and tmux then takes 1.6 ms to answer, so whatever else there is to
/// do is done in between.
#[derive(Default)]
pub struct Running(Option<Child>);

fn spawn(command: &mut Command, stdin: Stdio) -> Running {
    let child = command
        .stdin(stdin)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    Running(child.ok())
}

pub fn start(command: &mut Command) -> Running {
    spawn(command, Stdio::null())
}

/// Like `start`, for a command that reads its input: what `tell` gives it.
pub fn start_open(command: &mut Command) -> Running {
    spawn(command, Stdio::piped())
}

/// Has the command start in a session of its own, so that it outlives
/// whatever started this: an agent's turn, or the terminal.
pub fn detach(command: &mut Command) {
    let own_session = || {
        unsafe { libc::setsid() };
        Ok(())
    };
    unsafe { command.pre_exec(own_session) };
}

impl Running {
    /// Its stdout up to the end or, with `last`, up to a line that says
    /// that. None, and it is killed, if it ends before that line or takes
    /// longer than 3 s.
    fn read(&mut self, last: Option<&str>) -> Option<String> {
        let child = self.0.as_mut()?;
        let stdout = child.stdout.as_mut()?;
        let last = last.map(|last| format!("\n{last}\n").into_bytes());
        let deadline = Instant::now() + TIMEOUT;
        let mut output = Vec::new();
        let mut chunk = [0; 16384];
        loop {
            let complete = last
                .as_ref()
                .is_some_and(|last| output.ends_with(last) || output == last[1..]);
            if complete {
                return Some(String::from_utf8_lossy(&output).into_owned());
            }
            let read = match readable(&*stdout, deadline) {
                true => stdout.read(&mut chunk).ok(),
                false => None,
            };
            match read {
                Some(0) if last.is_none() => {
                    return Some(String::from_utf8_lossy(&output).into_owned());
                }
                Some(count) if count > 0 => output.extend_from_slice(&chunk[..count]),
                _ => break,
            }
        }
        let _ = child.kill();
        let _ = child.wait();
        self.0 = None;
        None
    }

    /// What it has printed once it prints a line that says `last`: its
    /// whole answer, read without waiting for it to exit.
    pub fn answer(&mut self, last: &str) -> Option<String> {
        self.read(Some(last))
    }

    /// Gives it its input, all that it gets.
    pub fn tell(&mut self, input: &str) {
        if let Some(mut stdin) = self.0.as_mut().and_then(|child| child.stdin.take()) {
            let _ = stdin.write_all(input.as_bytes());
        }
    }

    /// Waits for it. The rest of its stdout, or None if it failed or took
    /// longer than 3 s.
    pub fn finish(mut self) -> Option<String> {
        self.tell("");
        let output = self.read(None)?;
        let done = self.0.as_mut()?.wait().ok()?;
        done.success().then_some(output)
    }
}

/// Whether `file` has something to read, or has ended, before `deadline`.
pub fn readable(file: &impl AsRawFd, deadline: Instant) -> bool {
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        let mut poll = libc::pollfd {
            fd: file.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let timeout = left.as_millis().try_into().unwrap_or(libc::c_int::MAX);
        let ready = unsafe { libc::poll(&mut poll, 1, timeout) };
        if ready > 0 {
            return true;
        }
        let interrupted = std::io::Error::last_os_error().kind() == ErrorKind::Interrupted;
        if ready == 0 || !interrupted {
            return false;
        }
    }
}

/// A field of /proc/<pid>/stat, counted from the one after the command name,
/// which may itself hold spaces and brackets.
fn stat(pid: i32, field: usize) -> Option<String> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let (_, rest) = stat.rsplit_once(')')?;
    rest.split_ascii_whitespace().nth(field).map(str::to_string)
}

/// A process's start time, which tells it from a later reuse of its pid.
pub fn start_time(pid: i32) -> Option<String> {
    stat(pid, 19)
}

/// A process and its parents, up to but not including init.
pub fn ancestors(mut pid: i32) -> Vec<i32> {
    let mut pids = Vec::new();
    while pid > 1 && !pids.contains(&pid) {
        pids.push(pid);
        pid = stat(pid, 1)
            .and_then(|parent| parent.parse().ok())
            .unwrap_or(0);
    }
    pids
}
