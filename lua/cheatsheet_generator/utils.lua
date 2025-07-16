--- Utility functions for cheatsheet generation
-- @module cheatsheet_generator.utils

local M = {}

--- Determines the source location of a keymap
-- @param keymap table The keymap object from nvim_get_keymap
-- @return string The source description
function M.get_keymap_source(keymap)
    if keymap.sid and keymap.sid == -1 then
        return "Built-in Neovim default"
    end

    local info
    if type(keymap.callback) == "function" then
        info = debug.getinfo(keymap.callback, "S")
    elseif type(keymap.rhs) == "string" and keymap.rhs:match("^:lua") then
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
                if source:match("/lua/config/keymaps%.lua$") then
                    return "lua/config/keymaps.lua"
                end
                return source
            end
        elseif source:sub(1, 1) == "=" then
            return source:sub(2)
        end
    end

    return "lua/config/keymaps.lua"
end

--- Normalizes a keymap LHS by replacing leader keys and cleaning up formatting
-- @param lhs string The left-hand side of the keymap
-- @return string The normalized keymap
function M.normalize_keymap(lhs)
    local leader = vim.g.mapleader or "\\"
    local localleader = vim.g.maplocalleader or "\\"

    lhs = lhs:gsub("^<silent>%s*", "")
    lhs = lhs:gsub("<[Ll]ocal[Ll]eader>", "<leader>")

    lhs = lhs:gsub(vim.pesc(leader), "<leader>")
    lhs = lhs:gsub(vim.pesc(localleader), "<leader>")
    lhs = lhs:gsub("<[Ll]eader>", "<leader>")

    return lhs
end

--- Normalizes a keymap description by cleaning formatting and converting case
-- @param desc string The description to normalize
-- @return string The normalized description
function M.normalize_description(desc)
    desc = desc:gsub("%s+", " ")
    desc = desc:gsub("^%s+", "")
    desc = desc:gsub("%s+$", "")

    desc = desc:gsub(", ", "/")

    desc = desc:gsub("([%w]+)_([%w]+)", function(first, rest)
        local first_title = first:gsub("^%l", string.upper)
        local rest_title = rest:gsub("_", " "):gsub("(%l)(%w*)", function(f, r)
            return string.upper(f) .. r
        end)
        return first_title .. " " .. rest_title
    end)

    desc = desc:gsub("(%w)_(%w)", function(before, after)
        return before .. " " .. after
    end)

    desc = desc:gsub("/(%l)", function(letter)
        return "/" .. string.upper(letter)
    end)

    desc = desc:gsub("^(%l)", string.upper)

    return desc
end

--- Gets GitHub repository information from git remote
-- @param config table Optional configuration containing github info
-- @return table|nil GitHub info with url and branch, or nil if not a GitHub repo
function M.get_github_info(config)
    if config and config.output and config.output.github_info then
        return config.output.github_info
    end

    local success, handle = pcall(io.popen, "git remote get-url origin 2>/dev/null")
    if not success or not handle then
        return nil
    end

    local read_success, remote_url = pcall(function()
        return handle:read("*line")
    end)
    
    local close_success = pcall(function()
        handle:close()
    end)
    
    if not read_success or not remote_url or remote_url == "" then
        return nil
    end

    local github_url
    if remote_url:match("^git@github%.com:") then
        github_url = remote_url:gsub("^git@github%.com:", "https://github.com/"):gsub("%.git$", "")
    elseif remote_url:match("^https://github%.com/") then
        github_url = remote_url:gsub("%.git$", "")
    else
        return nil
    end

    local branch = "main"

    return {
        url = github_url,
        branch = branch,
    }
end

--- Formats a source path with GitHub links if available
-- @param source string The source file path
-- @param github_info table|nil GitHub repository information
-- @param line_number number|nil Line number for the link
-- @return string Formatted source with link if applicable
function M.format_source_with_links(source, github_info, line_number)
    if source == "Built-in Neovim default" then
        return "<sub>" .. source .. "</sub>"
    end

    if not source then
        return source
    end

    if source:match("%.lua$") or source:match("^lua/") or source:match("^ftplugin/") then
        if github_info then
            local link_url = github_info.url .. "/blob/" .. github_info.branch .. "/" .. source
            if line_number and line_number > 0 then
                link_url = link_url .. "#L" .. line_number
                return "[`" .. source .. ":" .. line_number .. "`](" .. link_url .. ")"
            else
                return "[`" .. source .. "`](" .. link_url .. ")"
            end
        end
    end

    return source
end

--- Consolidates keymaps with same keymap/description/source
-- @param keymaps table List of keymaps to consolidate
-- @return table Consolidated keymaps with combined modes
function M.consolidate_keymaps(keymaps)
    local consolidated = {}
    local keymap_groups = {}
    local essential_order_map = {}

    for i, km in ipairs(keymaps) do
        if km.built_in_section and km.built_in_order then
            essential_order_map[km.keymap .. "|" .. km.source] = km.built_in_order
        end
    end

    local base_groups = {}
    for _, km in ipairs(keymaps) do
        local base_key = km.keymap .. "|" .. km.source .. "|" .. (km.plugin or "")
        if not base_groups[base_key] then
            base_groups[base_key] = {}
        end
        table.insert(base_groups[base_key], km)
    end

    for _, group_keymaps in pairs(base_groups) do
        if #group_keymaps == 1 then
            local km = group_keymaps[1]
            local key = km.keymap .. "|" .. km.description .. "|" .. km.source .. "|" .. (km.plugin or "")
            keymap_groups[key] = {
                keymap = km.keymap,
                description = km.description,
                source = km.source,
                plugin = km.plugin,
                plugin_disabled = km.plugin_disabled,
                built_in_section = km.built_in_section,
                built_in_order = km.built_in_order,
                line_number = km.line_number,
                manual_order = km.manual_order,
                modes = { km.mode },
            }
        else
            local descriptions = {}
            local modes = {}
            local normal_desc = nil
            local visual_desc = nil

            for _, km in ipairs(group_keymaps) do
                table.insert(modes, km.mode)
                if km.mode == "n" then
                    normal_desc = km.description
                elseif km.mode == "v" then
                    visual_desc = km.description
                else
                    table.insert(descriptions, km.description)
                end
            end

            local all_descriptions = {}
            if normal_desc then
                table.insert(all_descriptions, normal_desc)
            end
            if visual_desc and visual_desc ~= normal_desc then
                table.insert(all_descriptions, visual_desc)
            end
            for _, desc in ipairs(descriptions) do
                local duplicate = false
                for _, existing in ipairs(all_descriptions) do
                    if desc == existing then
                        duplicate = true
                        break
                    end
                end
                if not duplicate then
                    table.insert(all_descriptions, desc)
                end
            end

            local combined_desc = table.concat(all_descriptions, "/")

            local km = group_keymaps[1] -- Use first keymap as template
            local key = km.keymap .. "|" .. combined_desc .. "|" .. km.source .. "|" .. (km.plugin or "")
            keymap_groups[key] = {
                keymap = km.keymap,
                description = combined_desc,
                source = km.source,
                plugin = km.plugin,
                plugin_disabled = km.plugin_disabled,
                built_in_section = km.built_in_section,
                built_in_order = km.built_in_order,
                line_number = km.line_number,
                manual_order = km.manual_order,
                modes = modes,
            }
        end
    end

    for _, group in pairs(keymap_groups) do
        local unique_modes = {}
        local mode_set = {}
        for _, mode in ipairs(group.modes) do
            if not mode_set[mode] then
                mode_set[mode] = true
                table.insert(unique_modes, mode)
            end
        end
        table.sort(unique_modes)

        table.insert(consolidated, {
            keymap = group.keymap,
            description = group.description,
            source = group.source,
            plugin = group.plugin,
            plugin_disabled = group.plugin_disabled,
            built_in_section = group.built_in_section,
            built_in_order = group.built_in_order,
            line_number = group.line_number,
            manual_order = group.manual_order,
            mode = table.concat(unique_modes, ","),
        })
    end

    return consolidated
end

return M