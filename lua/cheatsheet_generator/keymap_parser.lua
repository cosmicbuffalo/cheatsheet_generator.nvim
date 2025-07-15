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

    for _, keymap in ipairs(plugin_keymaps) do
        if keymap.lhs == "<leader>uf" and keymap.source == "lua/plugins/editor.lua" then
            keymap.plugin = "eyeliner.nvim"
        end

        if keymap.lhs == "<leader>bD" and keymap.source == "lua/plugins/ui.lua" and 
           (not keymap.plugin or keymap.plugin == "") then
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
        print("Warning: Could not read lines from file: " .. file)
        return keymaps
    end
    
    for line in lines_iter do
        local open_braces = select(2, line:gsub("{", ""))
        local close_braces = select(2, line:gsub("}", ""))
        brace_depth = brace_depth + open_braces - close_braces

        current_plugin, main_plugin, main_plugin_depth, current_plugin_disabled, in_keys_section, keys_section_plugin, keys_section_locked = 
            M._update_plugin_context(line, brace_depth, plugin_stack, current_plugin, main_plugin, main_plugin_depth, current_plugin_disabled, in_keys_section, keys_section_plugin, keys_section_locked)
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

        local map_mode, map_lhs = line:match('^%s*map%(["\']([^"\']+)["\'],%s*["\']([^"\']+)["\'],%s*function%(%)%s*$')
        if map_mode and map_lhs then
            multiline_keymap = true
            multiline_lhs = map_lhs
            multiline_mode = map_mode
            multiline_line_num = line_num
        end

        local vks_mode, vks_lhs = line:match('^%s*vim%.keymap%.set%(["\']([^"\']+)["\'],%s*["\']([^"\']+)["\'],%s*function%(%)%s*$')
        if vks_mode and vks_lhs then
            multiline_keymap = true
            multiline_lhs = vks_lhs
            multiline_mode = vks_mode
            multiline_line_num = line_num
        end

        M._parse_keymap_patterns(line, line_num, file, keymaps, in_keys_section, current_plugin, keys_section_plugin, main_plugin, current_plugin_disabled)

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
-- @return string, string, number, boolean, boolean, string, boolean Updated context variables
function M._update_plugin_context(line, brace_depth, plugin_stack, current_plugin, main_plugin, main_plugin_depth, current_plugin_disabled, in_keys_section, keys_section_plugin, keys_section_locked)
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

    if in_keys_section and not line:match("keys%s*=") and not line:match("^%s*{") and not line:match("^%s*%[") then
        local open_braces = select(2, line:gsub("{", ""))
        local close_braces = select(2, line:gsub("}", ""))
        if close_braces > open_braces and (line:match("},%s*$") or line:match("}%s*$")) then
            in_keys_section = false
            keys_section_plugin = nil
            keys_section_locked = false
        end
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
    end
    
    return current_plugin, main_plugin, main_plugin_depth, current_plugin_disabled, in_keys_section, keys_section_plugin, keys_section_locked
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
function M._parse_keymap_patterns(line, line_num, file, keymaps, in_keys_section, current_plugin, keys_section_plugin, main_plugin, current_plugin_disabled)
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
            local lhs, func, desc, modes = line:match('{ "([^"]+)",%s*(function%([^)]*%).-end),%s*desc = "([^"]+)",%s*mode = ({ [^}]+ })')
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
                    plugin = nil,
                    plugin_disabled = false,
                    line_number = line_num,
                }
            end
        end,

        function()
            local mode, lhs, func, desc = line:match('vim%.keymap%.set%("([^"]+)", "([^"]+)", (function%([^)]*%).-end).-desc = "([^"]+)"')
            if mode and lhs then
                return {
                    lhs = lhs,
                    rhs = func,
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
            local lhs, rhs, desc = line:match('vim%.keymap%.set%("", "([^"]+)", "([^"]+)".-desc = "([^"]+)"')
            if lhs then
                return {
                    lhs = lhs,
                    rhs = rhs,
                    desc = desc,
                    mode = "n",
                    source = file,
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
            if lsp_action and lsp_key and file:match("lsp%.lua") and not line:match("desc%s*=") and 
               (lsp_key:match("^<") or lsp_key:match("^%[") or lsp_key:match("^g") or lsp_key:match("^K$")) then
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
            local mode, lhs, func_name, desc = line:match('vim%.keymap%.set%("([^"]+)", "([^"]+)", ([%w_]+),%s*{.*desc = "([^"]+)"')
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
    }

    for _, pattern_func in ipairs(patterns) do
        local keymap = pattern_func()
        if keymap then
            table.insert(keymaps, keymap)
            break
        end
    end
end


return M
