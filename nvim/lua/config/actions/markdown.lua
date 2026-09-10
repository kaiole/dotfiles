local M = {}

function M.wrap_in_blockquote(first_line, last_line)
	local lines = vim.api.nvim_buf_get_lines(0, first_line - 1, last_line, false)

	for index, line in ipairs(lines) do
		lines[index] = "> " .. line
	end

	vim.api.nvim_buf_set_lines(0, first_line - 1, last_line, false, lines)
end

return M
