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
	-- Markdown snippets
	s("gamma", {
		t("\\gamma"),
	}),

	s("subseteq", {
		t("\\subseteq"),
	}),

	s("bold", {
		t("**"),
		i(1),
		t("**"),
		i(0),
	}),

	s("code", {
		t("```"),
		i(1),
		t({ "", "" }),
		i(2),
		t({ "", "```", "" }),
		i(0),
	}),

	s("cin", {
		t("`"),
		i(1),
		t("`"),
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

	-- LaTeX / MathJax snippets
	-- Add new math snippets in this section.
	s("min", {
		t("$"),
		i(1),
		t("$"),
		i(0),
	}),

	s("mat", {
		t({ "$$", "" }),
		i(1),
		t({ "", "$$", "" }),
		i(0),
	}),

	s("set", {
		t("\\{"),
		i(1),
		t("\\}"),
		i(0),
	}),

	s("setminus", {
		t("\\setminus"),
	}),

	s("emptyset", {
		t("\\emptyset"),
	}),

	s("notin", {
		t("\\notin"),
	}),

	s("in", {
		t("\\in"),
	}),

	s("neq", {
		t("\\neq"),
	}),

	s("geq", {
		t("\\geq"),
	}),

	s("leq", {
		t("\\leq"),
	}),

	s("cap", {
		t("\\cap"),
	}),

	s("cup", {
		t("\\cup"),
	}),

	s("ldots", {
		t("\\ldots"),
	}),

	s("cdots", {
		t("\\cdots"),
	}),

	s("cdot", {
		t("\\cdot"),
	}),

	s("times", {
		t("\\times"),
	}),

	s("therefore", {
		t("\\therefore"),
	}),

	s("forall", {
		t("\\forall"),
	}),

	s("quad", {
		t("\\quad"),
	}),

	s("text", {
		t("\\text{"),
		i(1),
		t("}"),
		i(0),
	}),

	s("frac", {
		t("\\frac{"),
		i(1),
		t("}{"),
		i(2),
		t("}"),
		i(0),
	}),

	s("binom", {
		t("\\binom{"),
		i(1),
		t("}{"),
		i(2),
		t("}"),
		i(0),
	}),

	s("boxed", {
		t("\\boxed{"),
		i(1),
		t("}"),
		i(0),
	}),

	s("ceil", {
		t("\\lceil "),
		i(1),
		t(" \\rceil"),
		i(0),
	}),

	s("cardinality", {
		t("\\left| "),
		i(1),
		t(" \\right|"),
		i(0),
	}),

	s("sqrt", {
		t("\\sqrt{"),
		i(1),
		t("}"),
		i(0),
	}),

	s("square", {
		t("\\square"),
	}),

	s("phantom", {
		t("\\phantom{"),
		i(1),
		t("}"),
		i(0),
	}),

	s("underbrace", {
		t("\\underbrace{"),
		i(1),
		t("}_{"),
		i(2),
		t("}"),
		i(0),
	}),

	s("overbrace", {
		t("\\overbrace{"),
		i(1),
		t("}^{"),
		i(2),
		t("}"),
		i(0),
	}),

	s("mathbb", {
		t("\\mathbb{"),
		i(1),
		t("}"),
		i(0),
	}),
}
