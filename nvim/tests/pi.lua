-- Run from nvim/: nvim --headless -u NONE -l tests/pi.lua
-- Uses only public pi-nvim APIs and our own offline JSONL subprocess fixture.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.expand("~/personal/pi-nvim"))
vim.o.swapfile = false
vim.o.hidden = true
-- Exercise diagnostic data, not renderer/extmark redraw behavior in headless mode.
vim.diagnostic.config({ virtual_text = false, virtual_lines = false, signs = false, underline = false })

local api = vim.api
local integration = require("config.pi")
local pi = require("pi")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local peer = vim.fn.getcwd() .. "/tests/pi_peer.py"
local original_notify, original_select = vim.notify, vim.ui.select
local notices, apps, clients, tests, failures = {}, {}, {}, {}, {}
local base_win = api.nvim_get_current_win()
local directory, source_buf
vim.notify = function(message, level)
	notices[#notices + 1] = { message = tostring(message), level = level, mode = vim.fn.mode() }
end

local function eq(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		(message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
	)
end

local function has(text, part, message)
	assert(text:find(part, 1, true), (message or "missing text") .. ": " .. part .. " in " .. text)
end

local function lacks(text, part)
	assert(not text:find(part, 1, true), "unexpected text: " .. part .. " in " .. text)
end

local function wait_for(predicate, message)
	assert(vim.wait(3000, predicate, 5), "timed out: " .. message)
end

local function text(buf)
	assert(buf and api.nvim_buf_is_valid(buf), "expected valid view buffer")
	return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function draft(app)
	return table.concat(app.view:get_text(), "\n")
end

local function source(buf)
	api.nvim_set_current_win(base_win)
	api.nvim_win_set_buf(base_win, buf or source_buf)
end

local function notice(part)
	for _, entry in ipairs(notices) do
		if entry.message:find(part, 1, true) then
			return true
		end
	end
	return false
end

local function records(log, direction, kind)
	local result = {}
	if vim.fn.filereadable(log) == 0 then
		return result
	end
	for _, line in ipairs(vim.fn.readfile(log)) do
		local entry = vim.json.decode(line)
		if entry.direction == direction and (not kind or entry.record.type == kind) then
			result[#result + 1] = entry.record or entry
		end
	end
	return result
end

local function fixture(mode, extra)
	local log = directory .. "/transcript-" .. (#apps + 1) .. ".jsonl"
	local calls = 0
	local options = {
		cwd = directory,
		command = { "python3", peer },
		env = { PI_TEST_MODE = mode or "normal", PI_TEST_TRANSCRIPT = log },
		timeout_ms = 2000,
		client_factory = function(opts)
			calls = calls + 1
			opts.stop_timeout_ms, opts.exit_drain_timeout_ms = 100, 100
			opts.request_timeout_ms = extra and extra.request_timeout_ms or opts.request_timeout_ms
			local client = pi.client.new(opts)
			clients[#clients + 1] = client
			return client
		end,
	}
	options = vim.tbl_extend("force", options, extra or {})
	local app = integration.new(options)
	apps[#apps + 1] = app
	app:workspace_for_source()
	return app, log, function()
		return calls
	end, options
end

local function settled(app)
	wait_for(function()
		return app.task and app.task.done and not app.task.awaiting_ack
	end, "task settlement and acknowledgement")
end

local function test(name, callback)
	tests[#tests + 1] = { name, callback }
end

test("construction, preview, and draft are inert; frozen workspace", function()
	local app, log, calls = fixture()
	eq(calls(), 0)
	eq(app.client, nil)
	app.view:open_draft()
	app.view:set_text({ "Explain this", "without changing it" })
	source()
	app:attach_buffer()
	app:preview_prompt()
	has(text(app.view.preview_buf), "Explain this\nwithout changing it")
	has(text(app.view.preview_buf), "Attachment @1:")
	has(text(app.view.preview_buf), 'Editor snapshot: "source.lua"')
	lacks(text(app.view.preview_buf), "Workspace:")
	eq(calls(), 0)
	eq(records(log, "start"), {})
	eq(vim.fn.readfile(directory .. "/source.lua"), { "disk source", "second line" })
	eq(app:workspace_for_source(), directory)
	vim.cmd("lcd " .. vim.fn.fnameescape(root))
	eq(app:workspace_for_source(), directory, "workspace must not follow later cwd changes")
	vim.cmd("lcd " .. vim.fn.fnameescape(vim.fn.fnamemodify(peer, ":h:h")))
end)

test("session directory follows cwd at first use and PiNew, not source Git roots", function()
	local starting_cwd = vim.fn.getcwd()
	local project = directory .. "/project"
	local working = project .. "/nested"
	vim.fn.mkdir(project .. "/.git", "p")
	vim.fn.mkdir(working, "p")
	vim.fn.writefile({ "project source" }, project .. "/file.lua")
	local buf = vim.fn.bufadd(project .. "/file.lua")
	vim.fn.bufload(buf)
	source(buf)
	vim.cmd("lcd " .. vim.fn.fnameescape(working))
	local app, log = fixture("normal", { cwd = false })
	eq(app.workspace, working, "cwd must win over the source Git root")
	vim.cmd("lcd " .. vim.fn.fnameescape(directory))
	eq(app:workspace_for_source(), working, "an existing conversation must stay pinned")
	app.view:set_text({ "check directory" })
	app:send()
	settled(app)
	eq(records(log, "start")[1].cwd, working)
	source(buf)
	app.view:set_text({ "unfinished draft" })
	local ok = pcall(function()
		app:new_conversation()
	end)
	eq(ok, false, "implicit cwd changes also require an empty draft")
	eq(app.workspace, working)
	eq(draft(app), "unfinished draft")
	app:clear_draft()
	app:new_conversation()
	eq(app.workspace, directory, "PiNew must capture the current cwd again")
	eq(app.client, nil, "changing conversations is inert")
	app.view:set_text({ "check new directory" })
	app:send()
	settled(app)
	eq(records(log, "start")[2].cwd, directory)
	source()
	vim.cmd("lcd " .. vim.fn.fnameescape(starting_cwd))
end)

test("Pi views wrap at word boundaries without rewriting text", function()
	local app = fixture()
	local paragraph = string.rep("diagnostic metadata and editor text ", 8)
	app.view:open_draft()
	app.view:set_text({ paragraph })
	app.view:show_preview("Preview", paragraph)
	app.view:write_chat({ paragraph })
	app.view:open_chat()
	for _, field in ipairs({ "draft_win", "attachment_win", "preview_win", "chat_win" }) do
		local win = app.view[field]
		eq(api.nvim_get_option_value("wrap", { win = win }), true)
		eq(api.nvim_get_option_value("linebreak", { win = win }), true)
	end
	eq(draft(app), paragraph)
	eq(text(app.view.preview_buf), paragraph)
	eq(text(app.view.chat_buf), paragraph)
end)

test("outgoing messages contain question/context without repeated system instructions", function()
	local context = require("config.pi.context")
	local prefix = "User question:\nExplain this"
	eq(context.prompt("Explain this", {}), prefix)
	eq(
		context.prompt("Explain this", { { attachment_id = 7, text = "captured context" } }),
		prefix .. "\n\nAttachment @7:\ncaptured context"
	)
end)

test("attachment references stay stable across removal, clear, and refresh", function()
	local app = fixture()
	local context = require("config.pi.context")
	app:attach_buffer()
	app:attach_selection({ start = { row = 0, col = 0 }, ["end"] = { row = 0, col = 4 } })
	app:remove_attachment(1)
	eq(context.reference(app.attachments[1]), "@2")
	has(text(app.view.attachment_buf), "@2  Selection")
	lacks(text(app.view.attachment_buf), "@1")
	api.nvim_buf_set_lines(source_buf, 0, 1, false, { "next source" })
	app:refresh_attachment(1)
	eq(context.reference(app.attachments[1]), "@2", "unsent refresh must retain the reference")
	app:preview_attachment(1)
	has(text(app.view.preview_buf), "Attachment @2:")
	has(app.view._preview_title, "@2  Selection")
	app.view:set_text({ "Explain @2" })
	app:preview_prompt()
	has(text(app.view.preview_buf), "Attachment @2:")
	app:clear_draft()
	source()
	app:attach_buffer()
	eq(context.reference(app.attachments[1]), "@3", "cleared IDs must not be recycled")
end)

test("standalone reference parser avoids emails and identifier suffixes", function()
	local context = require("config.pi.context")
	eq(context.references("Explain @12, compare (@2) with `@12`. Then @1!"), { "@12", "@2", "@1" })
	eq(context.references("user@1.example foo@2 @3suffix @@4 @_5 @6_thing é@7 @8中"), {})
	eq(context.references("@0 @01 @999999999999999999999999999999"), { "@0", "@01", "@999999999999999999999999999999" })
end)

test("unknown and removed references refuse submission without losing the draft", function()
	local app, log, calls = fixture()
	app:attach_buffer()
	app:remove_attachment(1)
	app.view:set_text({ "Explain @1 and @99; @1 again" })
	app:preview_prompt()
	assert(notice("Unknown attachment references: @1, @99"))
	app:send()
	eq(calls(), 0)
	eq(app.client, nil)
	eq(draft(app), "Explain @1 and @99; @1 again")
	source()
	app:attach_buffer()
	app.view:set_text({ "Explain @01" })
	app:send()
	eq(calls(), 0, "leading zeros must not accidentally resolve another reference")
	app.view:set_text({ "Explain @2" })
	app:send()
	settled(app)
	eq(#records(log, "in", "prompt"), 1)
	has(records(log, "in", "prompt")[1].message, "Attachment @2:")
end)

test("sent references reinclude frozen context without checking current source freshness", function()
	local app, log = fixture()
	app:attach_buffer()
	app.view:set_text({ "Explain @1" })
	app:send()
	settled(app)
	has(text(app.view.chat_buf), "@1  Buffer")
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "new editor text" })
	app.view:set_text({ "Explain the original @1 again, including @1" })
	app:preview_prompt()
	local preview = text(app.view.preview_buf)
	has(preview, "Previously sent attachment @1:")
	has(preview, "disk source")
	lacks(preview, "new editor text")
	app:send()
	settled(app)
	eq(records(log, "in", "prompt")[2].message, preview)
	eq(#app.archive[2].attachments, 0)
	eq(#app.archive[2].referenced, 1)
	app:new_conversation()
	app.view:set_text({ "Explain @1" })
	app:send()
	assert(notice("Unknown attachment references: @1"))
	eq(app.client, nil, "previous-conversation references are no longer valid")
	app:clear_draft()
	source()
	app:attach_buffer()
	eq(app.attachments[1].attachment_id, 2, "PiNew must not bind an old token to new context")
end)

test("historical reference bodies count against the complete outgoing prompt size limit", function()
	local app, log, _, options = fixture()
	app:attach_buffer()
	app.view:set_text({ "Explain @1" })
	app:send()
	settled(app)
	options.max_prompt_bytes = 60
	app.view:set_text({ "Again @1" })
	app:send()
	assert(notice("Prompt exceeds"))
	eq(draft(app), "Again @1")
	eq(#records(log, "in", "prompt"), 1)
end)

test("restored sent snapshots retain unchanged IDs and receive new IDs on changed content", function()
	local app, log = fixture()
	app:attach_buffer()
	app.view:set_text({ "Explain @1" })
	app:send()
	settled(app)
	app:restore_last()
	app:refresh_attachment(1)
	eq(app.attachments[1].attachment_id, 1, "bookkeeping-only changes do not change snapshot identity")
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "new content" })
	app:refresh_attachment(1)
	eq(app.attachments[1].attachment_id, 2)
	eq(draft(app), "Explain @1", "refresh must not silently rewrite the user's question")
	assert(notice("Refreshed @1 as @2"))
	eq(app.archive[1].attachments[1].capture.lines, { "disk source", "second line" })
	app.view:set_text({ "Compare @1 and @2" })
	app:preview_prompt()
	local preview = text(app.view.preview_buf)
	has(preview, "Attachment @2:")
	has(preview, "new content")
	has(preview, "Previously sent attachment @1:")
	has(preview, "disk source")
	app:send()
	settled(app)
	eq(records(log, "in", "prompt")[2].message, preview)
end)

test("refreshing a restored disk reference notices disk changes even when its serialized path is unchanged", function()
	local app = fixture()
	app:attach_file("source.lua")
	app.view:set_text({ "Explain @1" })
	app:send()
	settled(app)
	app:restore_last()
	local before = app.attachments[1].text
	vim.fn.writefile({ "different disk contents" }, directory .. "/source.lua")
	app:refresh_attachment(1)
	eq(app.attachments[1].text, before)
	eq(app.attachments[1].attachment_id, 2)
end)

test("pending acknowledgement reserves submitted IDs when the draft attachment is refreshed", function()
	local app = fixture("slow_ack")
	app:attach_buffer()
	app.view:set_text({ "Explain @1" })
	app:send()
	wait_for(function()
		return #app.state.messages == 2 and app.task.awaiting_ack
	end, "submission before acknowledgement")
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "refreshed while pending" })
	app:refresh_attachment(1)
	eq(app.attachments[1].attachment_id, 2)
	app.view:set_text({ "Next: compare @1 with @2" })
	settled(app)
	eq(app.archive[1].attachments[1].attachment_id, 1)
	eq(app.archive[1].attachments[1].capture.lines, { "disk source", "second line" })
	eq(app.attachments[1].attachment_id, 2)
	eq(draft(app), "Next: compare @1 with @2")
end)

test("rejected attachments remain unsent and can refresh without a new ID", function()
	local app = fixture("reject")
	app:attach_buffer()
	app.view:set_text({ "Explain @1" })
	app:send()
	settled(app)
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "refresh rejected context" })
	app:refresh_attachment(1)
	eq(app.attachments[1].attachment_id, 1)
	eq(#app.archive, 0)
end)

test("diagnostic summaries distinguish locations and show readable severity and condensed messages", function()
	local app = fixture()
	local ns = api.nvim_create_namespace("pi-test-reference-labels")
	vim.diagnostic.set(ns, source_buf, {
		{ lnum = 0, col = 1, end_col = 3, message = "first error\nwith details", severity = 1 },
		{ lnum = 1, col = 0, end_col = 4, message = "unused variable", severity = 2 },
	})
	api.nvim_win_set_cursor(base_win, { 1, 1 })
	app:attach_diagnostics(true)
	api.nvim_win_set_cursor(base_win, { 2, 0 })
	app:attach_diagnostics(true)
	has(text(app.view.attachment_buf), "@1  Diagnostic")
	has(text(app.view.attachment_buf), "source.lua:1:2 · ERROR: first error with details")
	has(text(app.view.attachment_buf), "@2  Diagnostic")
	has(text(app.view.attachment_buf), "source.lua:2:1 · WARN: unused variable")
	app:attach_diagnostics(false)
	has(app.attachments[3].label, "2 diagnostics")
	app:attach_file("source.lua")
	has(app.attachments[4].label, "disk reference")
end)

test("diagnostic label excerpts are single-line and truncate without splitting Unicode", function()
	local app = fixture()
	local ns = api.nvim_create_namespace("pi-test-reference-excerpt")
	local message = "text\27\n" .. string.rep("é", 100)
	vim.diagnostic.set(ns, source_buf, { { lnum = 0, col = 0, message = message, severity = 1 } })
	app:attach_diagnostics(false)
	local item = app.attachments[1]
	has(item.label, "text " .. string.rep("é", 75) .. "…")
	lacks(item.label, string.rep("é", 76))
	lacks(item.label, "\27")
	lacks(item.label, "\n")
	has(item.text, message, "the actual diagnostic message must remain intact")
end)

test("editor context is lean while original snapshots retain freshness metadata", function()
	local app = fixture()
	vim.bo[source_buf].filetype = "lua"
	app:attach_buffer()
	local item = app.attachments[1]
	has(item.text, 'Editor snapshot: "source.lua", filetype "lua"')
	has(item.text, "full text; may differ from disk")
	has(item.text, "[0:0] | disk source")
	assert(item.capture.id and item.capture.source.changedtick and item.capture.source.format)
	for _, field in ipairs({ item.capture.id, "buffer " .. source_buf, "changedtick", "Format:", "encoding", "BOM" }) do
		lacks(item.text, field)
	end
	app:attach_selection({ start = { row = 0, col = 2 }, ["end"] = { row = 1, col = 0 } })
	local selection = app.attachments[2]
	has(selection.text, "Range [0:2, 1:0), zero-based bytes, end-exclusive.")
	has(selection.text, "[0:2] | sk source")
	lacks(selection.text, "[1:0] |")
	has(selection.label, ":1–1 · 1 lines")
	eq(selection.capture.lines, { "sk source", "" }, "formatting must not mutate the capture")
	local ns = api.nvim_create_namespace("pi-test-lean-diagnostics")
	vim.diagnostic.set(ns, source_buf, {
		{ lnum = 0, col = 2, end_lnum = 0, end_col = 4, message = "bad call", severity = 2, source = "lsp", code = 42 },
		{ lnum = 1, col = 0, message = "note", severity = 3 },
	})
	app:attach_diagnostics(false)
	local diagnostic = app.attachments[3]
	has(diagnostic.text, '[0:2, 0:4) severity=WARN source="lsp" code="42": bad call')
	has(diagnostic.text, "severity=INFO")
	has(diagnostic.text, "publication freshness unknown")
	lacks(diagnostic.text, "namespace=")
	lacks(diagnostic.text, 'source=""')
	lacks(diagnostic.text, 'code=""')
	lacks(diagnostic.text, "disk source")
	assert(diagnostic.capture.diagnostics[1].namespace)
	local context = require("config.pi.context")
	eq(context.freshness(item), "unchanged")
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "changed source" })
	eq(context.freshness(item), "changed")
end)

test("every attachment produces a command-line confirmation", function()
	local app = fixture()
	app:attach_file("source.lua")
	app:attach_buffer()
	app:attach_selection({ start = { row = 0, col = 0 }, ["end"] = { row = 0, col = 4 } })
	local ns = api.nvim_create_namespace("pi-test-notifications")
	vim.diagnostic.set(ns, source_buf, { { lnum = 0, col = 0, end_col = 4, message = "error", severity = 1 } })
	api.nvim_win_set_cursor(base_win, { 1, 0 })
	app:attach_diagnostics(false)
	app:attach_diagnostics(true)
	vim.fn.setqflist({}, " ", { title = "build", items = { { text = "failure" } } })
	app:attach_quickfix()
	eq(#app.attachments, 6)
	wait_for(function()
		return #notices == 6
	end, "all attachment confirmations")
	for i, item in ipairs(app.attachments) do
		eq(notices[i].message, "Pi: Attached " .. require("config.pi.context").label(item))
		eq(notices[i].level, vim.log.levels.INFO)
	end
end)

test("Visual mapping confirmation arrives after leaving Visual mode", function()
	local app = dofile(vim.fn.fnamemodify(peer, ":h:h") .. "/lua/plugins/pi.lua")
	apps[#apps + 1] = app
	api.nvim_win_set_cursor(base_win, { 1, 0 })
	vim.cmd("normal! v")
	api.nvim_win_set_cursor(base_win, { 1, 3 })
	local mapping = vim.fn.maparg("<leader>pv", "x", false, true)
	assert(type(mapping.callback) == "function")
	mapping.callback()
	eq(vim.fn.mode(), "n")
	eq(#app.attachments, 1)
	eq(app.attachments[1].capture.lines, { "disk" })
	wait_for(function()
		return notice("Attached @1  Selection")
	end, "Visual confirmation")
	eq(#notices, 1)
	eq(notices[1].mode, "n", "confirmation must not be erased by the subsequent Visual-mode exit")
	eq(app.client, nil)
end)

test("attachment-pane i inserts a stable reference at the preserved Unicode cursor and supports undo", function()
	local app = fixture()
	app:attach_buffer()
	app:attach_selection({ start = { row = 0, col = 0 }, ["end"] = { row = 0, col = 4 } })
	app:remove_attachment(1)
	app.view:open_draft()
	local original = { "Explain é中 now", "leave this line alone" }
	app.view:set_text(original)
	local col = #"Explain é"
	-- Start a separate user undo block rather than merging into the API setup.
	vim.cmd("normal! i" .. string.char(7) .. "u" .. string.char(27))
	api.nvim_win_set_cursor(app.view.draft_win, { 1, col })
	vim.fn.maparg("<Tab>", "n", false, true).callback()
	eq(api.nvim_get_current_win(), app.view.attachment_win)
	api.nvim_win_set_cursor(app.view.attachment_win, { 1, 0 })
	api.nvim_feedkeys("i", "mx", false)
	eq(api.nvim_get_current_win(), app.view.draft_win)
	eq(vim.fn.mode(), "n")
	eq(app.view:get_text(), { "Explain é @2 中 now", "leave this line alone" })
	eq(api.nvim_win_get_cursor(app.view.draft_win), { 1, col + 2 })
	vim.cmd("silent undo")
	eq(app.view:get_text(), original, "inserting a reference must be one undoable edit")
	eq(app.client, nil)
end)

test("reference insertion after clear/restore snaps a saved column to a Unicode boundary", function()
	local app = fixture()
	app:attach_buffer()
	app.view:open_draft()
	app.view:set_text({ "中x" })
	app:send()
	settled(app)
	app.view:open_draft()
	app.view:set_text({ "ab" })
	api.nvim_win_set_cursor(app.view.draft_win, { 1, 1 })
	vim.fn.maparg("<Tab>", "n", false, true).callback()
	app:clear_draft()
	app:restore_last()
	api.nvim_set_current_win(app.view.attachment_win)
	api.nvim_feedkeys("i", "mx", false)
	eq(draft(app), "@1 中x", "a preserved ASCII byte column must never split restored Unicode text")
	eq(api.nvim_win_get_cursor(app.view.draft_win), { 1, 1 })
end)

test("reference insertion handles empty lines, punctuation, and a hidden composer", function()
	local app = fixture()
	app:attach_buffer()
	app.view:open_draft()
	app.view:set_text({ "" })
	app.view:insert_reference("@1")
	eq(draft(app), "@1")
	app.view:set_text({ "Explain ()" })
	api.nvim_win_set_cursor(app.view.draft_win, { 1, #"Explain (" })
	app.view:hide_draft()
	source()
	app.view:insert_reference("@1")
	eq(draft(app), "Explain (@1)")
	eq(api.nvim_get_current_win(), app.view.draft_win)
	eq(api.nvim_win_get_cursor(app.view.draft_win), { 1, #"Explain (@" })
	app.view:set_text({ "word" })
	api.nvim_win_set_cursor(app.view.draft_win, { 1, 0 })
	app.view:insert_reference("@1")
	eq(draft(app), "@1 word")
end)

test("reference insertion never edits a repurposed draft window", function()
	local app = fixture()
	app:attach_buffer()
	app.view:open_draft()
	app.view:set_text({ "question" })
	local repurposed = app.view.draft_win
	api.nvim_win_set_buf(repurposed, source_buf)
	app.view:insert_reference("@1")
	eq(text(source_buf), "disk source\nsecond line")
	if api.nvim_win_is_valid(repurposed) then
		eq(api.nvim_win_get_buf(repurposed), source_buf)
	end
	has(draft(app), "@1")
end)

test("draft hide/reopen preserves buffer, text, cursor, and undo", function()
	local app = fixture()
	app.view:open_draft()
	app.view:set_text({ "original" })
	local buf = app.view.draft_buf
	-- API writes and :normal can share an undo block inside one Lua invocation.
	-- Explicitly begin the user's edit block, as a separate interactive edit would.
	vim.cmd("normal! A" .. string.char(7) .. "u edited" .. string.char(27))
	eq(draft(app), "original edited")
	local undo = vim.fn.undotree().seq_cur
	local cursor = api.nvim_win_get_cursor(app.view.draft_win)
	app.view:hide_draft()
	app.view:open_draft()
	eq(app.view.draft_buf, buf)
	eq(draft(app), "original edited")
	eq(vim.fn.undotree().seq_cur, undo, "opening draft must not rewrite contents")
	eq(api.nvim_win_get_cursor(app.view.draft_win), cursor)
	vim.cmd("silent undo")
	eq(draft(app), "original")
end)

test("visible attachment list and either window closes paired composer", function()
	local app = fixture()
	app:attach_buffer()
	app.view:open_draft()
	has(text(app.view.attachment_buf), "source.lua")
	local config = api.nvim_win_get_config(app.view.attachment_win)
	eq(config.title, nil)
	has(config.footer[1][1], "Attachments (1)")
	has(config.footer[1][1], "i reference")
	has(config.footer[1][1], "Enter preview / d remove / r refresh")
	eq(vim.bo[app.view.attachment_buf].modifiable, false)
	eq(vim.bo[app.view.attachment_buf].readonly, true)
	for _, field in ipairs({ "draft_win", "attachment_win" }) do
		app.view:open_draft()
		local draft_win, attachment_win = app.view.draft_win, app.view.attachment_win
		api.nvim_win_close(app.view[field], true)
		wait_for(function()
			return not api.nvim_win_is_valid(draft_win) and not api.nvim_win_is_valid(attachment_win)
		end, "paired window closure")
	end
	app:remove_attachment(1)
	eq(#app.attachments, 0)
	has(text(app.view.attachment_buf), "no attachments")
	app.view:open_draft()
	local empty = api.nvim_win_get_config(app.view.attachment_win)
	eq(empty.title, nil)
	has(empty.footer[1][1], "Attachments (0)")
end)

test("explicit and active Visual selections include complete multibyte characters", function()
	local app = fixture()
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "aé中z", "tail" })
	app:attach_selection({ start = { row = 0, col = 1 }, ["end"] = { row = 0, col = 6 } })
	eq(app.attachments[1].capture.lines, { "é中" })
	has(app.attachments[1].text, "[0:1] | é中")
	api.nvim_win_set_cursor(base_win, { 1, 1 })
	vim.cmd("normal! v")
	api.nvim_win_set_cursor(base_win, { 1, 3 })
	eq(vim.fn.mode(), "v")
	app:attach_selection()
	eq(app.attachments[2].capture.lines, { "é中" })
	eq(vim.fn.mode(), "v", "capture should not leave Visual mode")
	api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	local ok = pcall(function()
		app:attach_selection()
	end)
	eq(ok, false, "normal mode must not reuse stale Visual marks")
end)

test("relative file path and explicit unsaved-buffer/disk/cancel choice", function()
	local app = fixture()
	app:attach_file("source.lua")
	eq(app.attachments[1].path, directory .. "/source.lua")
	has(app.attachments[1].text, '"source.lua"')
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "UNSAVED contents" })
	for index, choice in ipairs({ "Attach unsaved buffer snapshot", "Attach disk reference", "Cancel" }) do
		vim.ui.select = function(items, _, callback)
			eq(items[index], choice)
			callback(choice, index)
		end
		app:attach_file("source.lua")
	end
	eq(#app.attachments, 3)
	eq(app.attachments[2].capture.lines, { "UNSAVED contents" })
	has(app.attachments[3].text, "File reference (disk")
	assert(not app.attachments[3].text:find("UNSAVED", 1, true))
	eq(vim.fn.readfile(directory .. "/source.lua"), { "disk source", "second line" })
end)

test("late unsaved-file choice is invalidated by clear, new, or accepted send", function()
	for _, action in ipairs({ "clear", "new", "ack" }) do
		source()
		local app = fixture()
		api.nvim_buf_set_lines(source_buf, 0, -1, false, { "pending unsaved snapshot" })
		local choose
		vim.ui.select = function(_, _, callback)
			choose = callback
		end
		app:attach_file("source.lua")
		assert(choose, "expected deferred unsaved-file picker")
		if action == "clear" then
			app:clear_draft()
		elseif action == "new" then
			app:new_conversation()
		else
			app.view:set_text({ "question while picker pending" })
			app:send()
			settled(app)
		end
		choose("Attach unsaved buffer snapshot", 1)
		eq(#app.attachments, 0, "stale choice must not mutate a later draft: " .. action)
	end
end)

test("diagnostics freeze and overlapping undercursor choice", function()
	local app = fixture()
	local ns = api.nvim_create_namespace("pi-test-diagnostics")
	local diagnostics = {
		{ lnum = 0, col = 0, end_lnum = 0, end_col = 8, message = "outer", severity = 1 },
		{ lnum = 0, col = 2, end_lnum = 0, end_col = 5, message = "inner", severity = 2 },
		{ lnum = 1, col = 0, end_lnum = 1, end_col = 4, message = "elsewhere", severity = 3 },
	}
	vim.diagnostic.set(ns, source_buf, diagnostics)
	app:attach_diagnostics(false)
	api.nvim_win_set_cursor(base_win, { 1, 3 })
	vim.ui.select = function(items, opts, callback)
		eq(#items, 2)
		for _, item in ipairs(items) do
			if opts.format_item(item) == "inner" then
				callback(item)
				return
			end
		end
		error("overlapping inner diagnostic not offered")
	end
	app:attach_diagnostics(true)
	eq(app.attachments[2].capture.diagnostics[1].message, "inner")
	local frozen = app.attachments[1].text
	diagnostics[1].message = "republished diagnostic"
	vim.diagnostic.set(ns, source_buf, diagnostics)
	eq(app.attachments[1].text, frozen)
	has(frozen, "outer")
	app.view:set_text({ "diagnose" })
	app:send()
	eq(app.client, nil, "changed diagnostics reject before starting process")
	assert(notice("Attachments changed"))
	app:refresh_attachment(1)
	has(app.attachments[1].text, "republished diagnostic")
end)

test("quickfix captures paths, fileless messages, list metadata, and freezes", function()
	local app = fixture()
	vim.fn.setqflist({}, " ", {
		title = "compiler errors",
		items = {
			{ bufnr = source_buf, lnum = 1, col = 3, text = "source diagnostic", type = "E" },
			{ text = "global build failure", valid = 0 },
		},
	})
	app:attach_quickfix()
	local item = app.attachments[1]
	has(item.text, "compiler errors")
	has(item.text, 'file="source.lua"')
	has(item.text, 'file="[no file]"')
	has(item.text, "global build failure")
	has(item.text, "location=1:3")
	has(item.text, 'type="E"')
	for _, field in ipairs({ "valid=", "nr=", 'pattern=""', 'module=""', 'type=""', "–0:0", "location=0:0" }) do
		lacks(item.text, field)
	end
	eq(item.list.items[2].valid, 0, "bookkeeping must remain internal")
	local frozen = item.text
	vim.fn.setqflist({}, "r", { title = "new errors", items = { { text = "new failure" } } })
	eq(item.text, frozen)
	app.view:set_text({ "explain quickfix" })
	app:send()
	eq(app.client, nil)
	app:refresh_attachment(1)
	has(app.attachments[1].text, "new failure")
end)

test("quickfix preserves populated range, column, pattern and module context", function()
	local app = fixture()
	vim.fn.setqflist({}, " ", {
		title = "search results",
		items = {
			{ bufnr = source_buf, lnum = 1, col = 2, end_lnum = 2, end_col = 4, vcol = 1, text = "span", type = "W" },
			{ bufnr = source_buf, pattern = "^target", module = "parser", text = "pattern match" },
		},
	})
	app:attach_quickfix()
	local body = app.attachments[1].text
	has(body, 'location=1:2–2:4 column=display type="W"')
	has(body, 'pattern="^target" module="parser"')
	has(body, "pattern match")
	lacks(body, "valid=")
end)

test("changed source rejects send; refresh captures new text and permits send", function()
	local app, log, calls = fixture()
	app:attach_buffer()
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "updated unsaved text" })
	eq(app.attachments[1].capture.lines, { "disk source", "second line" })
	app.view:set_text({ "explain" })
	app:send()
	eq(calls(), 0)
	eq(draft(app), "explain")
	assert(notice("Attachments changed"))
	app:refresh_attachment(1)
	eq(app.attachments[1].capture.lines, { "updated unsaved text" })
	app:send()
	settled(app)
	eq(calls(), 1)
	has(records(log, "in", "prompt")[1].message, "updated unsaved text")
	eq(vim.fn.readfile(directory .. "/source.lua"), { "disk source", "second line" })
end)

test("disk and source-identity changes reject send without starting a process", function()
	local app = fixture()
	app:attach_file("source.lua")
	vim.fn.writefile({ "disk contents changed substantially" }, directory .. "/source.lua")
	app.view:set_text({ "disk question" })
	app:send()
	eq(app.client, nil)
	assert(notice("Attachments changed"))
	app:refresh_attachment(1)
	app:remove_attachment(1)
	app:attach_buffer()
	local captured = app.attachments[1]
	api.nvim_buf_set_name(source_buf, directory .. "/renamed.lua")
	app:send()
	eq(app.client, nil)
	app:refresh_attachment(1)
	eq(app.attachments[1], captured, "refresh must not silently change source identity")
	assert(notice("identity changed"))
end)

test("quickfix becomes stale when its loaded source changes", function()
	local app = fixture()
	vim.fn.setqflist({}, " ", { title = "source", items = { { bufnr = source_buf, lnum = 1, text = "error" } } })
	app:attach_quickfix()
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "changed" })
	app.view:set_text({ "question" })
	app:send()
	eq(app.client, nil)
	assert(notice("Attachments changed"))
	app:refresh_attachment(1)
	app:send()
	settled(app)
end)

test("read-only RPC argv/cwd; two prompts reuse client and authoritative final chat", function()
	local app, log, calls = fixture()
	app.view:set_text({ "First question" })
	app:send()
	settled(app)
	local client = app.client
	app.view:set_text({ "Follow-up question" })
	app:send()
	settled(app)
	eq(app.client, client)
	eq(calls(), 1)
	eq(#records(log, "start"), 1)
	eq(#records(log, "in", "prompt"), 2)
	eq(#app.archive, 2)
	eq(#app.state.messages, 4, "one user and one assistant per prompt")
	local startup = records(log, "start")[1]
	eq(startup.cwd, directory)
	local args = startup.argv
	for _, flag in ipairs({
		"--no-session",
		"--no-extensions",
		"--no-approve",
		"--no-skills",
		"--no-prompt-templates",
		"--no-context-files",
	}) do
		assert(vim.list_contains(args, flag), "missing safety flag " .. flag)
	end
	for i, arg in ipairs(args) do
		if arg == "--tools" then
			eq(args[i + 1], "read,grep,find,ls")
		end
	end
	assert(vim.list_contains(args, "--tools"))
	eq(args[#args - 1], "--mode")
	eq(args[#args], "rpc")
	local chat = text(app.view.chat_buf)
	has(chat, "FINAL answer 1")
	has(chat, "FINAL answer 2")
	assert(not chat:find("DRAFT delta", 1, true), "final must replace streamed draft")
	local _, count = chat:gsub("FINAL answer", "")
	eq(count, 2, "final messages must not duplicate")
	eq(vim.bo[app.view.chat_buf].modifiable, false)
end)

test("rejected prompt keeps draft and attachments, without archive", function()
	local app = fixture("reject")
	app:attach_buffer()
	app.view:set_text({ "Rejected question" })
	app:send()
	settled(app)
	eq(draft(app), "Rejected question")
	eq(#app.attachments, 1)
	eq(#app.archive, 0)
	has(app.status, "fixture rejected prompt")
	has(app.status, "draft kept")
end)

test("settled before acknowledgement still archives accepted draft", function()
	local app = fixture("early_settle")
	app:attach_buffer()
	app.view:set_text({ "Very fast answer" })
	app:send()
	wait_for(function()
		return app.task.done and app.task.awaiting_ack
	end, "settlement before delayed acknowledgement")
	eq(#app.archive, 0)
	eq(draft(app), "Very fast answer")
	local chat = text(app.view.chat_buf)
	has(chat, "Very fast answer")
	assert(not chat:find("User question:", 1, true), "event-before-ack chat must not show serialized prompt")
	assert(not chat:find("disk source", 1, true), "event-before-ack chat must not dump attachments")
	app:send()
	assert(notice("busy"), "settled-but-unacknowledged task remains busy")
	settled(app)
	eq(#app.archive, 1)
	eq(draft(app), "")
	eq(#app.attachments, 0)
end)

test("user text and new attachment added while awaiting ack are retained", function()
	local app, log = fixture("slow_ack")
	app:attach_buffer()
	app.view:set_text({ "Submitted question" })
	app:send()
	wait_for(function()
		return #app.state.messages == 2 and app.task.awaiting_ack
	end, "event before acknowledgement")
	app.view:set_text({ "Next unsent question" })
	source()
	app:attach_selection({ start = { row = 0, col = 0 }, ["end"] = { row = 0, col = 4 } })
	app:send()
	settled(app)
	eq(#records(log, "in", "prompt"), 1)
	eq(draft(app), "Next unsent question")
	eq(#app.attachments, 1)
	eq(app.attachments[1].capture.lines, { "disk" })
	eq(app.archive[1].question, "Submitted question")
	eq(#app.archive[1].attachments, 1)
end)

test("restore accepted draft and frozen attachments; refuse clobbering edits", function()
	local app = fixture()
	app:attach_buffer()
	app.view:set_text({ "restore me", "second paragraph" })
	app:send()
	settled(app)
	app:restore_last()
	eq(draft(app), "restore me\nsecond paragraph")
	eq(#app.attachments, 1)
	app.attachments[1].capture.lines[1] = "changed restored copy"
	eq(app.archive[1].attachments[1].capture.lines[1], "disk source")
	app.view:set_text({ "new edits" })
	app:restore_last()
	eq(draft(app), "new edits")
	assert(notice("Clear the current draft"))
	app:clear_draft()
	eq(draft(app), "")
	eq(#app.attachments, 0)
	app:restore_last()
	eq(draft(app), "restore me\nsecond paragraph")
end)

test("accepted provider failure is displayed and recoverable via restore", function()
	local app = fixture("provider_error")
	app.view:set_text({ "provider question" })
	app:send()
	settled(app)
	eq(#app.archive, 1)
	eq(draft(app), "")
	eq(app.state.messages[2].status, "error")
	has(text(app.view.chat_buf), "fixture provider failed")
	has(app.status, "Failed")
	app:restore_last()
	eq(draft(app), "provider question")
end)

test("handled prompt finishes without waiting for nonexistent answer", function()
	local app = fixture("handled")
	app.view:set_text({ "handled question" })
	app:send()
	settled(app)
	eq(#app.archive, 1)
	has(app.status, "handled")
end)

test("busy send is rejected; abort waits for queue clearance then aborts", function()
	local app, log = fixture("hold")
	app.view:set_text({ "held question" })
	app:send()
	wait_for(function()
		return #app.archive == 1
	end, "accepted held prompt")
	app.view:set_text({ "keep this next draft" })
	app:send()
	eq(#records(log, "in", "prompt"), 1)
	assert(notice("busy"))
	local held_client, held_task = app.client, app.task
	app:new_conversation()
	eq(app.client, held_client)
	eq(app.task, held_task, "busy PiNew must not replace active conversation")
	assert(notice("Abort or wait"))
	app:abort()
	settled(app)
	wait_for(function()
		return #records(log, "in", "abort") == 1
	end, "abort received")
	local incoming = records(log, "in")
	eq(incoming[#incoming - 1].type, "clear_queue")
	eq(incoming[#incoming].type, "abort")
	local cleared = false
	for _, entry in ipairs(vim.fn.readfile(log)) do
		local event = vim.json.decode(entry)
		if event.direction == "out" and event.record.command == "clear_queue" then
			cleared = true
		elseif event.direction == "in" and event.record.type == "abort" then
			assert(cleared, "abort sent before clear_queue acknowledgement")
		end
	end
	eq(draft(app), "keep this next draft")
	has(app.status, "Cancelled")
end)

test("deadline stops held subprocess and requires explicit new conversation", function()
	local app, log = fixture("hold", { timeout_ms = 150 })
	app.view:set_text({ "deadline question" })
	app:send()
	local client = app.client
	wait_for(function()
		return app.task.done and client.status == "stopped"
	end, "deadline process shutdown")
	assert(app.lost)
	app.view:set_text({ "do not automatically restart" })
	app:send()
	eq(#records(log, "in", "prompt"), 1)
	assert(notice("PiNew"))
end)

test("acknowledgement timeout is uncertain: stop client, preserve draft, require PiNew", function()
	local app, log = fixture("slow_ack", { request_timeout_ms = 30 })
	app:attach_buffer()
	app.view:set_text({ "uncertain submission" })
	app:send()
	local client = app.client
	wait_for(function()
		return app.lost and client.status == "stopped"
	end, "uncertain prompt shutdown")
	eq(draft(app), "uncertain submission")
	eq(#app.attachments, 1)
	eq(#app.archive, 0)
	app:send()
	eq(#records(log, "in", "prompt"), 1, "uncertain submission must not automatically retry")
	assert(notice("PiNew"))
	app:new_conversation()
	eq(app.client, nil)
	eq(app.lost, false)
end)

test("startup delay rechecks attachment freshness before actually submitting", function()
	local client = { status = "stopped", prompts = 0 }
	function client:on()
		return function() end
	end
	function client:start(callback)
		self.status, self.started = "starting", callback
	end
	function client:prompt()
		self.prompts = self.prompts + 1
	end
	function client:stop()
		self.status = "stopped"
	end
	clients[#clients + 1] = client
	local app = fixture(nil, {
		client_factory = function()
			return client
		end,
	})
	app:attach_buffer()
	app.view:set_text({ "startup source question" })
	app:send()
	api.nvim_buf_set_lines(source_buf, 0, -1, false, { "changed during startup" })
	client.status = "running"
	client.started(nil, {})
	eq(client.prompts, 0, "stale snapshot must not be submitted after startup")
	eq(draft(app), "startup source question")
	eq(#app.attachments, 1)
	eq(#app.archive, 0)
	assert(app.task.done and not app.task.awaiting_ack)
end)

test("unexpected exit preserves rejected/unacknowledged draft and reports loss", function()
	local app = fixture("exit")
	app.view:set_text({ "exit question" })
	app:send()
	local client = app.client
	wait_for(function()
		return app.lost and client.status == "stopped"
	end, "unexpected subprocess exit")
	eq(draft(app), "exit question")
	eq(#app.archive, 0)
	has(app.status, "exited")
	eq(app.state.messages[2].status, "interrupted")
	app:send()
	assert(notice("PiNew"))
end)

test("dispose during delayed ack is safe and stops process", function()
	local app = fixture("slow_ack")
	app.view:set_text({ "dispose question" })
	app:send()
	local client = app.client
	wait_for(function()
		return #app.state.messages == 2
	end, "stream before disposal")
	app:dispose()
	app:dispose()
	wait_for(function()
		return client.status == "stopped"
	end, "disposed process exit")
	eq(app.disposed, true)
	eq(#app.archive, 0)
	eq(app.view.draft_buf, nil)
	eq(app.view.chat_buf, nil)
end)

test("disposed application ignores manually delivered late startup, event, and prompt callbacks", function()
	local function mock(starting)
		local client = { status = starting and "stopped" or "running" }
		function client:on(_, callback)
			self.event = callback
			return function() end
		end
		function client:start(callback)
			self.status, self.started = "starting", callback
		end
		function client:prompt(_, callback)
			self.ack = callback
		end
		function client:stop()
			self.status = "stopped"
		end
		clients[#clients + 1] = client
		return client
	end
	for _, starting in ipairs({ true, false }) do
		local client = mock(starting)
		local app = fixture(nil, {
			client_factory = function()
				return client
			end,
		})
		app.view:set_text({ "late callback question" })
		app:send()
		app:dispose()
		local state = app.state:snapshot()
		if starting then
			client.started(nil, {})
			eq(client.ack, nil, "late startup must not submit prompt")
		else
			client.ack(nil, { disposition = "started" })
		end
		client.event({ type = "agent_start" })
		client.event({ type = "agent_settled" })
		eq(app.state:snapshot(), state)
		eq(#app.archive, 0)
		eq(app.view.chat_buf, nil)
	end
end)

test("wiping views during delayed ack and rendering does not lose later edits", function()
	local app = fixture("slow_ack")
	app.view:open_draft()
	app.view:set_text({ "live wipe question" })
	app:send()
	wait_for(function()
		return #app.state.messages == 2
	end, "live message before wipe")
	api.nvim_buf_delete(app.view.draft_buf, { force = true })
	app.view:open_draft()
	eq(draft(app), "live wipe question")
	app.view:set_text({ "edits after wipe" })
	api.nvim_buf_delete(app.view.chat_buf, { force = true })
	settled(app)
	eq(draft(app), "edits after wipe")
	has(text(app.view.chat_buf), "FINAL answer 1")
	eq(#app.archive, 1)
end)

test("external view wipes are safe and preserve draft contents", function()
	local app = fixture()
	app.view:open_draft()
	app.view:set_text({ "survive wipe" })
	api.nvim_buf_delete(app.view.draft_buf, { force = true })
	app.view:open_draft()
	eq(draft(app), "survive wipe")
	api.nvim_buf_delete(app.view.attachment_buf, { force = true })
	app.view:open_draft()
	assert(api.nvim_buf_is_valid(app.view.attachment_buf))
	app.view:show_preview("wipe preview", "preview text")
	api.nvim_buf_delete(app.view.preview_buf, { force = true })
	app.view:show_preview("new preview", "new text")
	has(text(app.view.preview_buf), "new text")
	app.view:open_chat()
	api.nvim_buf_delete(app.view.chat_buf, { force = true })
	app.view:write_chat({ "new chat" })
	app.view:open_chat()
	has(text(app.view.chat_buf), "new chat")
end)

test("PiNew uses a fresh client and reducer, keeps tools read-only, changes workspace explicitly", function()
	local app, log, calls = fixture()
	app.view:set_text({ "old conversation" })
	app:send()
	settled(app)
	local old_client = app.client
	app:new_conversation()
	eq(app.client, nil)
	eq(#app.state.messages, 0)
	eq(#app.archive, 0)
	app.view:set_text({ "fresh conversation" })
	app:send()
	settled(app)
	assert(app.client ~= old_client)
	eq(calls(), 2)
	eq(#app.state.messages, 2)
	local startups = records(log, "start")
	eq(#startups, 2)
	eq(startups[1].argv, startups[2].argv, "new conversation must not enable edit/bash tools")
	local other = directory .. "/other"
	vim.fn.mkdir(other)
	app.view:set_text({ "unsent draft" })
	local ok = pcall(function()
		app:new_conversation(other)
	end)
	eq(ok, false, "workspace change requires empty draft")
	app:clear_draft()
	app:new_conversation(other)
	eq(app.workspace, other)
	eq(app.client, nil, "PiNew alone must not start a process")
end)

test("setup commands work and repeated setup disposes old ownership", function()
	local unused, log, _, options = fixture()
	unused:dispose()
	local first = integration.setup(options)
	apps[#apps + 1] = first
	for _, name in ipairs({
		"PiAsk",
		"PiChat",
		"PiSend",
		"PiAbort",
		"PiNew",
		"PiClear",
		"PiRestore",
		"PiPreview",
		"PiAttachFile",
		"PiAttachBuffer",
		"PiAttachDiagnostic",
		"PiAttachDiagnostics",
		"PiAttachSelection",
		"PiAttachQuickfix",
	}) do
		assert(api.nvim_get_commands({})[name], "missing command " .. name)
	end
	vim.cmd("PiAsk")
	first.view:set_text({ "command draft" })
	source()
	vim.cmd("1,2PiAttachSelection")
	eq(first.attachments[1].capture.range.start.row, 0)
	eq(first.attachments[1].capture.range["end"].row, 2)
	vim.cmd("PiPreview")
	has(text(first.view.preview_buf), "command draft")
	eq(records(log, "start"), {})
	source()
	vim.cmd("PiSend")
	settled(first)
	local retired = first.client
	local second = integration.setup(options)
	apps[#apps + 1] = second
	eq(first.disposed, true)
	wait_for(function()
		return retired.status == "stopped"
	end, "setup replacement stops old process")
	source()
	vim.cmd("PiAsk")
	assert(second.view.draft_win and api.nvim_win_is_valid(second.view.draft_win))
	vim.cmd("PiClear")
	eq(draft(second), "")
	second:dispose()
	eq(api.nvim_get_commands({}).PiAsk, nil)
end)

if vim.env.PI_TEST_FILTER then
	tests = vim.tbl_filter(function(entry)
		return entry[1]:find(vim.env.PI_TEST_FILTER, 1, true) ~= nil
	end, tests)
	assert(#tests > 0, "PI_TEST_FILTER matched no cases")
end

for index, entry in ipairs(tests) do
	if vim.env.PI_TEST_VERBOSE then
		print("Pi test " .. index .. ": " .. entry[1])
	end
	apps, clients, notices = {}, {}, {}
	vim.ui.select = original_select
	directory = root .. "/case-" .. index
	vim.fn.mkdir(directory, "p")
	vim.fn.writefile({ "disk source", "second line" }, directory .. "/source.lua")
	source_buf = vim.fn.bufadd(directory .. "/source.lua")
	vim.fn.bufload(source_buf)
	source()
	vim.v.errmsg = ""
	local ok, err = xpcall(entry[2], debug.traceback)
	if not ok then
		failures[#failures + 1] = entry[1] .. ": " .. err
	end
	api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	for _, app in ipairs(apps) do
		local clean, reason = pcall(function()
			app:dispose()
		end)
		if not clean then
			failures[#failures + 1] = entry[1] .. " cleanup: " .. tostring(reason)
		end
	end
	local stopped = vim.wait(3000, function()
		for _, client in ipairs(clients) do
			if client.status ~= "stopped" then
				return false
			end
		end
		return true
	end, 5)
	if not stopped then
		failures[#failures + 1] = entry[1] .. " cleanup: client did not stop before quit"
	end
	-- Flush coalesced renders / window teardown; they must be safe after disposal.
	vim.wait(60, function()
		return false
	end, 5)
	if vim.v.errmsg ~= "" then
		failures[#failures + 1] = entry[1] .. " asynchronous editor error: " .. vim.v.errmsg
	end
	for _, item in ipairs(notices) do
		if item.level == vim.log.levels.ERROR and not item.message:match("^Pi:") then
			failures[#failures + 1] = entry[1] .. " asynchronous error: " .. item.message
		end
	end
end
vim.notify, vim.ui.select = original_notify, original_select
vim.fn.delete(root, "rf")
if #failures > 0 then
	io.stderr:write(string.format("Pi tests: %d failure(s), %d cases\n", #failures, #tests))
	for _, failure in ipairs(failures) do
		io.stderr:write("FAIL " .. failure .. "\n")
	end
	vim.cmd("cquit 1")
else
	print(string.format("Pi tests: %d passed (offline deterministic RPC)", #tests))
	vim.cmd("qa!")
end
