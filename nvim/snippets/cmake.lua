local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local t = ls.text_node
local c = ls.choice_node
local d = ls.dynamic_node
local sn = ls.snippet_node

local function standardBlock(language)
	if language == "C" then
		return sn(nil, {
			t("set(CMAKE_C_STANDARD "),
			c(1, { t("17"), t("23"), t("11"), t("99") }),
			t({
				")",
				"set(CMAKE_C_STANDARD_REQUIRED ON)",
				"set(CMAKE_C_EXTENSIONS OFF)",
				"set(CMAKE_EXPORT_COMPILE_COMMANDS ON)",
			}),
		})
	end

	return sn(nil, {
		t("set(CMAKE_CXX_STANDARD "),
		c(1, { t("23"), t("20"), t("17") }),
		t({
			")",
			"set(CMAKE_CXX_STANDARD_REQUIRED ON)",
			"set(CMAKE_CXX_EXTENSIONS OFF)",
			"set(CMAKE_EXPORT_COMPILE_COMMANDS ON)",
		}),
	})
end

return {
	-- Minimal top-level project preamble.
	s("cm", {
		t("cmake_minimum_required(VERSION "),
		i(1, "3.20"),
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

	-- Conventional CTest integration.
	s("cmtest", {
		t({
			"include(CTest)",
			"",
			"if(BUILD_TESTING)",
			"  add_subdirectory(tests)",
			"endif()",
			"",
		}),
		i(0),
	}),

	-- Acquire GoogleTest with FetchContent.
	s("cmgt", {
		t({
			"include(FetchContent)",
			"",
			"FetchContent_Declare(",
			"  googletest",
			"  GIT_REPOSITORY https://github.com/google/googletest.git",
			"  GIT_TAG ",
		}),
		i(1, "v1.15.2"),
		t({
			")",
			"",
			"if(MSVC)",
			'  set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)',
			"endif()",
			"",
			"FetchContent_MakeAvailable(googletest)",
			"",
		}),
		i(0),
	}),

	-- Register one GoogleTest executable with CTest.
	s("cmgtd", {
		t({ "include(GoogleTest)", "gtest_discover_tests(" }),
		i(1, "test_target"),
		t({ ")", "" }),
		i(0),
	}),

	-- Acquire Google Benchmark with FetchContent.
	s("cmgb", {
		t({
			"include(FetchContent)",
			"",
			"FetchContent_Declare(",
			"  googlebenchmark",
			"  GIT_REPOSITORY https://github.com/google/benchmark.git",
			"  GIT_TAG ",
		}),
		i(1, "v1.9.1"),
		t({
			")",
			"",
			"set(BENCHMARK_ENABLE_TESTING OFF)",
			"FetchContent_MakeAvailable(googlebenchmark)",
			"",
		}),
		i(0),
	}),
}
