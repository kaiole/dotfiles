-- Project files (presets, tidy, format) come from :Cpp; these are the CMake
-- fragments written by hand. Defaults that depend on where the snippet expands
-- (target name, project namespace) are computed from the buffer's path.
local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local t = ls.text_node
local c = ls.choice_node
local d = ls.dynamic_node
local f = ls.function_node
local sn = ls.snippet_node

-- compile_commands.json is per-machine tooling, so it is set in the presets
-- (cmpresets), not here.
local function standardBlock(language)
	if language == "C" then
		return sn(nil, {
			t("set(CMAKE_C_STANDARD "),
			c(1, { t("17"), t("23"), t("11"), t("99") }),
			t({
				")",
				"set(CMAKE_C_STANDARD_REQUIRED ON)",
				"set(CMAKE_C_EXTENSIONS OFF)",
			}),
		})
	end

	return sn(nil, {
		t("set(CMAKE_CXX_STANDARD "),
		c(1, { t("23"), t("17"), t("20") }),
		t({
			")",
			"set(CMAKE_CXX_STANDARD_REQUIRED ON)",
			"set(CMAKE_CXX_EXTENSIONS OFF)",
		}),
	})
end

local function copy(args)
	return args[1][1]
end

local cmake = require("config.cmake")

local function here()
	return vim.fn.expand("%:p:h")
end

-- libs/foo/CMakeLists.txt -> foo
local function target_name()
	return vim.fs.basename(here())
end

-- libs/foo/tests/CMakeLists.txt -> foo
local function parent_target()
	return vim.fs.basename(vim.fs.dirname(here()))
end

local function namespace()
	return cmake.project_name(here())
end

-- Editable field whose default is computed when the snippet expands.
local function default(index, text)
	return d(index, function()
		return sn(nil, i(1, text()))
	end)
end

-- target_link_libraries(<target> PRIVATE <lib> <warnings> <last>) in the
-- layout cmake-format picks at 80 columns, recomputed as the fields change:
-- one line; else wrapped, hanging under <lib>; else broken after the paren.
-- Returns the text before <target> and the text after <warnings>.
local function link_layout(args, last)
	local head = "target_link_libraries(" .. args[1][1] .. " PRIVATE "
	local first = head .. args[2][1] .. " " .. args[3][1]
	if #first + #last + 2 <= 80 then
		return "", " " .. last .. ")"
	elseif #first <= 80 then
		return "", { "", string.rep(" ", #head) .. last .. ")" }
	end
	return { "", "  " }, { "", string.rep(" ", #"  " + #args[1][1] + #" PRIVATE ") .. last .. ")" }
end

-- <lib>/tests or <lib>/bench executable: field 1 is the target, 3 and 4 the
-- libraries before `last`. `rest` follows the target_link_libraries call.
local function executable(target_suffix, source_suffix, last, rest)
	local nodes = {
		t("add_executable("),
		default(1, function()
			return parent_target() .. target_suffix
		end),
		t(" "),
		default(2, function()
			return parent_target() .. source_suffix
		end),
		t({ ")", "target_link_libraries(" }),
		f(function(args)
			return (link_layout(args, last))
		end, { 1, 3, 4 }),
		f(copy, { 1 }),
		t(" PRIVATE "),
		default(3, function()
			return namespace() .. "::" .. parent_target()
		end),
		t(" "),
		default(4, function()
			return namespace() .. "::warnings"
		end),
		f(function(args)
			return select(2, link_layout(args, last))
		end, { 1, 3, 4 }),
	}
	vim.list_extend(nodes, rest)
	nodes[#nodes + 1] = i(0)
	return nodes
end

-- <lib>/CMakeLists.txt: cmlib (STATIC) and cmlibh (header-only), also expanded
-- by :CppLib and :CppLib!. A header-only library compiles nothing, so it
-- doesn't link warnings; its tests do. The tests/ guard matches the top level,
-- which only includes GoogleTest under BUILD_TESTING.
local function library(kind)
	local static = kind == "STATIC"
	local ns = static and 3 or 2
	local nodes = { t("add_library("), default(1, target_name), t(" " .. kind) }
	if static then
		vim.list_extend(nodes, {
			t(" "),
			d(2, function(args)
				return sn(nil, i(1, "src/" .. args[1][1] .. ".cpp"))
			end, { 1 }),
		})
	end
	vim.list_extend(nodes, {
		t({ ")", "add_library(" }),
		default(ns, namespace),
		t("::"),
		f(copy, { 1 }),
		t(" ALIAS "),
		f(copy, { 1 }),
		t({ ")", "", "target_include_directories(" }),
		f(copy, { 1 }),
		t((static and " PUBLIC" or " INTERFACE") .. " include)"),
	})
	if static then
		nodes[#nodes + 1] = f(function(args)
			return { "", "target_link_libraries(" .. args[1][1] .. " PRIVATE " .. args[2][1] .. "::warnings)" }
		end, { 1, ns })
	end
	vim.list_extend(nodes, {
		t({ "", "", "if(BUILD_TESTING)", "  add_subdirectory(tests)", "endif()" }),
		i(0),
	})
	return s({
		trig = static and "cmlib" or "cmlibh",
		dscr = static and "Static library: alias, include dir, warnings, tests"
			or "Header-only library: alias, include dir, tests",
	}, nodes)
end

return {
	-- Top-level preamble with what every project has: warnings (:Cpp creates
	-- cmake/warnings.cmake; fill it with cmwarn) and testing. include(CTest)
	-- defines BUILD_TESTING and enables ctest for the whole tree, so it must
	-- precede the add_subdirectory calls whose tests/ guards read it. Benchmarks
	-- are per project: add include(cmake/gbench.cmake) (cmgb) when needed.
	s("cm", {
		t("cmake_minimum_required(VERSION "),
		i(1, "4.3"),
		t({ ")", "project(", "  " }),
		i(2, "name"),
		t({ "", "  VERSION " }),
		i(3, "0.0.0"),
		t({ "", '  DESCRIPTION "' }),
		i(4, "description"),
		t({ '"', "  LANGUAGES " }),
		c(5, { t("CXX"), t("C") }),
		t({ ")", "", "" }),
		d(6, function(args)
			return standardBlock(args[1][1])
		end, { 5 }),
		t({
			"",
			"",
			"include(cmake/warnings.cmake)",
			"include(CTest)",
			"",
			"if(BUILD_TESTING)",
			"  include(cmake/gtest.cmake)",
			"endif()",
			"",
			"",
		}),
		i(0),
	}),

	-- cmake/warnings.cmake: warnings as an INTERFACE target. Link it PRIVATE
	-- from every target that compiles your sources (tests, apps, compiled libs)
	-- so the flags never reach consumers or third-party code. Warnings-as-errors
	-- comes from the presets (CMAKE_COMPILE_WARNING_AS_ERROR).
	s({ trig = "cmwarn", dscr = "warnings INTERFACE target (link PRIVATE)" }, {
		t({ "add_library(warnings INTERFACE)", "add_library(" }),
		i(0, "project"),
		t({
			"::warnings ALIAS warnings)",
			"",
			"target_compile_options(",
			"  warnings",
			"  INTERFACE -Wall",
			"            -Wextra",
			"            -Wpedantic",
			"            -Wshadow",
			"            -Wconversion",
			"            -Wsign-conversion",
			"            -Wold-style-cast",
			"            -Wnon-virtual-dtor",
			"            -Woverloaded-virtual)",
		}),
	}),

	library("STATIC"),
	library("INTERFACE"),

	s({ trig = "cmfetch", dscr = "Dependency: system first, else pinned download" }, {
		t({ "include(FetchContent)", "", "FetchContent_Declare(", "  " }),
		i(1, "PackageName"),
		t({ "", "  GIT_REPOSITORY " }),
		i(2, "https://github.com/owner/repo.git"),
		t({ "", "  GIT_TAG " }),
		i(3, "v1.2.3"),
		t({ "", "  SYSTEM FIND_PACKAGE_ARGS CONFIG)", "FetchContent_MakeAvailable(" }),
		f(copy, { 1 }),
		t(")"),
		i(0),
	}),

	-- cmake/gtest.cmake, included from the top level (cm) inside
	-- if(BUILD_TESTING) after include(CTest). Uses the system GoogleTest when
	-- present, otherwise downloads the pinned release (pin = Arch's version so
	-- both paths match). -DFETCHCONTENT_TRY_FIND_PACKAGE_MODE=NEVER forces the
	-- download. SYSTEM keeps its headers out of warnings and clang-tidy.
	s({ trig = "cmgt", dscr = "GoogleTest dependency: system first, else pinned download" }, {
		t({
			"include(FetchContent)",
			"",
			"FetchContent_Declare(",
			"  googletest",
			"  URL https://github.com/google/googletest/archive/refs/tags/v",
		}),
		i(1, "1.18.0"),
		t({
			".tar.gz",
			"      SYSTEM FIND_PACKAGE_ARGS NAMES GTest)",
			"FetchContent_MakeAvailable(googletest)",
			"",
			"include(GoogleTest)",
		}),
		i(0),
	}),

	-- <module>/tests/CMakeLists.txt. PRE_TEST lists the tests at ctest time, so
	-- the test preset's ASAN_OPTIONS/UBSAN_OPTIONS apply and a crash is a test
	-- failure, not a build failure.
	s(
		{ trig = "cmgtx", dscr = "GoogleTest executable (gtest_main, ctest discovery)" },
		executable("_tests", "_test.cpp", "GTest::gtest_main", {
			t({ "", "gtest_discover_tests(" }),
			f(copy, { 1 }),
			t(" DISCOVERY_MODE PRE_TEST)"),
		})
	),

	-- cmake/gbench.cmake, included from the top level (not behind
	-- BUILD_TESTING). Same system-first pattern as cmgt. The two options only
	-- matter for the download: they skip benchmark's own tests, which would
	-- otherwise need GoogleTest. Measure only in release presets.
	s({ trig = "cmgb", dscr = "Google Benchmark dependency: system first, else pinned download" }, {
		t({
			"include(FetchContent)",
			"",
			"set(BENCHMARK_ENABLE_TESTING",
			"    OFF",
			'    CACHE BOOL "" FORCE)',
			"set(BENCHMARK_ENABLE_INSTALL",
			"    OFF",
			'    CACHE BOOL "" FORCE)',
			"",
			"FetchContent_Declare(",
			"  benchmark",
			"  URL https://github.com/google/benchmark/archive/refs/tags/v",
		}),
		i(1, "1.9.5"),
		t({
			".tar.gz",
			"      SYSTEM FIND_PACKAGE_ARGS CONFIG)",
			"FetchContent_MakeAvailable(benchmark)",
		}),
		i(0),
	}),

	-- <module>/bench/CMakeLists.txt.
	s(
		{ trig = "cmgbx", dscr = "Google Benchmark executable (benchmark_main)" },
		executable("_bench", "_bench.cpp", "benchmark::benchmark_main", {})
	),
}
