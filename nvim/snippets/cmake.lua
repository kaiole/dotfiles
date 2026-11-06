-- :Cpp writes the static project files (presets, tidy, format, warnings,
-- gtest, install) and expands cm; :CppLib expands cmlib/cmlibh; :CppSolo
-- writes both sets of files and expands cmsolo/cmsoloh. The rest are
-- fragments written by hand. Defaults that depend on where the snippet expands
-- (target name, project namespace) are computed from the buffer's path.
--
-- Names: directories may be kebab-case; C++ and CMake names never are. The
-- conversion happens once, in each name's default (project() from the
-- project directory, a library from its directory); later snippets read
-- names back from the CMake files rather than from paths.
--
-- Consumer rules every snippet follows: a target's real name is
-- <project>_<name> (just <project> when the two match) so two projects can
-- share a build, consumers only see the <project>::<name> alias, and nothing here (tests, warnings, -Werror,
-- clang-tidy) reaches a project that embeds or installs this one.
--
-- Text is written the way gw's formatter (cmake-format) leaves it, so gw is a
-- no-op; tests/snippet_format.lua checks every snippet.
local ls = require("luasnip")
local events = require("luasnip.util.events")
local i = ls.insert_node
local t = ls.text_node
local c = ls.choice_node
local d = ls.dynamic_node
local f = ls.function_node
local sn = ls.snippet_node

local function copy(args)
	return args[1][1]
end

local cmake = require("config.cmake")

local function here()
	return vim.fn.expand("%:p:h")
end

-- libs/order-book/CMakeLists.txt -> order_book
local function target_name()
	return cmake.identifier(vim.fs.basename(here()))
end

local function namespace()
	return cmake.project_name(here())
end

-- The library a tests/ or bench/ directory belongs to: the alias in the
-- parent's saved CMakeLists.txt (so the directory's name doesn't matter),
-- else <project>::<parent directory>.
local function tested_library()
	local parent = vim.fs.dirname(here())
	return cmake.library(parent) or namespace() .. "::" .. cmake.identifier(vim.fs.basename(parent))
end

local function tested_name()
	return tested_library():match("::(.*)")
end

-- Where a line wraps depends on the names typed in, so a snippet can't be
-- written pre-formatted. Each one formats its own lines once its last field
-- is left, and is unlinked first: reflowed text would leave its fields
-- pointing at the wrong spans.
local function format_when_done(snippet)
	local buf = vim.api.nvim_get_current_buf()
	local from, to = snippet.mark:pos_begin_end_raw()
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then
			return
		end
		if ls.get_active_snip() == snippet then
			ls.unlink_current()
		end
		local ok, conform = pcall(require, "conform")
		if ok then
			conform.format({
				bufnr = buf,
				async = false,
				quiet = true,
				range = { start = { from[1] + 1, 0 }, ["end"] = { to[1] + 1, 0 } },
			})
		end
	end)
end

local function s(context, nodes)
	return ls.snippet(context, nodes, { callbacks = { [-1] = { [events.leave] = format_when_done } } })
end

-- .../tags/v1.2.3.tar.gz -> 1.2.3: the last dotted number in a release URL.
local function url_version(url)
	local version = ""
	for match in url:gmatch("%d+%.%d+[%.%d]*") do
		version = match
	end
	return (version:gsub("%.+$", ""))
end

-- Editable field whose default is computed when the snippet expands.
local function default(index, text)
	return d(index, function()
		return sn(nil, i(1, text()))
	end)
end

-- <lib>/tests or <lib>/bench executable: field 1 is the target, 3 and 4 the
-- libraries before `last`. `rest` follows the target_link_libraries call.
local function executable(target_suffix, source_suffix, last, rest)
	local nodes = {
		t("add_executable("),
		default(1, function()
			return tested_name() .. target_suffix
		end),
		t(" "),
		default(2, function()
			return tested_name() .. source_suffix
		end),
		t({ ")", "target_link_libraries(" }),
		f(copy, { 1 }),
		t(" PRIVATE "),
		default(3, tested_library),
		t(" "),
		default(4, function()
			return namespace() .. "::warnings"
		end),
		t(" " .. last .. ")"),
	}
	vim.list_extend(nodes, rest)
	nodes[#nodes + 1] = i(0)
	return nodes
end

-- <lib>/CMakeLists.txt: cmlib (STATIC) and cmlibh (header-only), also expanded
-- by :CppLib and :CppLib!, which create the listed source and header.
-- - The header set gives the include directory for the build and the install,
--   installs the headers, and is what the presets' header verification
--   compiles one by one; list every public header in it.
-- - cxx_std_N makes consumers compile with at least this project's standard.
-- - Warnings are a build-only private link, so the install export doesn't
--   need them. A header-only library compiles nothing; its tests link them.
-- - install.cmake (once per project) adds the export and package files the
--   first time a library includes it, so a project without libraries has none.
-- - Tests build only when this is the top-level project.
local function real(args)
	local name, project = args[1][1], args[2][1]
	return name == project and name or project .. "_" .. name
end

-- What follows "add_library(<real name>". `name`, `ns` and `src` are the
-- fields holding the library name, the namespace and a static library's
-- source; header(name, ns) is the public header's path under include/.
local function library_nodes(kind, name, ns, src, header)
	local static = kind == "STATIC"
	local scope = static and " PUBLIC" or " INTERFACE"
	local nodes = { t(" " .. kind) }
	if static then
		vim.list_extend(nodes, {
			t(" "),
			d(src, function(args)
				return sn(nil, i(1, "src/" .. args[1][1] .. ".cpp"))
			end, { name }),
		})
	end
	vim.list_extend(nodes, {
		t({ ")", "add_library(" }),
		f(function(args)
			return args[2][1] .. "::" .. args[1][1] .. " ALIAS " .. real(args)
		end, { name, ns }),
		t({ ")", "set_target_properties(" }),
		f(function(args)
			return real(args) .. " PROPERTIES EXPORT_NAME " .. args[1][1]
		end, { name, ns }),
		t({ ")", "", "target_sources(" }),
		f(function(args)
			return {
				real(args) .. scope .. " FILE_SET HEADERS BASE_DIRS include FILES",
				"  include/" .. header(args[1][1], args[2][1]) .. ")",
			}
		end, { name, ns }),
		t({ "", "target_compile_features(" }),
		f(real, { name, ns }),
		t(scope .. " cxx_std_${CMAKE_CXX_STANDARD})"),
	})
	if static then
		nodes[#nodes + 1] = f(function(args)
			return {
				"",
				"target_link_libraries(" .. real(args) .. " PRIVATE $<BUILD_INTERFACE:" .. args[2][1] .. "::warnings>)",
			}
		end, { name, ns })
	end
	vim.list_extend(nodes, {
		t({ "", "", "include(${PROJECT_SOURCE_DIR}/cmake/install.cmake)", "install(", "  TARGETS " }),
		f(real, { name, ns }),
		t({ "", "  EXPORT " }),
		f(function(args)
			return args[2][1] .. "-targets"
		end, { name, ns }),
		t({
			"",
			"  FILE_SET HEADERS)",
			"",
			"if(PROJECT_IS_TOP_LEVEL AND BUILD_TESTING)",
			"  add_subdirectory(tests)",
			"endif()",
		}),
		i(0),
	})
	return nodes
end

local function library(kind)
	local static = kind == "STATIC"
	local ns = static and 3 or 2
	local nodes = { t("add_library("), default(ns, namespace), t("_"), default(1, target_name) }
	vim.list_extend(
		nodes,
		library_nodes(kind, 1, ns, 2, function(name, project)
			return project .. "/" .. name .. "/" .. name .. ".hpp"
		end)
	)
	return s({
		trig = static and "cmlib" or "cmlibh",
		dscr = static and "Static library: alias, header set, standard, warnings, install, tests"
			or "Header-only library: alias, header set, standard, install, tests",
	}, nodes)
end

-- A pinned third-party dependency: the system package first, else the
-- download, built without this project's -Werror (a new compiler warning in
-- their code must not break the build) or clang-tidy. block() scopes the
-- variables to the dependency; plain set() overrides its option() defaults.
-- cmake-format predates block() and doesn't indent its body, so neither do
-- these.
local function dependency(name, url, hash, find_args, settings, after)
	local lines = {
		"include(FetchContent)",
		"",
		"FetchContent_Declare(",
		"  " .. name,
		"  URL " .. url,
		"  URL_HASH",
		"    SHA256=" .. hash,
		"  SYSTEM FIND_PACKAGE_ARGS " .. find_args .. ")",
		"block()",
		"set(CMAKE_COMPILE_WARNING_AS_ERROR OFF)",
		'set(CMAKE_CXX_CLANG_TIDY "")',
	}
	for _, setting in ipairs(settings) do
		lines[#lines + 1] = "set(" .. setting .. ")"
	end
	vim.list_extend(lines, { "FetchContent_MakeAvailable(" .. name .. ")", "endblock()" })
	return t(vim.list_extend(lines, after or {}))
end

-- Top-level CMakeLists.txt, expanded by :Cpp. The project name defaults to
-- the directory. The 3.25 floor is what these snippets use (presets v6,
-- block(), FetchContent SYSTEM); the upper version is the newest tested, whose
-- policies apply. CTest is only included at the top level: BUILD_TESTING is a
-- global cache variable, and a consumer turning on its own tests must not
-- build these. Benchmarks are per project: add
-- include(cmake/gbench.cmake) (cmgb) inside if(PROJECT_IS_TOP_LEVEL).
local function project_nodes()
	return {
		t("cmake_minimum_required(VERSION "),
		i(1, "3.25...4.4"),
		t({ ")", "project(", "  " }),
		default(2, function()
			return target_name()
		end),
		t({ "", "  VERSION " }),
		i(3, "0.1.0"),
		t({ "", '  DESCRIPTION "' }),
		i(4, "description"),
		t({ '"', "  LANGUAGES CXX)", "", "set(CMAKE_CXX_STANDARD " }),
		c(5, { t("23"), t("17"), t("20") }),
		t({
			")",
			"set(CMAKE_CXX_STANDARD_REQUIRED ON)",
			"set(CMAKE_CXX_EXTENSIONS OFF)",
			"",
			"include(cmake/warnings.cmake)",
			"",
			"if(PROJECT_IS_TOP_LEVEL)",
			"  include(CTest)",
			"  if(BUILD_TESTING)",
			"    include(cmake/gtest.cmake)",
			"  endif()",
			"endif()",
		}),
	}
end

local cm = s("cm", vim.list_extend(project_nodes(), { i(0) }))

-- Top-level CMakeLists.txt of a project that is one library at its root,
-- expanded by :CppSolo (! for cmsoloh): cm, then cmlib/cmlibh named after the
-- project, whose header is include/<project>/<project>.hpp. The file is
-- unsaved, so the name is copied from the project() field.
local function solo(kind)
	local static = kind == "STATIC"
	local nodes = project_nodes()
	vim.list_extend(nodes, { t({ "", "", "add_library(" }), f(real, { 2, 2 }) })
	vim.list_extend(
		nodes,
		library_nodes(kind, 2, 2, 6, function(name)
			return name .. "/" .. name .. ".hpp"
		end)
	)
	return s({
		trig = static and "cmsolo" or "cmsoloh",
		dscr = static and "Project that is one static library at the root (cm + cmlib)"
			or "Project that is one header-only library at the root (cm + cmlibh)",
	}, nodes)
end

return {
	cm,

	-- cmake/warnings.cmake, written by :Cpp: warnings as an INTERFACE target.
	-- Link it PRIVATE from every target that compiles your sources (tests,
	-- apps, compiled libs; $<BUILD_INTERFACE:...> on installed ones) so the
	-- flags never reach consumers or third-party code. Warnings-as-errors comes
	-- from the presets (CMAKE_COMPILE_WARNING_AS_ERROR). Clang-only warnings
	-- live in .clang-tidy's ExtraArgs and are enforced by the lint preset.
	s({ trig = "cmwarn", dscr = "warnings INTERFACE target (link PRIVATE)" }, {
		t({
			"add_library(${PROJECT_NAME}_warnings INTERFACE)",
			"add_library(${PROJECT_NAME}::warnings ALIAS ${PROJECT_NAME}_warnings)",
			"",
			"target_compile_options(",
			"  ${PROJECT_NAME}_warnings",
			"  INTERFACE -Wall",
			"            -Wextra",
			"            -Wpedantic",
			"            -Wshadow",
			"            -Wconversion",
			"            -Wsign-conversion",
			"            -Wold-style-cast",
			"            -Wnon-virtual-dtor",
			"            -Woverloaded-virtual",
			"            -Wnull-dereference",
			"            -Wdouble-promotion",
			"            -Wfloat-equal",
			"            -Wimplicit-fallthrough",
			"            -Wvla)",
		}),
	}),

	-- cmake/install.cmake, written by :Cpp and included by each library
	-- (cmlib) before its install(TARGETS ... EXPORT <project>-targets). Lets a
	-- consumer find_package(<project>) after cmake --install from a release
	-- build (a sanitizer build needs the sanitizer runtime to link).
	s({ trig = "cminstall", dscr = "Install export and package files, once per project" }, {
		t({
			"include_guard(GLOBAL)",
			"include(GNUInstallDirs)",
			"include(CMakePackageConfigHelpers)",
			"",
			"block()",
			"set(destination ${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME})",
			"install(",
			"  EXPORT ${PROJECT_NAME}-targets",
			"  NAMESPACE ${PROJECT_NAME}::",
			"  DESTINATION ${destination})",
			"configure_package_config_file(",
			"  ${PROJECT_SOURCE_DIR}/cmake/config.cmake.in",
			"  ${PROJECT_BINARY_DIR}/${PROJECT_NAME}-config.cmake",
			"  INSTALL_DESTINATION ${destination})",
			"write_basic_package_version_file(",
			"  ${PROJECT_BINARY_DIR}/${PROJECT_NAME}-config-version.cmake",
			"  COMPATIBILITY SameMajorVersion)",
			"install(FILES ${PROJECT_BINARY_DIR}/${PROJECT_NAME}-config.cmake",
			"              ${PROJECT_BINARY_DIR}/${PROJECT_NAME}-config-version.cmake",
			"        DESTINATION ${destination})",
			"endblock()",
		}),
	}),

	-- cmake/config.cmake.in, written by :Cpp: the installed package's entry
	-- point. A library whose PUBLIC link includes an external package needs a
	-- matching find_dependency here, or consumers get a missing-target error.
	s({ trig = "cmconfig", dscr = "Package config template for install.cmake" }, {
		t({
			"@PACKAGE_INIT@",
			"",
			"include(CMakeFindDependencyMacro)",
			"# find_dependency(<Package> <version>) for each PUBLIC external dependency.",
			"",
			'include("${CMAKE_CURRENT_LIST_DIR}/@PROJECT_NAME@-targets.cmake")',
			"check_required_components(@PROJECT_NAME@)",
		}),
	}),

	library("STATIC"),
	library("INTERFACE"),
	solo("STATIC"),
	solo("INTERFACE"),

	-- System package first, else the pinned download. URL_HASH makes the
	-- download tamper- and drift-proof; get it with
	-- curl -sL <url> | sha256sum.
	-- The version (default: the URL's) is the oldest system package accepted;
	-- the package's version file decides which newer ones are compatible, and
	-- a range (1.2...<2) caps them. A PUBLIC dependency needs the same
	-- constraint in its find_dependency (cmconfig).
	s({ trig = "cmfetch", dscr = "Dependency: system first, else pinned, hashed download" }, {
		t({ "include(FetchContent)", "", "FetchContent_Declare(", "  " }),
		i(1, "PackageName"),
		t({ "", "  URL " }),
		i(2, "https://github.com/owner/repo/archive/refs/tags/v1.2.3.tar.gz"),
		t({ "", "  URL_HASH SHA256=" }),
		i(3, "hash"),
		t({ "", "  SYSTEM FIND_PACKAGE_ARGS " }),
		d(4, function(args)
			return sn(nil, i(1, url_version(args[1][1])))
		end, { 2 }),
		t({ " CONFIG)", "block()", "set(CMAKE_COMPILE_WARNING_AS_ERROR OFF)" }),
		t({ "", 'set(CMAKE_CXX_CLANG_TIDY "")', "FetchContent_MakeAvailable(" }),
		f(copy, { 1 }),
		t({ ")", "endblock()" }),
		i(0),
	}),

	-- cmake/gtest.cmake, written by :Cpp and included from the top level (cm)
	-- only when building this project's tests. Uses the system GoogleTest when
	-- present, otherwise downloads the pinned release (pin = Arch's version so
	-- both paths match; update URL and hash together).
	-- -DFETCHCONTENT_TRY_FIND_PACKAGE_MODE=NEVER forces the download. SYSTEM
	-- keeps its headers out of warnings and clang-tidy.
	s(
		{ trig = "cmgt", dscr = "GoogleTest dependency: system first, else pinned download" },
		dependency(
			"googletest",
			"https://github.com/google/googletest/archive/refs/tags/v1.18.0.tar.gz",
			"6e3191c1455468b3fc35a417fb565c1c5071aee1b7e7f85e30cf48a98d37d8b5",
			"NAMES GTest",
			{ "INSTALL_GTEST OFF" },
			{ "", "include(GoogleTest)" }
		)
	),

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

	-- cmake/gbench.cmake, included from the top level inside
	-- if(PROJECT_IS_TOP_LEVEL), not behind BUILD_TESTING. Same pattern as cmgt.
	-- The options only matter for the download: skip benchmark's own tests
	-- (which would need GoogleTest), install rules, and its own -Werror.
	-- Measure only in release presets.
	s(
		{ trig = "cmgb", dscr = "Google Benchmark dependency: system first, else pinned download" },
		dependency(
			"benchmark",
			"https://github.com/google/benchmark/archive/refs/tags/v1.10.0.tar.gz",
			"acc5c7c0fbed855c4aaa2d7c3c36fb82b0c15c28f4e151e3f679c2fc0aa404af",
			"CONFIG",
			{ "BENCHMARK_ENABLE_TESTING OFF", "BENCHMARK_ENABLE_INSTALL OFF", "BENCHMARK_ENABLE_WERROR OFF" }
		)
	),

	-- <module>/bench/CMakeLists.txt.
	s(
		{ trig = "cmgbx", dscr = "Google Benchmark executable (benchmark_main)" },
		executable("_bench", "_bench.cpp", "benchmark::benchmark_main", {})
	),
}
