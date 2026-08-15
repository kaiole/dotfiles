local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local c = ls.choice_node
local t = ls.text_node
local f = ls.function_node
local d = ls.dynamic_node
local sn = ls.snippet_node
local r = ls.restore_node

local function currentDate()
	return os.date("%m-%d-%Y")
end

return {
	s("min", {
		t("$"),
		i(1),
		t("$"),
		i(0),
	}),

	s("mat", {
		t({ "$$", "" }),
		i(1),
		t({ "", "$$" }),
		i(0),
	}),

	s("ex", {
		t("**Example"),
		i(1),
		t({ ":**", "", "" }),
		i(0),
	}),

	s("check", {
		t("- [ ] **"),
		i(1),
		t("**"),
	}),

	s("hd", {
		c(1, {
      sn(nil, {
        t("## **"),
        r(1, "heading", i(1)),
        t("**"),
      }),
			sn(nil, {
				t("### **"),
				r(1, "heading", i(1)),
				t("**"),
			}),
			sn(nil, {
				t("#### **"),
				r(1, "heading", i(1)),
				t("**"),
			}),
		}),
	}),

	s("frontmatter", {
		t({ "---", "# " }),
		c(1, {
			t("note"),
      t("leetcode"),
		}),
		t({ "", "" }),
		d(2, function(args)
			local mode = args[1][1] or "leetcode"

			if mode == "leetcode" then
				return sn(nil, {
					t('pattern: "[['),
					i(1),
					t({ ']]"', 'problem: "[' }),
					i(2, "#"),
					t(". "),
					i(3, "name"),
					t("]("),
					i(7, "link"),
					t({ ')"', "confidence: " }),
					c(4, {
						t("Amazing"),
						t("Good"),
						t("Mid"),
						t("Bad"),
					}),
					t({ "", "tags: [" }),
					c(5, {
						t("easy"),
						t("medium"),
						t("hard"),
					}),
					t(", leetcode, "),
					i(6),
					t({ "]", "date: " }),
					f(currentDate, {}),
					t({ "", "---", "", "" }),
					t({ "# Problem & Constraints", "", "> desc", "", "" }),
					t({ "**Constraints:**", "", "- ", "", "---", "", "" }),
					t({ "# Optimal", "", "" }),
					t({ "---", "", "" }),
					t({ "# Sub-optimal", "", "" }),
				})
			else
				return sn(nil, {
					t("tags: ["),
					i(1),
					t({ "]", "date: " }),
					f(currentDate, {}),
					t({ "", "---", "" }),
				})
			end
		end, { 1 }),
	}),

	-- leetcode solution
	s("sol", {
		t("## "),
		i(1, "name"),
		t({ "", "", "> " }),
		i(2),
		t({ "", "", "```cpp", "" }),
		i(3, "# TODO"),
		t({ "", "```", "", "**Complexity:**", "", "" }),
		t("- Time: "),
		i(4),
		t({ "", "- Space: " }),
		i(5),
		t({ "", "" }),
		i(0),
	}),
}
