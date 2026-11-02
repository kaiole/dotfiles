//! The focused monitor, read from Hyprland's IPC socket (what `hyprctl -j
//! monitors` asks for), which saves spawning hyprctl and jq.

use std::{
    env,
    io::{Read, Write},
    os::unix::net::UnixStream,
};

use serde::Deserialize;

use crate::Result;

pub struct Monitor {
    pub name: String,
    /// Width in pixels with rotation applied.
    pub width: u32,
    pub scale: f64,
    pub refresh_hz: u32,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Raw {
    name: String,
    width: u32,
    height: u32,
    scale: f64,
    transform: u32,
    refresh_rate: f64,
    focused: bool,
}

pub fn focused_monitor() -> Result<Monitor> {
    let runtime = env::var("XDG_RUNTIME_DIR").map_err(|_| "XDG_RUNTIME_DIR is unset")?;
    let sig = env::var("HYPRLAND_INSTANCE_SIGNATURE")
        .map_err(|_| "HYPRLAND_INSTANCE_SIGNATURE is unset; is Hyprland running?")?;
    let mut sock = UnixStream::connect(format!("{runtime}/hypr/{sig}/.socket.sock"))?;
    sock.write_all(b"j/monitors")?;
    let mut reply = Vec::new();
    sock.read_to_end(&mut reply)?;

    let monitors: Vec<Raw> = serde_json::from_slice(&reply)?;
    let m = monitors.into_iter().find(|m| m.focused).ok_or("no focused monitor")?;
    // Odd transforms rotate by 90 or 270 degrees.
    let width = if m.transform % 2 == 1 { m.height } else { m.width };
    Ok(Monitor {
        name: m.name,
        width,
        scale: m.scale,
        refresh_hz: m.refresh_rate.round() as u32,
    })
}
