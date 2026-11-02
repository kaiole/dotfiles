//! awww: read the wallpaper an output shows, and set a new one.

use std::{
    io,
    os::unix::process::CommandExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::Duration,
};

pub struct Status {
    pub running: bool,
    pub current: Option<PathBuf>,
}

pub fn query(output: &str) -> Status {
    let out = Command::new("awww")
        .arg("query")
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output();
    match out {
        Ok(out) if out.status.success() => Status {
            running: true,
            current: String::from_utf8_lossy(&out.stdout)
                .lines()
                .find_map(|line| displayed(line, output)),
        },
        _ => Status { running: false, current: None },
    }
}

/// Parses `: eDP-1: 1920x1080, scale: 1, currently displaying: image: /path`.
fn displayed(line: &str, output: &str) -> Option<PathBuf> {
    let (_, rest) = line.split_once(':')?;
    let rest = rest.strip_prefix(' ').unwrap_or(rest);
    let (_, path) = rest.strip_prefix(output)?.strip_prefix(':')?.rsplit_once(" image: ")?;
    (!path.is_empty()).then(|| PathBuf::from(path))
}

/// Replaces this process with `awww img`, starting the daemon first if it
/// isn't running (autostart normally runs it). Returns only on failure.
pub fn set(output: &str, path: &Path, fps: u32, running: bool) -> io::Error {
    if !running {
        let spawned = Command::new("awww-daemon")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .process_group(0)
            .spawn();
        if let Err(e) = spawned {
            return e;
        }
        for _ in 0..20 {
            if query(output).running {
                break;
            }
            thread::sleep(Duration::from_millis(100));
        }
    }
    Command::new("awww")
        .args(["img", "-o", output])
        .arg(path)
        .args(["--transition-type", "wipe", "--transition-angle", "180"])
        .args(["--transition-duration", "2", "--transition-fps"])
        .arg(fps.to_string())
        .exec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_query_line() {
        let line = ": eDP-1: 1920x1080, scale: 1, currently displaying: image: /w/a b.png";
        assert_eq!(displayed(line, "eDP-1"), Some(PathBuf::from("/w/a b.png")));
        assert_eq!(displayed(line, "DP-3"), None);
        assert_eq!(displayed(": eDP-1: 1920x1080, currently displaying: color: 000000", "eDP-1"), None);
    }
}
