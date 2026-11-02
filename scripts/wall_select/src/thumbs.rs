//! Wallpaper list and thumbnail cache.
//!
//! Each wallpaper <name> gets <cache>/<size>/<name>.bgra: raw XRGB8888
//! pixels (bytes B, G, R, X), center-cropped to size x size, so loading one
//! is a plain read with no decoding. A thumbnail is current when its mtime
//! equals the wallpaper's. Writes go to a temp file and are renamed into
//! place, so concurrent runs need no locks.

use std::{
    cmp::Ordering,
    collections::HashSet,
    env,
    ffi::{OsStr, OsString},
    fs::{self, File},
    io::{Read, Write},
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
    process,
    sync::atomic::{self, AtomicUsize},
    thread,
};

use fast_image_resize as fr;
use image::ImageReader;

use crate::Result;

/// Only the top level of the directory is listed; park wallpapers in a
/// subfolder (e.g. `archive/`) to hide them.
const EXTENSIONS: [&str; 6] = ["jpg", "jpeg", "png", "webp", "gif", "bmp"];

pub struct Wallpaper {
    pub path: PathBuf,
    /// File name without its extension.
    pub label: String,
    /// size * size XRGB8888 pixels; empty if the image couldn't be read.
    pub pixels: Vec<u8>,
}

pub fn wallpaper_dir() -> PathBuf {
    env::var_os("WALLPAPER_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join("images/wallpapers"))
}

pub fn cache_root() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".cache"))
        .join("wall_select")
}

fn home() -> PathBuf {
    env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

/// Wallpapers in `dir`, in natural order (like `sort -V`).
pub fn list(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut paths: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .filter_map(|entry| Some(entry.ok()?.path()))
        .filter(|path| {
            let ext = path.extension().and_then(OsStr::to_str);
            ext.is_some_and(|ext| EXTENSIONS.iter().any(|e| e.eq_ignore_ascii_case(ext)))
                && path.is_file()
        })
        .collect();
    paths.sort_by(|a, b| natural_cmp(name(a).as_bytes(), name(b).as_bytes()));
    Ok(paths)
}

fn name(path: &Path) -> &OsStr {
    path.file_name().unwrap_or_default()
}

/// Loads every thumbnail at `size`, regenerating stale ones in parallel.
pub fn load(paths: Vec<PathBuf>, size: u32) -> Vec<Wallpaper> {
    let dir = cache_root().join(size.to_string());
    let _ = fs::create_dir_all(&dir);
    let len = (size * size * 4) as usize;
    let mut walls: Vec<Wallpaper> = paths
        .into_iter()
        .map(|path| Wallpaper {
            label: path.file_stem().unwrap_or_default().to_string_lossy().into_owned(),
            pixels: read_cached(&path, &thumb_path(&dir, &path), len).unwrap_or_default(),
            path,
        })
        .collect();

    let stale: Vec<usize> = (0..walls.len()).filter(|&i| walls[i].pixels.is_empty()).collect();
    if stale.is_empty() {
        return walls;
    }
    // Workers take the next stale index, so one big image doesn't hold up
    // a whole batch.
    let next = AtomicUsize::new(0);
    let jobs = thread::available_parallelism().map_or(4, |n| n.get()).min(stale.len());
    let done: Vec<(usize, Vec<u8>)> = thread::scope(|s| {
        let workers: Vec<_> = (0..jobs)
            .map(|_| {
                s.spawn(|| {
                    let mut out = Vec::new();
                    loop {
                        let k = next.fetch_add(1, atomic::Ordering::Relaxed);
                        let Some(&i) = stale.get(k) else { break out };
                        let src = &walls[i].path;
                        match generate(src, &thumb_path(&dir, src), size) {
                            Ok(pixels) => out.push((i, pixels)),
                            Err(e) => eprintln!("wall_select: {}: {e}", src.display()),
                        }
                    }
                })
            })
            .collect();
        workers.into_iter().flat_map(|w| w.join().unwrap_or_default()).collect()
    });
    for (i, pixels) in done {
        walls[i].pixels = pixels;
    }
    walls
}

fn thumb_path(dir: &Path, src: &Path) -> PathBuf {
    let mut file = OsString::from(name(src));
    file.push(".bgra");
    dir.join(file)
}

fn read_cached(src: &Path, thumb: &Path, len: usize) -> Option<Vec<u8>> {
    let src_mtime = fs::metadata(src).ok()?.modified().ok()?;
    let mut file = File::open(thumb).ok()?;
    let meta = file.metadata().ok()?;
    if meta.modified().ok()? != src_mtime || meta.len() != len as u64 {
        return None;
    }
    let mut pixels = Vec::with_capacity(len);
    file.read_to_end(&mut pixels).ok()?;
    (pixels.len() == len).then_some(pixels)
}

fn generate(src: &Path, thumb: &Path, size: u32) -> Result<Vec<u8>> {
    let mtime = fs::metadata(src)?.modified()?;
    let image = ImageReader::open(src)?.with_guessed_format()?.decode()?.into_rgba8();
    let (w, h) = image.dimensions();
    let side = w.min(h);
    let image = fr::images::Image::from_vec_u8(w, h, image.into_raw(), fr::PixelType::U8x4)?;
    let mut scaled = fr::images::Image::new(size, size, fr::PixelType::U8x4);
    let options = fr::ResizeOptions::new()
        .resize_alg(fr::ResizeAlg::Convolution(fr::FilterType::Lanczos3))
        .crop(((w - side) / 2) as f64, ((h - side) / 2) as f64, side as f64, side as f64);
    fr::Resizer::new().resize(&image, &mut scaled, &options)?;

    // RGBA -> XRGB8888, flattening any transparency onto black.
    let mut pixels = scaled.into_vec();
    for px in pixels.as_chunks_mut::<4>().0 {
        let a = u32::from(px[3]);
        let [r, g, b] = [px[0], px[1], px[2]].map(|c| ((u32::from(c) * a + 127) / 255) as u8);
        *px = [b, g, r, 0xff];
    }

    let mut tmp = thumb.as_os_str().to_owned();
    tmp.push(format!(".{}.tmp", process::id()));
    let write = || -> std::io::Result<()> {
        let mut file = File::create(&tmp)?;
        file.write_all(&pixels)?;
        file.set_modified(mtime)?;
        fs::rename(&tmp, thumb)
    };
    if let Err(e) = write() {
        let _ = fs::remove_file(&tmp);
        return Err(e.into());
    }
    Ok(pixels)
}

/// Deletes thumbnails of removed wallpapers (at every size) and temp files
/// left by killed runs.
pub fn prune(paths: &[PathBuf]) {
    let names: HashSet<&[u8]> = paths.iter().map(|p| name(p).as_bytes()).collect();
    let Ok(sizes) = fs::read_dir(cache_root()) else { return };
    for dir in sizes.flatten().filter(|e| e.file_type().is_ok_and(|t| t.is_dir())) {
        let Ok(entries) = fs::read_dir(dir.path()) else { continue };
        for entry in entries.flatten() {
            let file = entry.file_name();
            let file = file.as_bytes();
            let keep = if let Some(src) = file.strip_suffix(b".bgra") {
                names.contains(src)
            } else if let Some(rest) = file.strip_suffix(b".tmp") {
                // <name>.bgra.<pid>.tmp: keep it while that run is alive.
                let pid = rest.rsplit(|&b| b == b'.').next().unwrap_or_default();
                !pid.is_empty()
                    && pid.iter().all(u8::is_ascii_digit)
                    && Path::new("/proc").join(OsStr::from_bytes(pid)).exists()
            } else {
                false
            };
            if !keep {
                let _ = fs::remove_file(entry.path());
            }
        }
    }
}

/// Compares runs of digits by value, everything else bytewise.
fn natural_cmp(a: &[u8], b: &[u8]) -> Ordering {
    let (mut i, mut j) = (0, 0);
    while i < a.len() && j < b.len() {
        if a[i].is_ascii_digit() && b[j].is_ascii_digit() {
            let (si, sj) = (i, j);
            while i < a.len() && a[i].is_ascii_digit() {
                i += 1;
            }
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
            let trim = |s: &[u8]| -> usize { s.iter().take_while(|&&c| c == b'0').count() };
            let (x, y) = (&a[si + trim(&a[si..i])..i], &b[sj + trim(&b[sj..j])..j]);
            match x.len().cmp(&y.len()).then(x.cmp(y)) {
                Ordering::Equal => {}
                ord => return ord,
            }
        } else {
            match a[i].cmp(&b[j]) {
                Ordering::Equal => (i, j) = (i + 1, j + 1),
                ord => return ord,
            }
        }
    }
    (a.len() - i).cmp(&(b.len() - j)).then(a.cmp(b))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn natural_order() {
        let mut v = vec!["wall10.png", "wall2.png", "Wall1.png", "abc.png", "wall02.png"];
        v.sort_by(|a, b| natural_cmp(a.as_bytes(), b.as_bytes()));
        assert_eq!(v, ["Wall1.png", "abc.png", "wall02.png", "wall2.png", "wall10.png"]);
    }
}
