--- Keymap parsing module for analyzing plugin configuration files
-- @module cheatsheet_generator.keymap_parser

local utils = require("cheatsheet_generator.utils")
local M = {}

--- Parses plugin keymaps from configuration files
-- @param config table Configuration object with plugin directories and files
-- @return table List of parsed plugin keymaps
function M.parse_plugin_keymaps(config)
  local plugin_keymaps = {}

  local plugin_files = {}

  local plugin_dirs = config and config.plugin_dirs or { "lua/plugins" }
  for _, plugins_dir in ipairs(plugin_dirs) do
    local escaped_dir = vim.fn.shellescape(plugins_dir)
    local cmd = "find " .. escaped_dir .. " -name '*.lua' -type f 2>/dev/null"
    local success, plugins_handle = pcall(io.popen, cmd)
    if success and plugins_handle then
      local file_success, files = pcall(function()
        local files = {}
        for file in plugins_handle:lines() do
          table.insert(files, file)
        end
        return files
      end)
      plugins_handle:close()

      if file_success then
        for _, file in ipairs(files) do
          table.insert(plugin_files, file)
        end
      else
        print("Warning: Error reading files from directory: " .. plugins_dir)
      end
    else
      print("Warning: Could not scan plugin directory: " .. plugins_dir)
    end
  end

  local escaped_ftplugin = vim.fn.shellescape("ftplugin")
  local ftplugin_cmd = "find " .. escaped_ftplugin .. " -name '*.lua' -type f 2>/dev/null"
  local ft_success, ftplugin_handle = pcall(io.popen, ftplugin_cmd)
  if ft_success and ftplugin_handle then
    local file_success, files = pcall(function()
      local files = {}
      for file in ftplugin_handle:lines() do
        table.insert(files, file)
      end
      return files
    end)
    ftplugin_handle:close()

    if file_success then
      for _, file in ipairs(files) do
        table.insert(plugin_files, file)
      end
    else
      print("Warning: Error reading files from ftplugin directory")
    end
  end

  if config and config.config_keymap_files then
    for _, config_file in ipairs(config.config_keymap_files) do
      table.insert(plugin_files, config_file)
    end
  else
    table.insert(plugin_files, "lua/config/keymaps.lua")
  end

  for _, file in ipairs(plugin_files) do
    local file_keymaps = M._parse_file(file)
    for _, keymap in ipairs(file_keymaps) do
      table.insert(plugin_keymaps, keymap)
    end
  end

  -- Scan installed plugin directories for additional keymaps
  local installed_plugin_keymaps = M._scan_installed_plugin_directories()
  for _, keymap in ipairs(installed_plugin_keymaps) do
    table.insert(plugin_keymaps, keymap)
  end

  for _, keymap in ipairs(plugin_keymaps) do
    if keymap.lhs == "<leader>uf" and keymap.source == "lua/plugins/editor.lua" then
      keymap.plugin = "eyeliner.nvim"
    end

    if
      keymap.lhs == "<leader>bD"
      and keymap.source == "lua/plugins/ui.lua"
      and (not keymap.plugin or keymap.plugin == "")
    then
      keymap.plugin = "mini.bufremove"
    end
  end

  return plugin_keymaps
end

--- Parses a single file for keymap definitions
-- @param file string Path to the file to parse
-- @return table List of keymaps found in the file
function M._parse_file(file)
  local keymaps = {}
  local success, f = pcall(io.open, file, "r")
  if not success or not f then
    print("Warning: Could not open file for parsing: " .. (file or "unknown"))
    return keymaps
  end
  f:close()

  local current_plugin = nil
  local current_plugin_disabled = false
  local in_keys_section = false
  local keys_section_plugin = nil
  local keys_section_locked = false
  local keys_section_depth = 0
  local brace_depth = 0
  local main_plugin = nil
  local main_plugin_depth = 0
  local plugin_stack = {}
  local in_config_function = false
  local config_function_plugin = nil
  local config_function_depth = 0

  local multiline_keymap = nil
  local multiline_lhs = nil
  local multiline_line_num = nil
  local multiline_mode = nil

  local line_num = 1
  local line_success, lines_iter = pcall(io.lines, file)
  if not line_success then
    print("Warning: Could not read lines from file: " .. file)
    return keymaps
  end

  for line in lines_iter do
    local open_braces = select(2, line:gsub("{", ""))
    local close_braces = select(2, line:gsub("}", ""))
    brace_depth = brace_depth + open_braces - close_braces

    -- Check if we're entering a config function
    if line:match("config%s*=%s*function") then
      in_config_function = true
      config_function_plugin = current_plugin or main_plugin
      config_function_depth = brace_depth
    end

    -- Check if we're exiting the config function
    if in_config_function and brace_depth < config_function_depth then
      in_config_function = false
      config_function_plugin = nil
      config_function_depth = 0
    end

    current_plugin, main_plugin, main_plugin_depth, current_plugin_disabled, in_keys_section, keys_section_plugin, keys_section_locked, keys_section_depth =
      M._update_plugin_context(
        line,
        brace_depth,
        plugin_stack,
        current_plugin,
        main_plugin,
        main_plugin_depth,
        current_plugin_disabled,
        in_keys_section,
        keys_section_plugin,
        keys_section_locked,
        keys_section_depth
      )
    if multiline_keymap then
      local desc = line:match('desc = "([^"]+)"')
      if desc then
        table.insert(keymaps, {
          lhs = multiline_lhs,
          rhs = "function",
          desc = desc,
          mode = multiline_mode or "n",
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = multiline_line_num,
        })
        multiline_keymap = nil
        multiline_lhs = nil
        multiline_line_num = nil
        multiline_mode = nil
      end
    end

    local multiline_start_lhs = line:match('^%s*{ "([^"]+)",%s*$')
    if multiline_start_lhs and in_keys_section then
      multiline_keymap = true
      multiline_lhs = multiline_start_lhs
      multiline_line_num = line_num
    end

    if line:match("^%s*{%s*$") and in_keys_section then
      multiline_keymap = "starting"
      multiline_line_num = line_num
    end

    if multiline_keymap == "starting" then
      local key_line_lhs = line:match('^%s*"([^"]+)",%s*$')
      if key_line_lhs then
        multiline_keymap = true
        multiline_lhs = key_line_lhs
        multiline_line_num = line_num
      end
    end

    local map_mode, map_lhs = line:match("^%s*map%([\"']([^\"']+)[\"'],%s*[\"']([^\"']+)[\"'],%s*function%(%)%s*$")
    if map_mode and map_lhs then
      multiline_keymap = true
      multiline_lhs = map_lhs
      multiline_mode = map_mode
      multiline_line_num = line_num
    end

    local vks_mode, vks_lhs =
      line:match("^%s*vim%.keymap%.set%([\"']([^\"']+)[\"'],%s*[\"']([^\"']+)[\"'],%s*function%(%)%s*$")
    if vks_mode and vks_lhs then
      multiline_keymap = true
      multiline_lhs = vks_lhs
      multiline_mode = vks_mode
      multiline_line_num = line_num
    end

    -- Handle multiline vim.keymap.set that starts on one line
    local vks_multiline_start = line:match("^%s*vim%.keymap%.set%(%s*$")
    if vks_multiline_start then
      multiline_keymap = "vim_keymap_starting"
      multiline_line_num = line_num
    end

    -- Continue parsing multiline vim.keymap.set
    if multiline_keymap == "vim_keymap_starting" then
      -- Check for single mode string
      local mode_line = line:match('^%s*"([^"]*)",%s*$')
      if mode_line then
        multiline_mode = mode_line
        multiline_keymap = "vim_keymap_mode_found"
      else
        -- Check for mode table like { "n", "v" }
        local mode_table = line:match('^%s*({ [^}]+ }),%s*$')
        if mode_table then
          multiline_mode = mode_table
          multiline_keymap = "vim_keymap_mode_found"
        end
      end
    elseif multiline_keymap == "vim_keymap_mode_found" then
      local key_line = line:match('^%s*"([^"]*)",%s*$')
      if key_line then
        multiline_lhs = key_line
        multiline_keymap = "vim_keymap_key_found"
      end
    elseif multiline_keymap == "vim_keymap_key_found" then
      -- Check if this line contains a function reference (not inline function)
      if line:match("^%s*[%w_]+,%s*$") then
        multiline_keymap = "vim_keymap_func_found"
      end
    elseif multiline_keymap == "vim_keymap_func_found" then
      local desc = line:match('{ desc = "([^"]+)"')
      if desc then
        -- Check if multiline_mode is a table of modes
        if multiline_mode and multiline_mode:match("^{") then
          -- Extract all modes and create multiple keymaps
          for mode in multiline_mode:gmatch('"([^"]+)"') do
            table.insert(keymaps, {
              lhs = multiline_lhs,
              rhs = "function",
              desc = desc,
              mode = mode,
              source = file,
              plugin = in_config_function and config_function_plugin or nil,
              plugin_disabled = current_plugin_disabled,
              line_number = multiline_line_num,
            })
          end
        else
          -- Single mode
          table.insert(keymaps, {
            lhs = multiline_lhs,
            rhs = "function",
            desc = desc,
            mode = multiline_mode or "n",
            source = file,
            plugin = in_config_function and config_function_plugin or nil,
            plugin_disabled = current_plugin_disabled,
            line_number = multiline_line_num,
          })
        end
        multiline_keymap = nil
        multiline_lhs = nil
        multiline_line_num = nil
        multiline_mode = nil
      end
    end

    M._parse_keymap_patterns(
      line,
      line_num,
      file,
      keymaps,
      in_keys_section,
      current_plugin,
      keys_section_plugin,
      main_plugin,
      current_plugin_disabled,
      in_config_function,
      config_function_plugin
    )

    line_num = line_num + 1
  end

  return keymaps
end

--- Updates plugin context tracking variables based on current line
-- @param line string Current line being processed
-- @param brace_depth number Current brace nesting depth
-- @param plugin_stack table Plugin hierarchy by depth
-- @param current_plugin string Current plugin name
-- @param main_plugin string Main plugin for this section
-- @param main_plugin_depth number Depth of main plugin
-- @param current_plugin_disabled boolean Whether current plugin is disabled
-- @param in_keys_section boolean Whether currently in a keys section
-- @param keys_section_plugin string Plugin owning the keys section
-- @param keys_section_locked boolean Whether keys section is locked
-- @param keys_section_depth number Brace depth where keys section started
-- @return string, string, number, boolean, boolean, string, boolean, number Updated context variables
function M._update_plugin_context(
  line,
  brace_depth,
  plugin_stack,
  current_plugin,
  main_plugin,
  main_plugin_depth,
  current_plugin_disabled,
  in_keys_section,
  keys_section_plugin,
  keys_section_locked,
  keys_section_depth
)
  local plugin_name = line:match('"([%w%-_%.]+/[%w%-_%.]+)"') or line:match("'([%w%-_%.]+/[%w%-_%.]+)'")
  if plugin_name and not keys_section_locked then
    current_plugin = plugin_name:match("([^/]+)$")
    plugin_stack[brace_depth] = current_plugin

    if brace_depth == 2 then
      main_plugin = current_plugin
      main_plugin_depth = brace_depth
      current_plugin_disabled = false
      in_keys_section = false
    end
  end

  if line:match("^%s*enabled%s*=%s*false") and brace_depth == 3 and main_plugin then
    current_plugin_disabled = true
  end

  if line:match("keys%s*=") then
    in_keys_section = true
    keys_section_depth = brace_depth
    keys_section_plugin = current_plugin
    if not keys_section_plugin then
      for depth = brace_depth - 1, 1, -1 do
        if plugin_stack[depth] then
          keys_section_plugin = plugin_stack[depth]
          break
        end
      end
    end
    keys_section_locked = true
  end

  -- Exit keys section when brace depth falls below where keys section started
  if in_keys_section and brace_depth < keys_section_depth then
    in_keys_section = false
    keys_section_plugin = nil
    keys_section_locked = false
    keys_section_depth = 0
  end

  for depth = brace_depth + 1, 10 do
    plugin_stack[depth] = nil
  end

  if current_plugin and plugin_stack[brace_depth] ~= current_plugin then
    current_plugin = plugin_stack[brace_depth]
  end

  if brace_depth < main_plugin_depth and main_plugin then
    main_plugin = nil
    main_plugin_depth = 0
    current_plugin = nil
    current_plugin_disabled = false
    in_keys_section = false
    keys_section_plugin = nil
    keys_section_locked = false
    keys_section_depth = 0
  end

  return current_plugin,
    main_plugin,
    main_plugin_depth,
    current_plugin_disabled,
    in_keys_section,
    keys_section_plugin,
    keys_section_locked,
    keys_section_depth
end

--- Parses various keymap patterns from a line and adds them to the keymaps list
-- @param line string Line to parse
-- @param line_num number Line number
-- @param file string Source file path
-- @param keymaps table List to add parsed keymaps to
-- @param in_keys_section boolean Whether currently in a keys section
-- @param current_plugin string Current plugin name
-- @param keys_section_plugin string Plugin owning the keys section
-- @param main_plugin string Main plugin for this section
-- @param current_plugin_disabled boolean Whether current plugin is disabled
-- @param in_config_function boolean Whether currently in a config function
-- @param config_function_plugin string Plugin owning the config function
function M._parse_keymap_patterns(
  line,
  line_num,
  file,
  keymaps,
  in_keys_section,
  current_plugin,
  keys_section_plugin,
  main_plugin,
  current_plugin_disabled,
  in_config_function,
  config_function_plugin
)
  local patterns = {
    function()
      local lhs, rhs, desc = line:match('{ "([^"]+)",%s*"([^"]+)",%s*desc = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = "n",
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local lhs, func, desc = line:match('{ "([^"]+)",%s*(function%([^)]*%).-end),%s*desc = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = func,
          desc = desc,
          mode = "n",
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local lhs, desc = line:match('{ "([^"]+)",%s*desc = "([^"]+)" }')
      if lhs then
        return {
          lhs = lhs,
          rhs = "",
          desc = desc,
          mode = "n",
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      -- Handle { "lhs", desc = "description", mode = { "n", "v" } } pattern
      local lhs, desc, modes = line:match('{ "([^"]+)",%s*desc = "([^"]+)",%s*mode = ({ [^}]+ })')
      if lhs then
        -- Extract all modes from the table and create multiple keymaps
        local keymaps_to_add = {}
        for mode in modes:gmatch('"([^"]+)"') do
          table.insert(keymaps_to_add, {
            lhs = lhs,
            rhs = "",
            desc = desc,
            mode = mode,
            source = file,
            plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
            plugin_disabled = current_plugin_disabled,
            line_number = line_num,
          })
        end
        -- Return a special marker to indicate multiple keymaps need to be added
        return { multiple = keymaps_to_add }
      end
    end,

    function()
      local lhs, rhs, desc, mode = line:match('{ "([^"]+)",%s*"([^"]+)",%s*desc = "([^"]+)",%s*mode = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = mode,
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local lhs, rhs, mode, desc = line:match('{ "([^"]+)",%s*"([^"]+)",%s*mode = "([^"]+)",%s*desc = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = mode,
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local lhs, rhs, mode, desc = line:match('{ "([^"]+)",%s*\'([^\']+)\',%s*mode = "([^"]+)",%s*desc = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = mode,
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local lhs, rhs, desc = line:match('{ "([^"]+)",%s*\'([^\']+)\',%s*desc = "([^"]+)" }')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = "n",
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local lhs, func, desc, modes =
        line:match('{ "([^"]+)",%s*(function%([^)]*%).-end),%s*desc = "([^"]+)",%s*mode = ({ [^}]+ })')
      if lhs then
        local mode_list = modes:match('{ "([^"]+)"') or "n"
        return {
          lhs = lhs,
          rhs = func,
          desc = desc,
          mode = mode_list,
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local mode, lhs, rhs, desc = line:match('vim%.keymap%.set%("([^"]+)", "([^"]+)", "([^"]+)".-desc = "([^"]+)"')
      if mode and lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = mode,
          source = file,
          plugin = in_config_function and config_function_plugin or nil,
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,

    function()
      local mode, lhs, func, desc =
        line:match('vim%.keymap%.set%("([^"]+)", "([^"]+)", (function%([^)]*%).-end).-desc = "([^"]+)"')
      if mode and lhs then
        return {
          lhs = lhs,
          rhs = func,
          desc = desc,
          mode = mode,
          source = file,
          plugin = in_config_function and config_function_plugin or nil,
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,

    function()
      local lhs, rhs, desc = line:match('vim%.keymap%.set%("", "([^"]+)", "([^"]+)".-desc = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = "n",
          source = file,
          plugin = in_config_function and config_function_plugin or nil,
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,

    function()
      local mode, lhs, rhs, desc = line:match('vim%.keymap%.set%("([^"]*)", "([^"]+)", "([^"]+)".-desc = "([^"]+)"')
      if mode and lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = mode == "" and "n" or mode,
          source = file,
          plugin = in_config_function and config_function_plugin or nil,
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,

    function()
      local lhs, rhs, desc = line:match('{ "([^"]+)",%s*"([^"]+)",%s*desc = "([^"]+)",%s*remap = true }')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = "n",
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local lsp_action, lsp_key = line:match('([%w_]+)%s*=%s*"([^"]+)"')
      if
        lsp_action
        and lsp_key
        and file:match("lsp%.lua")
        and not line:match("desc%s*=")
        and (lsp_key:match("^<") or lsp_key:match("^%[") or lsp_key:match("^g") or lsp_key:match("^K$"))
      then
        return {
          lhs = lsp_key,
          rhs = lsp_action,
          desc = "LSP: " .. lsp_action:gsub("_", " "):gsub("(%l)(%w*)", function(f, r)
            return string.upper(f) .. r
          end),
          mode = "n",
          source = file,
          plugin = "LSP",
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,

    function()
      local cmp_key, cmp_actions = line:match('%["([^"]+)"%]%s*=%s*{([^}]+)}')
      if cmp_key and cmp_actions and file:match("coding%.lua") then
        local desc = "Completion: " .. cmp_actions:gsub('"', ""):gsub(",", ", ")
        desc = utils.normalize_description(desc)
        return {
          lhs = cmp_key,
          rhs = cmp_actions,
          desc = desc,
          mode = "i",
          source = file,
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
        }
      end
    end,

    function()
      local mode, lhs, rhs, desc = line:match('map%("([^"]+)", "([^"]+)", (["\'][^"\']+["\']).*desc = "([^"]+)"')
      if mode and lhs then
        rhs = rhs:gsub("^[\"']", ""):gsub("[\"']$", "")
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = mode,
          source = file,
          plugin = nil,
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,

    function()
      local modes, lhs, rhs, desc = line:match('map%({([^}]+)}, "([^"]+)", (["\'][^"\']+["\']).*desc = "([^"]+)"')
      if modes and lhs then
        local first_mode = modes:match('"([^"]+)"')
        rhs = rhs:gsub("^[\"']", ""):gsub("[\"']$", "")
        if first_mode then
          return {
            lhs = lhs,
            rhs = rhs,
            desc = desc,
            mode = first_mode,
            source = file,
            plugin = nil,
            plugin_disabled = false,
            line_number = line_num,
          }
        end
      end
    end,

    function()
      local mode, lhs, func_name, desc =
        line:match('vim%.keymap%.set%("([^"]+)", "([^"]+)", ([%w_]+),%s*{.*desc = "([^"]+)"')
      if mode and lhs and func_name then
        return {
          lhs = lhs,
          rhs = func_name,
          desc = desc,
          mode = mode,
          source = file,
          plugin = in_config_function and config_function_plugin or nil,
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,

    function()
      local mode, lhs, desc = line:match('map%("([^"]+)", "([^"]+)", function%(%).*desc = "([^"]+)"')
      if mode and lhs then
        return {
          lhs = lhs,
          rhs = "function",
          desc = desc,
          mode = mode,
          source = file,
          plugin = nil,
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,

    function()
      -- Handle map() with function reference: map("n", "<leader>gp", copy_github_pr_url, { desc = "..." })
      local mode, lhs, func_name, desc = line:match('map%("([^"]+)", "([^"]+)", ([%w_]+), { desc = "([^"]+)"')
      if mode and lhs and func_name then
        return {
          lhs = lhs,
          rhs = func_name,
          desc = desc,
          mode = mode,
          source = file,
          plugin = nil,
          plugin_disabled = false,
          line_number = line_num,
        }
      end
    end,
  }

  for _, pattern_func in ipairs(patterns) do
    local keymap = pattern_func()
    if keymap then
      -- Check if this is a multiple keymaps case
      if keymap.multiple then
        -- Add all keymaps from the multiple array
        for _, km in ipairs(keymap.multiple) do
          table.insert(keymaps, km)
        end
      else
        -- Single keymap, add normally
        table.insert(keymaps, keymap)
      end
      break
    end
  end
end

--- Scans installed plugin directories for lazy.lua files and parses keymaps
-- @return table List of keymaps found in installed plugins
function M._scan_installed_plugin_directories()
  local plugin_keymaps = {}

  -- Get the lazy plugin installation directory
  local lazy_path = vim.fn.stdpath("data") .. "/lazy"

  -- Check if lazy directory exists
  if vim.fn.isdirectory(lazy_path) == 0 then
    return plugin_keymaps
  end

  -- Get list of installed plugins
  local plugins_cmd = "find " .. vim.fn.shellescape(lazy_path) .. " -maxdepth 1 -type d 2>/dev/null"
  local success, plugins_handle = pcall(io.popen, plugins_cmd)
  if not success or not plugins_handle then
    return plugin_keymaps
  end

  local plugin_dirs = {}
  local dir_success, _ = pcall(function()
    for plugin_dir in plugins_handle:lines() do
      -- Skip the lazy directory itself
      if plugin_dir ~= lazy_path then
        table.insert(plugin_dirs, plugin_dir)
      end
    end
  end)
  plugins_handle:close()

  if not dir_success then
    return plugin_keymaps
  end

  -- For each plugin directory, check for lazy.lua file
  for _, plugin_dir in ipairs(plugin_dirs) do
    local lazy_file = plugin_dir .. "/lazy.lua"
    if vim.fn.filereadable(lazy_file) == 1 then
      local plugin_name = vim.fn.fnamemodify(plugin_dir, ":t")
      local file_keymaps = M._parse_installed_plugin_file(lazy_file, plugin_name)
      for _, keymap in ipairs(file_keymaps) do
        table.insert(plugin_keymaps, keymap)
      end
    end
  end

  return plugin_keymaps
end

--- Parses a lazy.lua file from an installed plugin directory
-- @param file string Path to the lazy.lua file
-- @param plugin_name string Name of the plugin directory
-- @return table List of keymaps found in the file
function M._parse_installed_plugin_file(file, plugin_name)
  local keymaps = {}

  -- Get plugin repository information
  local repo_info = M._get_plugin_repo_info(plugin_name)

  local success, f = pcall(io.open, file, "r")
  if not success or not f then
    return keymaps
  end
  f:close()

  local current_plugin = nil
  local current_plugin_disabled = false
  local in_keys_section = false
  local keys_section_plugin = nil
  local keys_section_locked = false
  local keys_section_depth = 0
  local brace_depth = 0
  local main_plugin = nil
  local main_plugin_depth = 0
  local plugin_stack = {}

  local multiline_keymap = nil
  local multiline_lhs = nil
  local multiline_line_num = nil
  local multiline_mode = nil

  local line_num = 1
  local line_success, lines_iter = pcall(io.lines, file)
  if not line_success then
    return keymaps
  end

  for line in lines_iter do
    local open_braces = select(2, line:gsub("{", ""))
    local close_braces = select(2, line:gsub("}", ""))
    brace_depth = brace_depth + open_braces - close_braces

    current_plugin, main_plugin, main_plugin_depth, current_plugin_disabled, in_keys_section, keys_section_plugin, keys_section_locked, keys_section_depth =
      M._update_plugin_context(
        line,
        brace_depth,
        plugin_stack,
        current_plugin,
        main_plugin,
        main_plugin_depth,
        current_plugin_disabled,
        in_keys_section,
        keys_section_plugin,
        keys_section_locked,
        keys_section_depth
      )

    -- Handle multiline keymaps (same logic as original _parse_file)
    if multiline_keymap then
      local desc = line:match('desc = "([^"]+)"')
      if desc then
        table.insert(keymaps, {
          lhs = multiline_lhs,
          rhs = "function",
          desc = desc,
          mode = multiline_mode or "n",
          source = M._format_plugin_source(file, repo_info),
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = multiline_line_num,
          repo_info = repo_info,
        })
        multiline_keymap = nil
        multiline_lhs = nil
        multiline_line_num = nil
        multiline_mode = nil
      end
    end

    local multiline_start_lhs = line:match('^%s*{ "([^"]+)",%s*$')
    if multiline_start_lhs and in_keys_section then
      multiline_keymap = true
      multiline_lhs = multiline_start_lhs
      multiline_line_num = line_num
    end

    if line:match("^%s*{%s*$") and in_keys_section then
      multiline_keymap = "starting"
      multiline_line_num = line_num
    end

    if multiline_keymap == "starting" then
      local key_line_lhs = line:match('^%s*"([^"]+)",%s*$')
      if key_line_lhs then
        multiline_keymap = true
        multiline_lhs = key_line_lhs
        multiline_line_num = line_num
      end
    end

    local map_mode, map_lhs = line:match("^%s*map%([\"']([^\"']+)[\"'],%s*[\"']([^\"']+)[\"'],%s*function%(%)%s*$")
    if map_mode and map_lhs then
      multiline_keymap = true
      multiline_lhs = map_lhs
      multiline_mode = map_mode
      multiline_line_num = line_num
    end

    local vks_mode, vks_lhs =
      line:match("^%s*vim%.keymap%.set%([\"']([^\"']+)[\"'],%s*[\"']([^\"']+)[\"'],%s*function%(%)%s*$")
    if vks_mode and vks_lhs then
      multiline_keymap = true
      multiline_lhs = vks_lhs
      multiline_mode = vks_mode
      multiline_line_num = line_num
    end

    -- Parse keymap patterns using the same logic as original
    M._parse_keymap_patterns_for_plugin(
      line,
      line_num,
      file,
      keymaps,
      in_keys_section,
      current_plugin,
      keys_section_plugin,
      main_plugin,
      current_plugin_disabled,
      repo_info
    )

    line_num = line_num + 1
  end

  return keymaps
end

--- Parses keymap patterns for installed plugin files with plugin repository information
-- @param line string Line to parse
-- @param line_num number Line number
-- @param file string Source file path
-- @param keymaps table List to add parsed keymaps to
-- @param in_keys_section boolean Whether currently in a keys section
-- @param current_plugin string Current plugin name
-- @param keys_section_plugin string Plugin owning the keys section
-- @param main_plugin string Main plugin for this section
-- @param current_plugin_disabled boolean Whether current plugin is disabled
-- @param repo_info table Repository information for the plugin
function M._parse_keymap_patterns_for_plugin(
  line,
  line_num,
  file,
  keymaps,
  in_keys_section,
  current_plugin,
  keys_section_plugin,
  main_plugin,
  current_plugin_disabled,
  repo_info
)
  -- Use the same pattern parsing logic as the original function, but with plugin repo attribution
  local patterns = {
    function()
      local lhs, rhs, desc = line:match('{ "([^"]+)",%s*"([^"]+)",%s*desc = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = "n",
          source = M._format_plugin_source(file, repo_info),
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
          repo_info = repo_info,
        }
      end
    end,

    function()
      local lhs, func, desc = line:match('{ "([^"]+)",%s*(function%([^)]*%).-end),%s*desc = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = func,
          desc = desc,
          mode = "n",
          source = M._format_plugin_source(file, repo_info),
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
          repo_info = repo_info,
        }
      end
    end,

    function()
      local lhs, desc = line:match('{ "([^"]+)",%s*desc = "([^"]+)" }')
      if lhs then
        return {
          lhs = lhs,
          rhs = "",
          desc = desc,
          mode = "n",
          source = M._format_plugin_source(file, repo_info),
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
          repo_info = repo_info,
        }
      end
    end,

    function()
      local lhs, rhs, desc, mode = line:match('{ "([^"]+)",%s*"([^"]+)",%s*desc = "([^"]+)",%s*mode = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = mode,
          source = M._format_plugin_source(file, repo_info),
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
          repo_info = repo_info,
        }
      end
    end,

    function()
      local lhs, rhs, mode, desc = line:match('{ "([^"]+)",%s*"([^"]+)",%s*mode = "([^"]+)",%s*desc = "([^"]+)"')
      if lhs then
        return {
          lhs = lhs,
          rhs = rhs,
          desc = desc,
          mode = mode,
          source = M._format_plugin_source(file, repo_info),
          plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
          plugin_disabled = current_plugin_disabled,
          line_number = line_num,
          repo_info = repo_info,
        }
      end
    end,
  }

  for _, pattern_func in ipairs(patterns) do
    local keymap = pattern_func()
    if keymap then
      -- Check if this is a multiple keymaps case
      if keymap.multiple then
        -- Add all keymaps from the multiple array
        for _, km in ipairs(keymap.multiple) do
          table.insert(keymaps, km)
        end
      else
        -- Single keymap, add normally
        table.insert(keymaps, keymap)
      end
      break
    end
  end
end

--- Gets repository information for a plugin
-- @param plugin_name string Name of the plugin
-- @return table|nil Repository information or nil if not available
function M._get_plugin_repo_info(plugin_name)
  -- Try to get repository information from the plugin's git directory
  local plugin_dir = vim.fn.stdpath("data") .. "/lazy/" .. plugin_name

  if vim.fn.isdirectory(plugin_dir) == 0 then
    return nil
  end

  -- Get git remote URL from the plugin directory
  local git_dir = plugin_dir .. "/.git"
  if vim.fn.isdirectory(git_dir) == 0 then
    return nil
  end

  -- Read the git remote URL
  local cmd = "cd " .. vim.fn.shellescape(plugin_dir) .. " && git remote get-url origin 2>/dev/null"
  local success, handle = pcall(io.popen, cmd)
  if not success or not handle then
    return nil
  end

  local read_success, remote_url = pcall(function()
    return handle:read("*line")
  end)
  handle:close()

  if not read_success or not remote_url or remote_url == "" then
    return nil
  end

  -- Convert git URL to GitHub HTTPS URL
  local github_url
  if remote_url:match("^git@github%.com:") then
    github_url = remote_url:gsub("^git@github%.com:", "https://github.com/"):gsub("%.git$", "")
  elseif remote_url:match("^https://github%.com/") then
    github_url = remote_url:gsub("%.git$", "")
  else
    return nil
  end

  return {
    url = remote_url,
    github_url = github_url,
    name = plugin_name,
  }
end

--- Formats the source path for plugin files to include repository information
-- @param file string Local file path
-- @param repo_info table|nil Repository information
-- @return string Formatted source path
function M._format_plugin_source(file, repo_info)
  if repo_info and repo_info.github_url then
    -- Return a format that utils.format_source_with_links can recognize as a plugin source
    return repo_info.github_url .. "/lazy.lua"
  else
    -- Fallback to local file path
    return file
  end
end

return M
