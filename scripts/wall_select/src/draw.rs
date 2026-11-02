//! Layout, colors and software drawing into an XRGB8888 buffer.

use std::fs;

use crate::{Result, text::Font, thumbs::Wallpaper};

/// Tiles per page.
pub const COLUMNS: usize = 6;

/// The geometry of the rofi theme this replaced, in
/// buffer pixels: a full-width strip holding one row of tiles, each a square
/// icon above a one-line label.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Layout {
    pub width: u32,
    pub height: u32,
    /// Left edge of the first tile.
    x0: u32,
    /// Top edge of every tile.
    y0: u32,
    gap: u32,
    tile_w: u32,
    tile_h: u32,
    /// Padding around the icon and label inside a tile.
    inset: u32,
    pub icon: u32,
    /// Label box offset from the tile's top edge, and its height.
    label_y: u32,
    label_h: u32,
}

impl Layout {
    pub fn new(width: u32, scale: f64, line_height: u32) -> Layout {
        let px = |logical: f64| (logical * scale).round() as u32;
        let (pad_x, pad_y, gap, inset) = (px(30.0), px(20.0), px(30.0), px(3.0));
        let (label_top, label_bottom) = (px(10.0), px(8.0));

        let cols = COLUMNS as u32;
        let inner = width.saturating_sub(2 * pad_x + (cols - 1) * gap);
        let tile_w = inner / cols;
        let icon = tile_w.saturating_sub(2 * inset).max(1);
        let label_y = inset + icon + label_top;
        let tile_h = label_y + line_height + label_bottom + inset;
        Layout {
            width,
            height: 2 * pad_y + tile_h,
            x0: pad_x + (inner - tile_w * cols) / 2,
            y0: pad_y,
            gap,
            tile_w,
            tile_h,
            inset,
            icon,
            label_y,
            label_h: line_height,
        }
    }

    fn tile_x(&self, col: usize) -> u32 {
        self.x0 + col as u32 * (self.tile_w + self.gap)
    }

    /// The column of the tile under a point, in buffer pixels.
    pub fn hit(&self, x: f64, y: f64) -> Option<usize> {
        let (x, y) = (x - f64::from(self.x0), y - f64::from(self.y0));
        if x < 0.0 || y < 0.0 || y >= f64::from(self.tile_h) {
            return None;
        }
        let stride = f64::from(self.tile_w + self.gap);
        let col = (x / stride) as usize;
        (col < COLUMNS && x - col as f64 * stride < f64::from(self.tile_w)).then_some(col)
    }
}

/// Colors as 0xAARRGGBB, from the file the theme system renders from
/// theme/templates/scripts/wall_select/colors.
pub struct Colors {
    pub background: u32,
    pub text: u32,
    pub selected_background: u32,
    pub selected_text: u32,
}

impl Colors {
    pub fn load() -> Result<Colors> {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/colors");
        let src = fs::read_to_string(path).map_err(|e| format!("{path}: {e} (run `theme`)"))?;
        let get = |key: &str| -> Result<u32> {
            src.lines()
                .filter_map(|line| line.split_once('='))
                .find(|(k, _)| k.trim() == key)
                .and_then(|(_, v)| u32::from_str_radix(v.trim().strip_prefix('#')?, 16).ok())
                .map(|rgb| 0xff00_0000 | rgb)
                .ok_or_else(|| format!("{path}: missing or invalid `{key}`").into())
        };
        Ok(Colors {
            background: get("background")?,
            text: get("text")?,
            selected_background: get("selected_background")?,
            selected_text: get("selected_text")?,
        })
    }
}

/// A mutable view of an XRGB8888 buffer (little endian: bytes B, G, R, X).
pub struct Canvas<'a> {
    pub buf: &'a mut [u8],
    pub width: u32,
    pub height: u32,
}

impl Canvas<'_> {
    fn stride(&self) -> usize {
        self.width as usize * 4
    }

    pub fn fill(&mut self, x: u32, y: u32, w: u32, h: u32, color: u32) {
        let (x1, y1) = ((x + w).min(self.width), (y + h).min(self.height));
        if x >= x1 || y >= y1 {
            return;
        }
        let row: Vec<u8> = color.to_le_bytes().repeat((x1 - x) as usize);
        let stride = self.stride();
        for y in y..y1 {
            let start = y as usize * stride + x as usize * 4;
            self.buf[start..start + row.len()].copy_from_slice(&row);
        }
    }

    /// Copies a square of `size` x `size` pixels in this canvas's format.
    fn blit(&mut self, x: u32, y: u32, size: u32, pixels: &[u8]) {
        let row_len = size as usize * 4;
        if pixels.len() != row_len * size as usize
            || x + size > self.width
            || y + size > self.height
        {
            return;
        }
        let stride = self.stride();
        for (r, src) in pixels.chunks_exact(row_len).enumerate() {
            let start = (y as usize + r) * stride + x as usize * 4;
            self.buf[start..start + row_len].copy_from_slice(src);
        }
    }

    /// Blends `color` over a pixel with the given coverage (0..=1).
    pub fn blend(&mut self, x: i32, y: i32, color: u32, coverage: f32) {
        if x < 0 || y < 0 || x as u32 >= self.width || y as u32 >= self.height {
            return;
        }
        let i = y as usize * self.stride() + x as usize * 4;
        let a = coverage.clamp(0.0, 1.0);
        let src = color.to_le_bytes();
        for (d, &s) in self.buf[i..i + 3].iter_mut().zip(&src) {
            *d = (f32::from(*d) + (f32::from(s) - f32::from(*d)) * a).round() as u8;
        }
    }
}

/// What a frame shows: the wallpapers on the current page, and which column
/// is selected.
pub struct Frame<'a> {
    pub walls: &'a [Wallpaper],
    pub page: &'a [usize],
    pub selected: Option<usize>,
}

pub fn frame(c: &mut Canvas, l: &Layout, colors: &Colors, font: &Font, f: &Frame) {
    c.fill(0, 0, c.width, c.height, colors.background);
    for (col, &i) in f.page.iter().enumerate() {
        let wall = &f.walls[i];
        let (x, y) = (l.tile_x(col), l.y0);
        let selected = f.selected == Some(col);
        if selected {
            c.fill(x, y, l.tile_w, l.tile_h, colors.selected_background);
        }
        c.blit(x + l.inset, y + l.inset, l.icon, &wall.pixels);
        let color = if selected { colors.selected_text } else { colors.text };
        let label_w = l.tile_w - 2 * l.inset;
        font.draw(c, &wall.label, (x + l.inset, y + l.label_y, label_w, l.label_h), color);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_rofi_at_1080p() {
        // Measured from a screenshot of the rofi picker: 285px tiles, 279px
        // icons, 362px strip with a 19px label line.
        let l = Layout::new(1920, 1.0, 19);
        assert_eq!((l.tile_w, l.icon, l.height, l.tile_x(2)), (285, 279, 362, 660));
        assert_eq!(l.hit(31.0, 30.0), Some(0));
        assert_eq!(l.hit(330.0, 30.0), None);
        assert_eq!(l.hit(1880.0, 30.0), Some(5));
        assert_eq!(l.hit(100.0, 10.0), None);
    }
}
