-- Fragments only. Whole-project setup (presets, warnings, sanitizers, tidy)
-- comes from the cppstack scaffold: ~/personal/cppstack/scaffold.
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

return {
	-- Minimal top-level project preamble.
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
		t({ "", "" }),
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

	s({ trig = "cmfetch", dscr = "Dependency: system first, else pinned download" }, {
		t({ "include(FetchContent)", "", "FetchContent_Declare(", "  " }),
		i(1, "PackageName"),
		t({ "", "  GIT_REPOSITORY " }),
		i(2, "https://github.com/owner/repo.git"),
		t({ "", "  GIT_TAG " }),
		i(3, "v1.2.3"),
		t({ "", "  SYSTEM", "  FIND_PACKAGE_ARGS CONFIG", ")", "FetchContent_MakeAvailable(" }),
		f(copy, { 1 }),
		t({ ")", "", "" }),
		i(0),
	}),

	-- cmake/googletest.cmake, included from the top level inside
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
			"  SYSTEM",
			"  FIND_PACKAGE_ARGS NAMES GTest)",
			"FetchContent_MakeAvailable(googletest)",
			"",
			"include(GoogleTest)",
			"",
		}),
		i(0),
	}),

	-- <module>/tests/CMakeLists.txt. PRE_TEST lists the tests at ctest time, so
	-- the test preset's ASAN_OPTIONS/UBSAN_OPTIONS apply and a crash is a test
	-- failure, not a build failure.
	s({ trig = "cmgtx", dscr = "GoogleTest executable (gtest_main, ctest discovery)" }, {
		t("add_executable("),
		i(1, "name_tests"),
		t(" "),
		i(2, "name_test.cpp"),
		t({ ")", "target_link_libraries(" }),
		f(copy, { 1 }),
		t(" PRIVATE "),
		i(3, "project::lib"),
		t(" "),
		i(4, "project::warnings"),
		t({ " GTest::gtest_main)", "gtest_discover_tests(" }),
		f(copy, { 1 }),
		t({ " DISCOVERY_MODE PRE_TEST)", "" }),
		i(0),
	}),

	-- cmake/benchmark.cmake, included from the top level (not behind
	-- BUILD_TESTING). Same system-first pattern as cmgt. The two options only
	-- matter for the download: they skip benchmark's own tests, which would
	-- otherwise need GoogleTest. Measure only in release presets.
	s({ trig = "cmgb", dscr = "Google Benchmark dependency: system first, else pinned download" }, {
		t({
			"include(FetchContent)",
			"",
			'set(BENCHMARK_ENABLE_TESTING OFF CACHE BOOL "" FORCE)',
			'set(BENCHMARK_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)',
			"",
			"FetchContent_Declare(",
			"  benchmark",
			"  URL https://github.com/google/benchmark/archive/refs/tags/v",
		}),
		i(1, "1.9.5"),
		t({
			".tar.gz",
			"  SYSTEM",
			"  FIND_PACKAGE_ARGS CONFIG)",
			"FetchContent_MakeAvailable(benchmark)",
			"",
		}),
		i(0),
	}),

	-- <module>/bench/CMakeLists.txt.
	s({ trig = "cmgbx", dscr = "Google Benchmark executable (benchmark_main)" }, {
		t("add_executable("),
		i(1, "name_bench"),
		t(" "),
		i(2, "name_bench.cpp"),
		t({ ")", "target_link_libraries(" }),
		f(copy, { 1 }),
		t(" PRIVATE "),
		i(3, "project::lib"),
		t(" "),
		i(4, "project::warnings"),
		t({ " benchmark::benchmark_main)", "" }),
		i(0),
	}),
}
