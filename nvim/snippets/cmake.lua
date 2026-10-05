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

	-- Companion to cmpresets: apply only to owned, concrete C/C++ targets.
	s({
		trig = "cmopts",
		dscr = "Target-scoped sanitizer and profiling options for cmpresets",
	}, {
		t({
			"# Place after project(); call project_build_options(my_target) for each owned target.",
			'set(PROJECT_SANITIZER "none" CACHE STRING "Sanitizer: none, address-undefined, or thread")',
			"set_property(CACHE PROJECT_SANITIZER PROPERTY STRINGS none address-undefined thread)",
			'option(PROJECT_FRAME_POINTERS "Keep frame pointers for profiling" OFF)',
			"",
			'if(NOT PROJECT_SANITIZER MATCHES "^(none|address-undefined|thread)$")',
			'  message(FATAL_ERROR "Unknown PROJECT_SANITIZER: ${PROJECT_SANITIZER}")',
			"endif()",
			"",
			"function(project_build_options target)",
			'  if(PROJECT_SANITIZER STREQUAL "none" AND NOT PROJECT_FRAME_POINTERS)',
			"    return()",
			"  endif()",
			"",
			"  foreach(lang IN ITEMS C CXX)",
			"    if(CMAKE_${lang}_COMPILER_LOADED)",
			'      if(NOT CMAKE_${lang}_COMPILER_ID MATCHES "^(GNU|Clang|AppleClang)$"',
			'          OR CMAKE_${lang}_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")',
			'        message(FATAL_ERROR "Sanitizer/profiling options require GCC or Clang with a GNU-style frontend")',
			"      endif()",
			"    endif()",
			"  endforeach()",
			"",
			"  target_compile_options(${target} PRIVATE",
			'    "$<$<COMPILE_LANGUAGE:C,CXX>:-fno-omit-frame-pointer>"',
			"  )",
			"",
			'  if(NOT PROJECT_SANITIZER STREQUAL "none")',
			'    if(PROJECT_SANITIZER STREQUAL "address-undefined")',
			'      set(sanitizer_flag "-fsanitize=address,undefined")',
			"    else()",
			'      set(sanitizer_flag "-fsanitize=thread")',
			"    endif()",
			"",
			"    # Modest optimization; keep Debug assertions and symbols in sanitizer presets.",
			"    target_compile_options(${target} PRIVATE",
			'      "$<$<COMPILE_LANGUAGE:C,CXX>:-O1>"',
			'      "$<$<COMPILE_LANGUAGE:C,CXX>:${sanitizer_flag}>"',
			'      "$<$<COMPILE_LANGUAGE:C,CXX>:-fno-sanitize-recover=all>"',
			"    )",
			"    # PUBLIC carries the sanitizer runtime requirement through static libraries.",
			"    target_link_options(${target} PUBLIC ${sanitizer_flag})",
			"  endif()",
			"endfunction()",
			"",
		}),
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
