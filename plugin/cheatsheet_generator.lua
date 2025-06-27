-- Auto-create commands when plugin loads
if vim.fn.has("nvim-0.7") == 1 then
	require("cheatsheet_generator").create_commands()
end

