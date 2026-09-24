local ls = require("luasnip")
local k = require("luasnip.nodes.key_indexer").new_key

local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local c = ls.choice_node
local f = ls.function_node
local r = ls.restore_node

local function name_from(args)
	return args[1][1]
end

local function class_name()
	return f(name_from, k("class_name"))
end

local function generated_lines(build)
	return f(function(args)
		return build(args[1][1])
	end, k("class_name"))
end

local function constructor_choice()
	return c(2, {
		t(""),
		generated_lines(function(name)
			return { "", "  " .. name .. "() = default;" }
		end),
		sn(nil, {
			t({ "", "  " }),
			class_name(),
			t("("),
			r(1, "constructor_arguments", i(1)),
			t(");"),
		}),
		sn(nil, {
			t({ "", "  explicit " }),
			class_name(),
			t("("),
			r(1, "constructor_arguments", i(1)),
			t(");"),
		}),
	})
end

local function defaulted_rule_of_five(name)
	return {
		"",
		"",
		"  ~" .. name .. "() = default;",
		"  " .. name .. "(const " .. name .. "&) = default;",
		"  " .. name .. "& operator=(const " .. name .. "&) = default;",
		"  " .. name .. "(" .. name .. "&&) noexcept = default;",
		"  " .. name .. "& operator=(" .. name .. "&&) noexcept = default;",
	}
end

local function move_only(name)
	return {
		"",
		"",
		"  ~" .. name .. "() = default;",
		"  " .. name .. "(const " .. name .. "&) = delete;",
		"  " .. name .. "& operator=(const " .. name .. "&) = delete;",
		"  " .. name .. "(" .. name .. "&&) noexcept = default;",
		"  " .. name .. "& operator=(" .. name .. "&&) noexcept = default;",
	}
end

local function custom_rule_of_five(name)
	return {
		"",
		"",
		"  ~" .. name .. "();",
		"  " .. name .. "(const " .. name .. "& other);",
		"  " .. name .. "& operator=(const " .. name .. "& other);",
		"  " .. name .. "(" .. name .. "&& other) noexcept;",
		"  " .. name .. "& operator=(" .. name .. "&& other) noexcept;",
	}
end

return {
	s({
		trig = "class",
		docstring = "class ClassName { ... };",
	}, {
		t("class "),
		i(1, "class_name", { key = "class_name" }),
		t({ " {", "public:" }),
		constructor_choice(),
		c(3, {
			t(""),
			generated_lines(defaulted_rule_of_five),
			generated_lines(move_only),
			generated_lines(custom_rule_of_five),
		}),
		t({ "", "", "private:", "  " }),
		i(4),
		t({ "", "};" }),
		i(0),
	}),
}
