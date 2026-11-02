//! wall_select: pick a wallpaper from a strip of thumbnails and show it on
//! the focused monitor with awww. Running it again closes the picker.
//!
//! This replaces a bash script that drove rofi, whose thumbnails appeared
//! ~90ms after the rest of the window: rofi waits 66ms before redrawing
//! after icons load, and gdk-pixbuf decodes each image in a sandboxed glycin
//! process. Here thumbnails are cached as raw pixels, read before the first
//! configure, and drawn with everything else into a single first frame.
//!
//! WALL_SELECT_TRACE=1 logs startup timings to stderr, measured from
//! WALL_SELECT_T0 (Unix time in ns, for a benchmark harness) or else from
//! the start of main. `--bench` traces, never toggles, and exits once the
//! compositor has shown the first frame.

mod awww;
mod draw;
mod hypr;
mod picker;
mod text;
mod thumbs;
mod ui;

use std::{
    env,
    path::{Path, PathBuf},
    process::{Command, ExitCode},
    thread,
};

use draw::{Colors, Layout};
use text::Font;
use thumbs::Wallpaper;
use ui::Outcome;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

/// Everything the picker shows, loaded off the main thread.
pub struct Content {
    pub walls: Vec<Wallpaper>,
    /// The wallpaper on screen now, or the first.
    pub selected: usize,
    /// Thumbnail size in pixels.
    pub icon: u32,
    pub awww_running: bool,
}

fn main() -> ExitCode {
    let bench = env::args().skip(1).any(|a| a == "--bench");
    trace::init(bench);
    match run(bench) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("wall_select: {e}");
            let _ = Command::new("notify-send").args(["-a", "wall_select", &format!("{e}")]).status();
            ExitCode::FAILURE
        }
    }
}

fn run(bench: bool) -> Result<()> {
    let runtime = PathBuf::from(env::var_os("XDG_RUNTIME_DIR").ok_or("XDG_RUNTIME_DIR is unset")?);
    if !bench && instance::close_running(&runtime) {
        return Ok(());
    }
    instance::close_rofi(&runtime);
    let pidfile = instance::PidFile::create(&runtime);

    let monitor = hypr::focused_monitor()?;
    trace::mark("monitor queried");
    let icon = Layout::new(monitor.width, monitor.scale, 0).icon;
    let output = monitor.name.clone();
    let content = thread::spawn(move || load_content(&output, icon));
    let colors = Colors::load()?;
    let font = Font::load(monitor.scale)?;
    trace::mark("font loaded");

    let inputs = ui::Inputs { scale: monitor.scale, width: monitor.width, font, colors, content, bench };
    let (outcome, content) = ui::run(inputs)?;
    match outcome {
        Outcome::Cancel => Ok(()),
        Outcome::Apply(i) => {
            drop(pidfile);
            let path = &content.walls[i].path;
            Err(awww::set(&monitor.name, path, monitor.refresh_hz, content.awww_running).into())
        }
    }
}

fn load_content(output: &str, icon: u32) -> Result<Content> {
    let output = output.to_owned();
    let status = thread::spawn(move || awww::query(&output));
    let dir = thumbs::wallpaper_dir();
    let paths = thumbs::list(&dir)?;
    if paths.is_empty() {
        return Err(format!("no wallpapers in {}", dir.display()).into());
    }
    let walls = thumbs::load(paths, icon);
    let status = status.join().unwrap_or(awww::Status { running: false, current: None });
    let selected = status
        .current
        .and_then(|current| walls.iter().position(|w| w.path == current))
        .unwrap_or(0);
    Ok(Content { walls, selected, icon, awww_running: status.running })
}

/// One picker at a time: a second run closes the first. pgrep would do,
/// but scanning /proc costs ~40ms; a pidfile checked against
/// /proc/<pid>/comm costs nothing.
mod instance {
    use std::{fs, path::PathBuf, process};

    use super::Path;

    const NAME: &str = "wall_select";

    fn read_pid(path: &Path) -> Option<i32> {
        fs::read_to_string(path).ok()?.trim().parse().ok()
    }

    fn is(pid: i32, comm: &str) -> bool {
        fs::read_to_string(format!("/proc/{pid}/comm")).is_ok_and(|c| c.trim_end() == comm)
    }

    fn terminate(pid: i32) -> bool {
        // SAFETY: kill has no memory-safety preconditions.
        unsafe { libc::kill(pid, libc::SIGTERM) == 0 }
    }

    /// Closes a running picker; true if there was one.
    pub fn close_running(runtime: &Path) -> bool {
        match read_pid(&runtime.join(format!("{NAME}.pid"))) {
            Some(pid) if pid as u32 != process::id() && is(pid, NAME) => terminate(pid),
            _ => false,
        }
    }

    /// Closes the rofi launcher, if open, as `rofi -replace` did.
    pub fn close_rofi(runtime: &Path) {
        if let Some(pid) = read_pid(&runtime.join("rofi.pid"))
            && is(pid, "rofi")
        {
            terminate(pid);
        }
    }

    pub struct PidFile(PathBuf);

    impl PidFile {
        pub fn create(runtime: &Path) -> PidFile {
            let path = runtime.join(format!("{NAME}.pid"));
            let _ = fs::write(&path, process::id().to_string());
            PidFile(path)
        }
    }

    impl Drop for PidFile {
        fn drop(&mut self) {
            if read_pid(&self.0) == Some(process::id() as i32) {
                let _ = fs::remove_file(&self.0);
            }
        }
    }
}

mod trace {
    use std::{
        env,
        sync::OnceLock,
        time::{Duration, SystemTime, UNIX_EPOCH},
    };

    /// When timing started, if tracing is on.
    static START: OnceLock<Option<SystemTime>> = OnceLock::new();

    pub fn init(force: bool) {
        let on = force || env::var("WALL_SELECT_TRACE").is_ok_and(|v| !v.is_empty() && v != "0");
        let t0 = env::var("WALL_SELECT_T0")
            .ok()
            .and_then(|ns| ns.parse().ok())
            .map(|ns| UNIX_EPOCH + Duration::from_nanos(ns))
            .unwrap_or_else(SystemTime::now);
        let _ = START.set(on.then_some(t0));
        mark("main");
    }

    pub fn mark(what: &str) {
        if let Some(Some(t0)) = START.get() {
            let ms = t0.elapsed().unwrap_or_default().as_secs_f64() * 1e3;
            eprintln!("wall_select: {ms:7.2} ms  {what}");
        }
    }
}
