local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node

return {
	-- check, written (executable) by :Cpp: every gate a change must pass. The
	-- presets (cmpresets) hold the policy; a workflow can't span configure
	-- presets, so this runs them in turn.
	s({ trig = "check", dscr = "C++ project gate: clang-format, lint, dev and tsan workflows" }, {
		t({
			"#!/bin/sh",
			"# Every gate a change must pass: formatting, clang-tidy, then the tests under",
			"# ASan/UBSan and TSan/UBSan.",
			"set -eu",
			'cd "$(dirname "$0")"',
			"",
			"find . \\( -path ./build -o -path ./.cache -o -path ./.git \\) -prune -o \\",
			"  -type f \\( -name '*.cpp' -o -name '*.hpp' \\) -print0 |",
			"  xargs -0 clang-format --dry-run --Werror",
			"",
			"for preset in lint dev tsan; do",
			'  cmake --workflow --preset "$preset"',
			"done",
		}),
	}),
}
