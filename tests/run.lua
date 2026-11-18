-- End-to-end test: runs the generator against tests/fixture the way :CheatsheetGenerate does
-- (external_script.lua in a clean, headless Neovim) and checks the generated markdown.
-- Run from anywhere: nvim --clean --headless -l tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local fixture = root .. "/tests/fixture"
local script = root .. "/lua/cheatsheet_generator/external_script.lua"

-- An empty data dir, so recipe repos installed under stdpath("data")/lazy on this machine
-- do not leak keymaps into the output.
local data_home = vim.fn.tempname()
vim.fn.mkdir(data_home, "p")

local failures = {}
local function check(name, ok, detail)
  if ok then
    print("ok   " .. name)
  else
    print("FAIL " .. name .. (detail and ("\n     " .. detail) or ""))
    failures[#failures + 1] = name
  end
end

--- Runs the generator with `output` merged over the base output config and `overrides` over the
-- top-level config, and returns the markdown.
local function generate(output, overrides)
  local out_file = vim.fn.tempname() .. ".md"
  local config = {
    plugin_dirs = { "lua/plugins" },
    config_keymap_files = { "lua/config/keymaps.lua" },
    output = vim.tbl_extend("force", {
      file = out_file,
      title = "Fixture Cheatsheet",
      github_info = { url = "https://github.com/example/cfg", branch = "main" },
    }, output or {}),
  }
  config = vim.tbl_extend("force", config, overrides or {})
  local result = vim
    .system({
      vim.v.progpath,
      "--clean",
      "--headless",
      "-c",
      "set rtp+=" .. root,
      "-c",
      "set rtp+=.",
      "-l",
      script,
      vim.json.encode(config),
    }, { cwd = fixture, text = true, env = { XDG_DATA_HOME = data_home } })
    :wait()
  -- external_script.lua exits 0 even when it prints an error, so check for both.
  if result.code ~= 0 or (result.stdout or ""):find("Error:", 1, true) or vim.fn.filereadable(out_file) == 0 then
    error(("generator failed (exit %d)\n%s%s"):format(result.code, result.stdout or "", result.stderr or ""))
  end
  return table.concat(vim.fn.readfile(out_file), "\n")
end

local function has(md, line)
  return md:find(line, 1, true) ~= nil
end

local link = "https://github.com/example/cfg/blob/main/"

local md = generate({ include_date = false })
check("title", has(md, "# Fixture Cheatsheet"))
check(
  "plugin keymap with default mode",
  has(
    md,
    "| `<leader>xe` | `n` | Open Example | [`lua/plugins/example.lua:5`](" .. link .. "lua/plugins/example.lua#L5) |"
  )
)
check(
  "plugin keymap with string mode",
  has(
    md,
    "| `<leader>xv` | `v` | Example Visual | [`lua/plugins/example.lua:6`](" .. link .. "lua/plugins/example.lua#L6) |"
  )
)
check("plugin section heading", has(md, "## Plugin: example.nvim"))
check(
  "mode table before desc lists every mode",
  has(
    md,
    "| `<leader>xa` | `n` `v` | Mode Table Before Desc | [`lua/plugins/example.lua:7`]("
      .. link
      .. "lua/plugins/example.lua#L7) |"
  )
)
check(
  "mode table after desc lists every mode",
  has(
    md,
    "| `<leader>xb` | `n` `x` | Mode Table After Desc | [`lua/plugins/example.lua:8`]("
      .. link
      .. "lua/plugins/example.lua#L8) |"
  )
)
check(
  "config keymap",
  has(md, "| `<leader>qq` | `n` | Quit All | [`lua/config/keymaps.lua:1`](" .. link .. "lua/config/keymaps.lua#L1) |")
)
check("built-in keymaps", has(md, "| `dd` | `n` | Delete line | <sub>Built-in Neovim default</sub> |"))
check("no keymaps from installed recipe repos", not has(md, "lazy_ufo_recipe") and not has(md, "lazy_jumpliner_recipe"))
check("include_date = false omits the date", not md:find("%d%d%d%d%-%d%d%-%d%d"))

local without_built_ins = generate({ include_date = false }, { built_in_keymaps = { enabled = false } })
check("built_in_keymaps.enabled = false leaves out built-ins", not has(without_built_ins, "Built-in Neovim default"))
check(
  "built_in_keymaps.enabled = false keeps plugin keymaps",
  has(without_built_ins, "| `<leader>xe` | `n` | Open Example |")
)

local dated = generate({ include_date = true })
check("include_date = true adds the date", dated:find(os.date("%Y-%m-%d"), 1, true) ~= nil)

if #failures > 0 then
  io.stderr:write(("%d check(s) failed: %s\n"):format(#failures, table.concat(failures, ", ")))
  os.exit(1)
end
print("All checks passed")
