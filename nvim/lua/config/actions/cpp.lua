local M = {}

local function enclosing_type_name()
	local ok, parser = pcall(vim.treesitter.get_parser, 0, "cpp")
	if not ok then
		return
	end

	local tree = parser:parse()[1]
	if not tree then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, column = cursor[1] - 1, cursor[2]
	local node = tree:root():named_descendant_for_range(row, column, row, column)

	while node do
		if node:type() == "class_specifier" or node:type() == "struct_specifier" then
			local name = node:field("name")[1]
			if name then
				return vim.treesitter.get_node_text(name, 0)
			end
		end
		node = node:parent()
	end
end

local function modifier_choice(ls, index, starts_noexcept)
	local choices = starts_noexcept
		and { ls.text_node(" noexcept"), ls.text_node(""), ls.text_node(" = default"), ls.text_node(" = delete") }
		or { ls.text_node(""), ls.text_node(" noexcept"), ls.text_node(" = default"), ls.text_node(" = delete") }

	return ls.choice_node(index, choices)
end

function M.insert_special_members()
	local name = enclosing_type_name()
	if not name then
		vim.notify("Place the cursor inside a named C++ class or struct", vim.log.levels.WARN, {
			title = "C++ constructors",
		})
		return
	end

	local ls = require("luasnip")
	ls.snip_expand(ls.snippet("", {
		ls.text_node(name .. "()"),
		modifier_choice(ls, 1, false),
		ls.text_node({ ";", "~" .. name .. "()" }),
		modifier_choice(ls, 2, false),
		ls.text_node({ ";", "", name .. "(const " .. name .. "& other)" }),
		modifier_choice(ls, 3, false),
		ls.text_node({ ";", name .. "& operator=(const " .. name .. "& other)" }),
		modifier_choice(ls, 4, false),
		ls.text_node({ ";", name .. "(" .. name .. "&& other)" }),
		modifier_choice(ls, 5, true),
		ls.text_node({ ";", name .. "& operator=(" .. name .. "&& other)" }),
		modifier_choice(ls, 6, true),
		ls.text_node(";"),
		ls.insert_node(0),
	}))
end

return M
