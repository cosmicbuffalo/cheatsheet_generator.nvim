local M = {}

local function get_keymap_source(keymap)
    -- Check if this is a built-in Neovim keymap
    if keymap.sid and keymap.sid == -1 then
        return "Built-in Neovim default"
    end

    -- For buffer-local keymaps, try to find the actual source location
    local info
    if type(keymap.callback) == "function" then
        info = debug.getinfo(keymap.callback, "S")
    elseif type(keymap.rhs) == "string" and keymap.rhs:match("^:lua") then
        -- Try to extract source from lua command if possible
        local lua_code = keymap.rhs:match("^:lua%s+(.+)")
        if lua_code then
            local func, err = load("return " .. lua_code)
            if func then
                local ok, result = pcall(func)
                if ok and type(result) == "function" then
                    info = debug.getinfo(result, "S")
                end
            end
        end
    end

    if info and info.source then
        local source = info.source
        if source:sub(1, 1) == "@" then
            source = source:sub(2)
            local cwd = vim.fn.getcwd()
            if source:find(cwd, 1, true) == 1 then
                source = source:sub(#cwd + 2)
                return source
            else
                -- Check if this is keymaps.lua from config directory
                for _, config_file in ipairs(vim.tbl_get(M.config, "config_keymap_files") or {}) do
                    if source:match("/" .. config_file:gsub("lua/", ""):gsub("%.lua$", "%.lua$")) then
                        return config_file
                    end
                end
                return source
            end
        elseif source:sub(1, 1) == "=" then
            return source:sub(2)
        end
    end

    -- If we can't determine source, this is likely from keymaps.lua
    return (vim.tbl_get(M.config, "config_keymap_files") or {})[1] or "lua/config/keymaps.lua"
end

local function normalize_keymap(lhs)
    local leader = vim.g.mapleader or "\\"
    local localleader = vim.g.maplocalleader or "\\"

    -- Remove <silent> prefix if present
    lhs = lhs:gsub("^<silent>%s*", "")
    -- change this if we ever end up using an actual localleader key
    lhs = lhs:gsub("<[Ll]ocal[Ll]eader>", "<leader>")

    -- Normalize leader key
    lhs = lhs:gsub(vim.pesc(leader), "<leader>")
    lhs = lhs:gsub(vim.pesc(localleader), "<leader>")
    lhs = lhs:gsub("<[Ll]eader>", "<leader>")

    return lhs
end

local function normalize_description(desc)
    -- Clean up multiple spaces
    desc = desc:gsub("%s+", " ")
    desc = desc:gsub("^%s+", "")
    desc = desc:gsub("%s+$", "")

    -- Replace comma+space with /
    desc = desc:gsub(", ", "/")

    -- Convert snake_case to Title Case with spaces
    desc = desc:gsub("([%w]+)_([%w]+)", function(first, rest)
        -- Convert to title case with spaces
        local first_title = first:gsub("^%l", string.upper)
        local rest_title = rest:gsub("_", " "):gsub("(%l)(%w*)", function(f, r)
            return string.upper(f) .. r
        end)
        return first_title .. " " .. rest_title
    end)

    desc = desc:gsub("(%w)_(%w)", function(before, after)
        return before .. " " .. after
    end)

    -- Fix capitalization after /
    desc = desc:gsub("/(%l)", function(letter)
        return "/" .. string.upper(letter)
    end)

    return desc
end

local function find_files_in_directory(dir, pattern)
    local files = {}
    local handle = io.popen("find " .. dir .. " -name '" .. pattern .. "' -type f 2>/dev/null")
    if handle then
        for file in handle:lines() do
            table.insert(files, file)
        end
        handle:close()
    end
    return files
end

local function parse_plugin_keymaps(config)
    local plugin_keymaps = {}
    local plugin_files = {}

    -- Add all files from configured plugin directories
    for _, plugin_dir in ipairs(config.plugin_dirs or {}) do
        local files = find_files_in_directory(plugin_dir, "*.lua")
        for _, file in ipairs(files) do
            table.insert(plugin_files, file)
        end
    end

    -- Add all files from ftplugin directory
    if config.ftplugin_dir then
        local files = find_files_in_directory(config.ftplugin_dir, "*.lua")
        for _, file in ipairs(files) do
            table.insert(plugin_files, file)
        end
    end

    -- Add config keymap files
    for _, config_file in ipairs(config.config_keymap_files or {}) do
        table.insert(plugin_files, config_file)
    end

    for _, file in ipairs(plugin_files) do
        local full_path = file
        local f = io.open(full_path, "r")
        if f then
            f:close()

            -- Track current plugin name and status for plugin-specific groupings
            local current_plugin = nil
            local current_plugin_disabled = false
            local in_keys_section = false
            local keys_section_plugin = nil
            local keys_section_locked = false
            local brace_depth = 0
            local plugin_start_depth = 0
            local main_plugin = nil
            local main_plugin_depth = 0
            local plugin_stack = {} -- Track plugin hierarchy by depth

            -- Multi-line keymap tracking
            local multiline_keymap = nil
            local multiline_lhs = nil
            local multiline_desc = nil
            local multiline_line_num = nil

            local line_num = 1
            for line in io.lines(full_path) do
                -- Track brace depth to understand nested structures
                local open_braces = select(2, line:gsub("{", ""))
                local close_braces = select(2, line:gsub("}", ""))
                brace_depth = brace_depth + open_braces - close_braces

                -- Detect plugin name from lazy plugin specs (GitHub-style author/repo)
                local plugin_name = line:match('"([%w%-_%.]+/[%w%-_%.]+)"') or line:match("'([%w%-_%.]+/[%w%-_%.]+)'")
                if plugin_name and not keys_section_locked then
                    current_plugin = plugin_name:match("([^/]+)$") -- Extract just the plugin name

                    -- Store plugin at current depth
                    plugin_stack[brace_depth] = current_plugin

                    -- If this is a top-level plugin (depth 2 in a return { } structure), it's a main plugin
                    if brace_depth == 2 then
                        main_plugin = current_plugin
                        main_plugin_depth = brace_depth
                        current_plugin_disabled = false
                        in_keys_section = false
                    end
                end

                -- Detect if plugin is disabled (only at top level of plugin spec)
                if line:match("^%s*enabled%s*=%s*false") and brace_depth == 3 and main_plugin then
                    current_plugin_disabled = true
                end

                -- Detect entering keys section
                if line:match("keys%s*=") then
                    in_keys_section = true
                    -- Keys belong to the closest plugin that contains them
                    keys_section_plugin = current_plugin
                    if not keys_section_plugin then
                        -- If no immediate plugin, find the plugin that owns this keys section
                        for depth = brace_depth - 1, 1, -1 do
                            if plugin_stack[depth] then
                                keys_section_plugin = plugin_stack[depth]
                                break
                            end
                        end
                    end

                    -- Don't allow further plugin changes while in keys section
                    keys_section_locked = true
                end

                -- Reset keys section when we exit it
                if in_keys_section and not line:match("keys%s*=") and not line:match("^%s*{") and not line:match("^%s*%[") then
                    local open_braces = select(2, line:gsub("{", ""))
                    local close_braces = select(2, line:gsub("}", ""))
                    if close_braces > open_braces and (line:match("},%s*$") or line:match("}%s*$")) then
                        in_keys_section = false
                        keys_section_plugin = nil
                        keys_section_locked = false
                    end
                end

                -- Reset plugin context when we exit any plugin scope
                for depth = brace_depth + 1, 10 do
                    plugin_stack[depth] = nil
                end

                if current_plugin and plugin_stack[brace_depth] ~= current_plugin then
                    current_plugin = plugin_stack[brace_depth]
                end

                -- Reset plugin context only when we exit the main plugin table
                if brace_depth < main_plugin_depth and main_plugin then
                    main_plugin = nil
                    main_plugin_depth = 0
                    current_plugin = nil
                    current_plugin_disabled = false
                    in_keys_section = false
                    keys_section_plugin = nil
                    keys_section_locked = false
                    plugin_start_depth = 0
                end

                -- Handle multi-line keymap collection
                if multiline_keymap then
                    local desc = line:match('desc = "([^"]+)"')
                    if desc then
                        table.insert(plugin_keymaps, {
                            lhs = multiline_lhs,
                            rhs = "function",
                            desc = desc,
                            mode = "n",
                            source = file,
                            plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
                            plugin_disabled = current_plugin_disabled,
                            line_number = multiline_line_num,
                        })
                        multiline_keymap = nil
                        multiline_lhs = nil
                        multiline_desc = nil
                        multiline_line_num = nil
                    end
                end

                -- Check for start of multi-line keymap definition
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

                -- Parse various keymap patterns (simplified - add all your patterns here)
                -- Pattern 1: { "key", "command", desc = "description" }
                local lhs, rhs, desc = line:match('{ "([^"]+)",%s*"([^"]+)",%s*desc = "([^"]+)"')
                if lhs then
                    table.insert(plugin_keymaps, {
                        lhs = lhs,
                        rhs = rhs,
                        desc = desc,
                        mode = "n",
                        source = file,
                        plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
                        plugin_disabled = current_plugin_disabled,
                        line_number = line_num,
                    })
                end

                -- Add more patterns here as needed from your original script...

                line_num = line_num + 1
            end
        end
    end

    -- Apply plugin-specific fixes if configured
    if config.plugin_fixes then
        for plugin_name, fix in pairs(config.plugin_fixes) do
            for _, keymap in ipairs(plugin_keymaps) do
                if keymap.lhs == fix.keymap and keymap.source == fix.source then
                    keymap.plugin = plugin_name
                end
            end
        end
    end

    return plugin_keymaps
end

function M.generate(config)
    M.config = config -- Store config for use in other functions
    
    -- Load core configuration without plugins (if specified)
    if config.load_config then
        for _, module in ipairs(config.load_config) do
            require(module)
        end
    end

    print("Loading configuration and collecting all keymaps...")
    local keymaps = {} -- This would call your collect_all_keymaps function
    print("Found " .. #keymaps .. " keymaps")

    print("Generating markdown...")
    local markdown = "" -- This would call your generate_markdown function
    
    local output_file = config.output.file or "CHEATSHEET.md"
    local file = io.open(output_file, "w")
    if file then
        file:write(markdown)
        file:close()
        print("Cheatsheet written to " .. output_file)
        return true
    else
        error("Could not write to " .. output_file)
    end
end

return M