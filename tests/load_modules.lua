-- Requires every module so syntax errors and bad requires fail fast.
-- Run from anywhere: nvim --clean --headless -l tests/load_modules.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)

local failures = {}
for _, file in ipairs(vim.fn.glob(root .. "/lua/cheatsheet_generator/*.lua", false, true)) do
  local module = "cheatsheet_generator." .. vim.fn.fnamemodify(file, ":t:r")
  -- external_script runs the whole generator when required; tests/run.lua covers it.
  if module ~= "cheatsheet_generator.external_script" then
    local ok, err = pcall(require, module)
    if not ok then
      failures[#failures + 1] = module .. ": " .. tostring(err)
    end
  end
end

if #failures > 0 then
  io.stderr:write("Modules failed to load:\n" .. table.concat(failures, "\n") .. "\n")
  os.exit(1)
end
print("All modules loaded")
