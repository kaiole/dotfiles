local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local c = ls.choice_node
local f = ls.function_node

-- These options are implemented by cmopts and project_build_options(target).
local profiles = {
	["asan-ubsan"] = {
		inherits = "base",
		cacheVariables = {
			CMAKE_BUILD_TYPE = "Debug",
			PROJECT_SANITIZER = "address-undefined",
		},
	},
	tsan = {
		inherits = "base",
		cacheVariables = {
			CMAKE_BUILD_TYPE = "Debug",
			PROJECT_SANITIZER = "thread",
		},
	},
	profile = {
		inherits = "release",
		cacheVariables = { PROJECT_FRAME_POINTERS = true },
	},
}

local function optional_configure(names)
	if #names == 0 then
		return t("")
	end

	local lines = { "," }
	for index, name in ipairs(names) do
		local profile = profiles[name]
		local keys = vim.tbl_keys(profile.cacheVariables)
		table.sort(keys)
		vim.list_extend(lines, {
			"    {",
			'      "name": ' .. vim.json.encode(name) .. ",",
			'      "inherits": ' .. vim.json.encode(profile.inherits) .. ",",
			'      "cacheVariables": {',
		})
		for key_index, key in ipairs(keys) do
			table.insert(
				lines,
				"        "
					.. vim.json.encode(key)
					.. ": "
					.. vim.json.encode(profile.cacheVariables[key])
					.. (key_index < #keys and "," or "")
			)
		end
		vim.list_extend(lines, { "      }", "    }" .. (index < #names and "," or "") })
	end
	return t(lines)
end

-- Read the selected configure fragment, keeping only the optional entries linked.
-- Whitespace may change with snippet indentation, so decode JSON rather than
-- matching rendered text or tracking a second, potentially divergent choice.
local function optional_entries(args, _, kind)
	local fragment = table.concat(args[1], "\n")
	if fragment:match("^%s*$") then
		return ""
	end
	local selected = vim.json.decode("[" .. fragment:gsub("^%s*,", "", 1) .. "]")
	local lines = { "," }
	for index, profile in ipairs(selected) do
		local name = vim.json.encode(profile.name)
		vim.list_extend(lines, {
			"    {",
			'      "name": ' .. name .. ",",
			'      "configurePreset": ' .. name .. (kind == "test" and "," or ""),
		})
		if kind == "test" then
			table.insert(lines, '      "inherits": "test-base"')
		end
		table.insert(lines, "    }" .. (index < #selected and "," or ""))
	end
	return lines
end

return {
	s({
		trig = "cmpresets",
		dscr = "Fixed debug/release presets; optional ASan+UBSan / concurrency / profiling (requires cmopts)",
	}, {
		t({
			"{",
			'  "version": 2,',
			'  "cmakeMinimumRequired": {',
			'    "major": 3,',
			'    "minor": 20,',
			'    "patch": 0',
			"  },",
			'  "configurePresets": [',
			"    {",
			'      "name": "base",',
			'      "hidden": true,',
			'      "generator": "Ninja",',
			'      "binaryDir": "${sourceDir}/build/${presetName}",',
			'      "cacheVariables": {',
			'        "CMAKE_EXPORT_COMPILE_COMMANDS": true,',
			'        "BUILD_TESTING": true',
			"      }",
			"    },",
			"    {",
			'      "name": "debug",',
			'      "inherits": "base",',
			'      "cacheVariables": {',
			'        "CMAKE_BUILD_TYPE": "Debug"',
			"      }",
			"    },",
			"    {",
			'      "name": "release",',
			'      "inherits": "base",',
			'      "cacheVariables": {',
			'        "CMAKE_BUILD_TYPE": "',
		}),
		c(1, { t("RelWithDebInfo"), t("Release") }),
		t({ '"', "      }", "    }" }),
		-- The cursor stays at the additions, not at the top of the whole document.
		c(2, {
			optional_configure({}),
			optional_configure({ "asan-ubsan" }),
			optional_configure({ "asan-ubsan", "tsan" }),
			optional_configure({ "profile" }),
		}),
		t({
			"",
			"  ],",
			'  "buildPresets": [',
			"    {",
			'      "name": "debug",',
			'      "configurePreset": "debug"',
			"    },",
			"    {",
			'      "name": "release",',
			'      "configurePreset": "release"',
			"    }",
		}),
		f(optional_entries, { 2 }, { user_args = { "build" } }),
		t({
			"",
			"  ],",
			'  "testPresets": [',
			"    {",
			'      "name": "test-base",',
			'      "hidden": true,',
			'      "output": {',
			'        "outputOnFailure": true',
			"      },",
			'      "execution": {',
			'        "noTestsAction": "error"',
			"      }",
			"    },",
			"    {",
			'      "name": "debug",',
			'      "configurePreset": "debug",',
			'      "inherits": "test-base"',
			"    },",
			"    {",
			'      "name": "release",',
			'      "configurePreset": "release",',
			'      "inherits": "test-base"',
			"    }",
		}),
		f(optional_entries, { 2 }, { user_args = { "test" } }),
		t({ "", "  ]", "}" }),
		i(0),
	}),
}
