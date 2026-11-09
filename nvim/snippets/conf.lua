local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node

return {
	s("ofmt", {
		t({
			"profile = default",
			"version = 0.29.0",
			"break-cases = all",
			"let-binding-spacing = double-semicolon",
		}),
	}),
}
