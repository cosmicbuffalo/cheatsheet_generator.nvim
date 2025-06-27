local M = {}

local function get_github_info(config)
    if not config.git or not config.git.enabled then
        return nil
    end

    -- Get the git remote URL
    local handle = io.popen("git remote get-url origin 2>/dev/null")
    if not handle then
        return nil
    end

    local remote_url = handle:read("*line")
    handle:close()

    if not remote_url then
        return nil
    end

    -- Use configured base URL if provided
    if config.git.base_url then
        return {
            url = config.git.base_url,
            branch = config.git.default_branch or "main",
        }
    end

    -- Convert SSH URL to HTTPS format for web links
    local github_url
    if remote_url:match("^git@github%.com:") then
        github_url = remote_url:gsub("^git@github%.com:", "https://github.com/"):gsub("%.git$", "")
    elseif remote_url:match("^https://github%.com/") then
        github_url = remote_url:gsub("%.git$", "")
    else
        return nil
    end

    return {
        url = github_url,
        branch = config.git.default_branch or "main",
    }
end

local function format_source_with_links(source, github_info, line_number)
    if source == "Built-in Neovim default" then
        return "<sub>" .. source .. "</sub>"
    end

    if not source then
        return source
    end

    -- Only convert sources that look like file paths
    if source:match("%.lua$") or source:match("^lua/") or source:match("^ftplugin/") then
        if github_info then
            local link_url = github_info.url .. "/blob/" .. github_info.branch .. "/" .. source
            if line_number and line_number > 0 then
                link_url = link_url .. "#L" .. line_number
                return "[" .. source .. ":" .. line_number .. "](" .. link_url .. ")"
            else
                return "[" .. source .. "](" .. link_url .. ")"
            end
        end
    end

    return source
end

local function consolidate_keymaps(keymaps)
    local consolidated = {}
    local keymap_groups = {}

    -- Group keymaps by keymap + source + plugin
    local base_groups = {}
    for _, km in ipairs(keymaps) do
        local base_key = km.keymap .. "|" .. km.source .. "|" .. (km.plugin or "")
        if not base_groups[base_key] then
            base_groups[base_key] = {}
        end
        table.insert(base_groups[base_key], km)
    end

    -- Consolidate descriptions and modes for each group
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
                modes = { km.mode },
            }
        else
            -- Multiple keymaps with same LHS, consolidate
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

            -- Combine descriptions, avoiding duplicates
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
            local km = group_keymaps[1]
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
                modes = modes,
            }
        end
    end

    -- Convert back to list format
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
            mode = table.concat(unique_modes, ","),
        })
    end

    return consolidated
end

function M.generate_section_table(keymaps, title, strip_prefix, is_disabled, config)
    if #keymaps == 0 then
        return {}
    end

    local github_info = get_github_info(config)
    local lines = {
        "",
        "## " .. title,
        "",
    }

    if is_disabled then
        table.insert(lines, "_This plugin is disabled by default and needs to be enabled._")
        table.insert(lines, "")
    end

    table.insert(lines, "| Keymap | Mode | Description | Source |")
    table.insert(lines, "|--------|------|-------------|--------|")

    local consolidated = consolidate_keymaps(keymaps)

    -- Sort keymaps
    local mode_order = { n = 1, i = 2, v = 3, x = 4, s = 5, o = 6, t = 7, c = 8, ["!"] = 9 }
    
    local function get_mode_priority(mode_string)
        local first_mode = mode_string:match("^([^,]+)")
        return mode_order[first_mode] or 99
    end

    local built_in_keymaps = {}
    local plugin_keymaps = {}
    local other_keymaps = {}

    for _, km in ipairs(consolidated) do
        if km.built_in_section then
            table.insert(built_in_keymaps, km)
        elseif km.line_number then
            table.insert(plugin_keymaps, km)
        else
            table.insert(other_keymaps, km)
        end
    end

    -- Sort each category
    table.sort(other_keymaps, function(a, b)
        local a_priority = get_mode_priority(a.mode)
        local b_priority = get_mode_priority(b.mode)
        if a_priority ~= b_priority then
            return a_priority < b_priority
        end
        return a.keymap < b.keymap
    end)

    table.sort(plugin_keymaps, function(a, b)
        if a.source ~= b.source then
            return a.source < b.source
        end
        return (a.line_number or 0) < (b.line_number or 0)
    end)

    table.sort(built_in_keymaps, function(a, b)
        if a.built_in_order and b.built_in_order then
            return a.built_in_order < b.built_in_order
        end
        return a.keymap < b.keymap
    end)

    -- Combine all keymaps
    consolidated = {}
    for _, km in ipairs(built_in_keymaps) do
        table.insert(consolidated, km)
    end
    for _, km in ipairs(plugin_keymaps) do
        table.insert(consolidated, km)
    end
    for _, km in ipairs(other_keymaps) do
        table.insert(consolidated, km)
    end

    -- Generate table rows
    for _, km in ipairs(consolidated) do
        local keymap_escaped = km.keymap:gsub("|", "\\|"):gsub("\n", " ")
        local desc = km.description

        if strip_prefix and desc:match("^" .. strip_prefix) then
            desc = desc:gsub("^" .. strip_prefix .. "%s*", "")
        end

        local desc_escaped = desc:gsub("|", "\\|"):gsub("\n", " ")

        local modes = {}
        for mode in km.mode:gmatch("[^,]+") do
            table.insert(modes, "`" .. mode .. "`")
        end
        local mode_formatted = table.concat(modes, " ")

        local source_formatted = format_source_with_links(km.source, github_info, km.line_number)
        local source_escaped = source_formatted:gsub("|", "\\|"):gsub("\n", " ")
        
        table.insert(
            lines,
            string.format("| `%s` | %s | %s | %s |", keymap_escaped, mode_formatted, desc_escaped, source_escaped)
        )
    end

    return lines
end

return M