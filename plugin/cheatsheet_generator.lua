-- Auto-create command when plugin loads
if vim.fn.has('nvim-0.7') == 1 then
  require('cheatsheet_generator').create_command()
end