//! Tile labels, in the font rofi used (rofi/share/fonts.rasi). ab_glyph
//! parses glyphs on demand, which matters for a Nerd Font with thousands of
//! icon glyphs.

use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use ab_glyph::{Font as _, FontVec, GlyphId, PxScale, ScaleFont, point};

use crate::{Result, draw::Canvas, thumbs};

const FAMILY: &str = "CaskaydiaCove Nerd Font";
const SIZE_PT: f32 = 12.0;

pub struct Font {
    font: FontVec,
    scale: PxScale,
    ascent: f32,
    pub line_height: u32,
}

impl Font {
    pub fn load(ui_scale: f64) -> Result<Font> {
        let font = FontVec::try_from_vec(fs::read(font_path()?)?)?;
        // Points at 96 dpi, like Pango. ab_glyph's PxScale sets the
        // ascent-to-descent height rather than the em size.
        let em = SIZE_PT * 96.0 / 72.0 * ui_scale as f32;
        let units_per_em = font.units_per_em().ok_or("font has no units per em")?;
        let scale = PxScale::from(em * font.height_unscaled() / units_per_em);
        let scaled = font.as_scaled(scale);
        Ok(Font {
            ascent: scaled.ascent(),
            line_height: (scaled.ascent() - scaled.descent()).round() as u32,
            scale,
            font,
        })
    }

    /// Draws `text` centered in `(x, y, w, h)`, ellipsized to fit.
    pub fn draw(&self, c: &mut Canvas, text: &str, (x, y, w, h): (u32, u32, u32, u32), color: u32) {
        let scaled = self.font.as_scaled(self.scale);
        let glyph = |ch: char| {
            let id = scaled.glyph_id(ch);
            (id, scaled.h_advance(id))
        };
        let mut glyphs: Vec<(GlyphId, f32)> = text.chars().map(glyph).collect();
        let width = |g: &[(GlyphId, f32)]| g.iter().map(|&(_, adv)| adv).sum::<f32>();
        let max = w as f32;
        if width(&glyphs) > max {
            let ellipsis = glyph('…');
            while !glyphs.is_empty() && width(&glyphs) + ellipsis.1 > max {
                glyphs.pop();
            }
            glyphs.push(ellipsis);
        }

        let mut pen = (x as f32 + (max - width(&glyphs)) / 2.0).round();
        let baseline = (y + h.saturating_sub(self.line_height) / 2) as f32 + self.ascent.round();
        for (id, advance) in glyphs {
            let positioned = id.with_scale_and_position(self.scale, point(pen, baseline));
            if let Some(outline) = self.font.outline_glyph(positioned) {
                let min = outline.px_bounds().min;
                outline.draw(|gx, gy, coverage| {
                    c.blend(min.x as i32 + gx as i32, min.y as i32 + gy as i32, color, coverage);
                });
            }
            pen += advance;
        }
    }
}

/// The font file, from fontconfig. fc-match costs a few milliseconds, so
/// the answer is cached as "<family>\n<path>".
fn font_path() -> Result<PathBuf> {
    let cache = thumbs::cache_root().join("font");
    if let Ok(cached) = fs::read_to_string(&cache)
        && let Some((family, path)) = cached.split_once('\n')
        && family == FAMILY
        && Path::new(path).is_file()
    {
        return Ok(path.into());
    }
    let out = Command::new("fc-match")
        .args(["-f", "%{file}", &format!("{FAMILY}:style=Regular")])
        .output()
        .map_err(|e| format!("fc-match: {e}"))?;
    let path = String::from_utf8(out.stdout)?;
    if path.is_empty() {
        return Err(format!("fc-match found no font for {FAMILY}").into());
    }
    let _ = fs::create_dir_all(thumbs::cache_root());
    let _ = fs::write(&cache, format!("{FAMILY}\n{path}"));
    Ok(path.into())
}
