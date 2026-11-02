//! Selection, paging and filtering, independent of Wayland.
//!
//! Filtering follows the rofi config (`matching: "prefix"`, `-i`): the
//! input splits on whitespace, and every token must match the start of a
//! word in the label, ignoring case.

use crate::draw::COLUMNS;

pub struct Picker {
    labels: Vec<String>,
    filter: String,
    /// Indices of the labels that pass the filter.
    matches: Vec<usize>,
    /// Index into `matches`.
    sel: usize,
}

impl Picker {
    pub fn new<'a>(labels: impl IntoIterator<Item = &'a str>, selected: usize) -> Picker {
        let labels: Vec<String> = labels.into_iter().map(str::to_lowercase).collect();
        let matches = (0..labels.len()).collect();
        Picker { labels, filter: String::new(), matches, sel: selected }
    }

    /// The selected label's index.
    pub fn selected(&self) -> Option<usize> {
        self.matches.get(self.sel).copied()
    }

    /// The page holding the selection, and the selection's column on it.
    /// Pages are whole rows, like rofi's default per-page scrolling.
    pub fn page(&self) -> (&[usize], Option<usize>) {
        if self.matches.is_empty() {
            return (&[], None);
        }
        let start = self.sel / COLUMNS * COLUMNS;
        let end = (start + COLUMNS).min(self.matches.len());
        (&self.matches[start..end], Some(self.sel - start))
    }

    /// Moves by `delta`, wrapping around (rofi's `cycle: true`).
    pub fn step(&mut self, delta: isize) {
        let n = self.matches.len() as isize;
        if n > 0 {
            self.sel = (self.sel as isize + delta).rem_euclid(n) as usize;
        }
    }

    /// Moves a page forward or back, stopping at the ends.
    pub fn page_step(&mut self, pages: isize) {
        let last = self.matches.len().saturating_sub(1) as isize;
        self.sel = (self.sel as isize + pages * COLUMNS as isize).clamp(0, last) as usize;
    }

    pub fn first(&mut self) {
        self.sel = 0;
    }

    pub fn last(&mut self) {
        self.sel = self.matches.len().saturating_sub(1);
    }

    /// Selects a column on the current page; false if it's empty or
    /// already selected.
    pub fn select_column(&mut self, col: usize) -> bool {
        let (page, current) = self.page();
        if col >= page.len() || current == Some(col) {
            return false;
        }
        self.sel = self.sel / COLUMNS * COLUMNS + col;
        true
    }

    pub fn push(&mut self, text: &str) {
        self.filter.push_str(text);
        self.refilter();
    }

    pub fn pop(&mut self) {
        if self.filter.pop().is_some() {
            self.refilter();
        }
    }

    pub fn clear(&mut self) {
        if !self.filter.is_empty() {
            self.filter.clear();
            self.refilter();
        }
    }

    fn refilter(&mut self) {
        let tokens: Vec<String> = self.filter.split_whitespace().map(str::to_lowercase).collect();
        self.matches = (0..self.labels.len())
            .filter(|&i| tokens.iter().all(|t| matches_word_start(&self.labels[i], t)))
            .collect();
        self.sel = 0;
    }
}

/// Like the regex `\b<token>`: the token occurs where the character before
/// it (or the start of the label, a non-word) differs in word-ness from the
/// token's first character.
fn matches_word_start(label: &str, token: &str) -> bool {
    let is_word = |c: char| c.is_alphanumeric() || c == '_';
    let Some(first) = token.chars().next() else { return true };
    label.match_indices(token).any(|(i, _)| {
        label[..i].chars().next_back().is_some_and(is_word) != is_word(first)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn picker() -> Picker {
        let labels = ["abstract", "black", "cabin", "city", "color-pixel", "dark-pixel", "katana"];
        Picker::new(labels, 0)
    }

    #[test]
    fn prefix_filter() {
        let mut p = picker();
        p.push("pix");
        assert_eq!(p.matches, [4, 5]);
        p.clear();
        p.push("C");
        assert_eq!(p.matches, [2, 3, 4]);
        p.push("ab");
        assert_eq!(p.matches, [2]);
        p.clear();
        p.push("bin");
        assert!(p.matches.is_empty());
        assert_eq!(p.selected(), None);
        p.clear();
        p.push("dark pix");
        assert_eq!(p.matches, [5]);
    }

    #[test]
    fn paging_and_wrapping() {
        let mut p = picker();
        p.step(-1);
        assert_eq!(p.selected(), Some(6));
        assert_eq!(p.page(), (&[6][..], Some(0)));
        p.step(1);
        assert_eq!(p.page(), (&[0, 1, 2, 3, 4, 5][..], Some(0)));
        assert!(p.select_column(3));
        assert!(!p.select_column(3));
        assert_eq!(p.selected(), Some(3));
        p.page_step(1);
        assert_eq!(p.selected(), Some(6));
        p.page_step(-1);
        assert_eq!(p.selected(), Some(0));
    }
}
