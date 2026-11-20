/**
 * The three things browse needs from the fullscreen viewport that pi-tui keeps
 * private: the transcript's content lines, setting the text selection, and
 * scrolling without follow. On stock pi these are reached through TuiAltScreen
 * internals, so this file is the only one that breaks if they change.
 */
import { type Component, isViewportTUI, type ScrollView, type TUI } from "@earendil-works/pi-tui";

interface SelectionPoint {
	row: number;
	col: number;
	scrollView?: ScrollView;
	boundary?: boolean;
}

interface Box {
	readonly children: readonly Box[];
	readonly scrollView?: ScrollView;
	readonly scrollContentLines?: readonly string[];
}

/** TuiAltScreen as of pi 1.6.0, including the private members browse reads. */
interface AltScreen extends TUI {
	currentLayout?: { readonly root: Box };
	selectionAnchor?: SelectionPoint;
	selectionFocus?: SelectionPoint;
	getPrimaryScrollView(): ScrollView;
	getFocusedComponent(): Component | null;
	copyActiveSelectionToClipboard(): Promise<boolean>;
	resetTextSelection(): void;
}

function isAltScreen(tui: TUI): tui is AltScreen {
	return (
		isViewportTUI(tui) &&
		"currentLayout" in tui &&
		"selectionAnchor" in tui &&
		typeof Reflect.get(tui, "getPrimaryScrollView") === "function" &&
		typeof Reflect.get(tui, "copyActiveSelectionToClipboard") === "function"
	);
}

function findScrollBox(box: Box, scrollView: ScrollView): Box | undefined {
	if (box.scrollView === scrollView) return box;
	for (const child of box.children) {
		const found = findScrollBox(child, scrollView);
		if (found) return found;
	}
	return undefined;
}

export class Viewport {
	readonly #tui: AltScreen;

	private constructor(tui: AltScreen) {
		this.#tui = tui;
	}

	/** Undefined unless pi runs with `tuiMode: "fullscreen"` and the internals match. */
	static of(tui: TUI): Viewport | undefined {
		return isAltScreen(tui) ? new Viewport(tui) : undefined;
	}

	get #scrollView(): ScrollView {
		return this.#tui.getPrimaryScrollView();
	}

	/** Transcript rows as rendered last frame, with styling escapes. */
	lines(): readonly string[] {
		const layout = this.#tui.currentLayout;
		if (!layout) return [];
		return findScrollBox(layout.root, this.#scrollView)?.scrollContentLines ?? [];
	}

	get top(): number {
		return this.#scrollView.scrollTop;
	}

	get height(): number {
		return this.#scrollView.viewportHeight;
	}

	get following(): boolean {
		return this.#scrollView.isFollowingEnd;
	}

	scrollTo(top: number, follow: boolean): void {
		this.#scrollView.scrollTo(top, { disableFollow: !follow });
	}

	/** Highlight cells [startCol, endCol) from startRow to endRow, in content coordinates. */
	select(startRow: number, startCol: number, endRow: number, endCol: number): void {
		const scrollView = this.#scrollView;
		this.#tui.selectionAnchor = { row: startRow, col: startCol, scrollView };
		this.#tui.selectionFocus = { row: endRow, col: endCol, scrollView, boundary: true };
		this.#tui.requestRender();
	}

	clearSelection(): void {
		this.#tui.resetTextSelection();
		this.#tui.requestRender();
	}

	/** Copies the current selection; the text is taken before this returns. */
	copySelection(): Promise<boolean> {
		return this.#tui.copyActiveSelectionToClipboard();
	}

	focused(): Component | null {
		return this.#tui.getFocusedComponent();
	}

	hasOverlay(): boolean {
		return this.#tui.hasOverlay();
	}

	requestRender(): void {
		this.#tui.requestRender();
	}

	/** Lay out now, so top and height reflect a change such as the mode line appearing. */
	renderNow(): void {
		this.#tui.renderNow();
	}
}
