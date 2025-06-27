--- Markdown formatting module for generating cheatsheet output
-- @module cheatsheet_generator.formatter

local utils = require("cheatsheet_generator.utils")
local M = {}

--- Generates the complete markdown cheatsheet
-- @param keymaps table List of keymaps to format
-- @param config table Configuration object
-- @return string Complete markdown content
function M.generate_markdown(keymaps, config)
    local lines = {}

    if config and config.output and config.output.title then
        table.insert(lines, "# " .. config.output.title)
    else
        table.insert(lines, "# Neovim Keymap Cheatsheet")
    end

    table.insert(lines, "")
    table.insert(lines, "Up to date as of: " .. os.date("%Y-%m-%d"))
    table.insert(lines, "")

    M._add_generation_info(lines, config)

    M._add_mode_legend(lines)

    local categories, prefix_groups = M._categorize_keymaps_by_function(keymaps)

    M._generate_sections(lines, categories, prefix_groups, config)

    return table.concat(lines, "\n")
end

--- Adds generation information to the markdown
-- @param lines table List of lines to add to
-- @param config table Configuration object
function M._add_generation_info(lines, config)
    if config and config.output and config.output.generation_info then
        local info = config.output.generation_info
        local generation_line = "This cheatsheet is automatically generated"
        
        if info.script_path then
            generation_line = generation_line .. " by [" .. info.script_path .. "](" .. info.script_path .. ")"
        end
        
        if info.hook_path then
            generation_line = generation_line .. " via a [pre-commit hook](" .. info.hook_path .. ")"
        end
        
        generation_line = generation_line .. ". It includes all keymaps from:"
        table.insert(lines, generation_line)
    else
        table.insert(lines, "This cheatsheet is automatically generated. It includes all keymaps from:")
    end

    table.insert(lines, "")
    table.insert(lines, "- Built-in Neovim defaults")

    if config and config.config_keymap_files then
        for _, config_file in ipairs(config.config_keymap_files) do
            table.insert(lines, "- Custom configuration in [`" .. config_file .. "`](" .. config_file .. ")")
        end
    else
        table.insert(lines, "- Custom configuration in [`lua/config/keymaps.lua`](lua/config/keymaps.lua)")
    end

    local plugin_dirs = config and config.plugin_dirs or { "lua/plugins" }
    
    for _, plugins_dir in ipairs(plugin_dirs) do
        table.insert(lines, "- Plugin-specific keymaps from [`" .. plugins_dir .. "/`](" .. plugins_dir .. "/)")
    end
    
    local ftplugin_exists = vim.fn.isdirectory("ftplugin") == 1
    if ftplugin_exists then
        table.insert(lines, "- Filetype-specific keymaps from [`ftplugin/`](ftplugin/)")
    end
    table.insert(lines, "")
    
    if config and config.output and config.output.runtime_note and config.output.runtime_note.enabled then
        table.insert(lines, "> [!NOTE]")
        local note_text = "> This cheatsheet does not include keymaps added automatically by configured plugins at runtime, such as those from most legacy vim plugins. To see all keymaps available in your current Neovim session, use the `:map` command"
        
        if config.output.runtime_note.keymap_search then
            note_text = note_text .. ", or the `" .. config.output.runtime_note.keymap_search .. "` keymap to open a fuzzy search for keymaps"
        end
        
        note_text = note_text .. "."
        table.insert(lines, note_text)
        table.insert(lines, "")
    end
end

--- Adds the mode legend table to the markdown
-- @param lines table List of lines to add to
function M._add_mode_legend(lines)
    table.insert(lines, "## Mode Legend")
    table.insert(lines, "")
    table.insert(lines, "| Abbreviation | Mode |")
    table.insert(lines, "|--------------|------|")
    table.insert(lines, "| n | Normal |")
    table.insert(lines, "| i | Insert |")
    table.insert(lines, "| v | Visual and Select |")
    table.insert(lines, "| x | Visual only |")
    table.insert(lines, "| s | Select |")
    table.insert(lines, "| o | Operator-pending |")
    table.insert(lines, "| t | Terminal |")
    table.insert(lines, "| c | Command-line |")
    table.insert(lines, "| ! | Insert & Command-line |")
end

--- Generates all sections of the cheatsheet
-- @param lines table List of lines to add to
-- @param categories table Categorized keymaps
-- @param prefix_groups table Prefix-based groupings
-- @param config table Configuration object
function M._generate_sections(lines, categories, prefix_groups, config)
    local built_in_sections = {}
    local prefix_sections = {}
    local plugin_sections = {}
    local other_sections = {}

    for category, category_data in pairs(categories) do
        if category_data.is_built_in then
            table.insert(built_in_sections, category)
        elseif category:match("^Plugin: ") then
            table.insert(plugin_sections, category)
        elseif prefix_groups[category] then
            table.insert(prefix_sections, category)
        else
            table.insert(other_sections, category)
        end
    end

    local built_in_order = {
        "mode_changes",
        "motions",
        "edit_operations",
        "default_text_objects",
        "search",
        "insert_mode",
        "visual_mode",
        "macros_and_registers",
        "marks",
        "navigation",
        "folds",
    }

    for _, section_name in ipairs(built_in_order) do
        if categories[section_name] and categories[section_name].is_built_in then
            local category_data = categories[section_name]
            local title = section_name:gsub("_", " "):gsub("(%l)(%w*)", function(f, r)
                return string.upper(f) .. r
            end)
            local section = M._generate_section_table(category_data.keymaps, title, nil, category_data.disabled, config)
            for _, line in ipairs(section) do
                table.insert(lines, line)
            end
        end
    end

    table.sort(prefix_sections)

    for _, prefix in ipairs(prefix_sections) do
        local category_data = categories[prefix]
        local section = M._generate_section_table(category_data.keymaps, prefix, prefix .. ":", category_data.disabled, config)
        for _, line in ipairs(section) do
            table.insert(lines, line)
        end
    end

    table.sort(plugin_sections)

    for _, category in ipairs(plugin_sections) do
        local category_data = categories[category]
        local strip_prefix = nil
        local plugin_name = category:match("^Plugin: (.+)$")
        if plugin_name then
            local potential_prefix = plugin_name:gsub("%.lua$", ""):gsub("^vim%-", ""):gsub("%-", " ")
            potential_prefix = potential_prefix:sub(1, 1):upper() .. potential_prefix:sub(2)

            local prefix_count = 0
            for _, keymap in ipairs(category_data.keymaps) do
                if keymap.description:match("^" .. potential_prefix .. ":") then
                    prefix_count = prefix_count + 1
                end
            end

            if prefix_count > #category_data.keymaps / 2 then
                strip_prefix = potential_prefix .. ":"
            end
        end

        local section = M._generate_section_table(category_data.keymaps, category, strip_prefix, category_data.disabled, config)
        for _, line in ipairs(section) do
            table.insert(lines, line)
        end
    end

    table.sort(other_sections)

    for _, category in ipairs(other_sections) do
        local category_data = categories[category]
        local section = M._generate_section_table(category_data.keymaps, category, nil, category_data.disabled, config)
        for _, line in ipairs(section) do
            table.insert(lines, line)
        end
    end
end

--- Generates a section table for a group of keymaps
-- @param keymaps table List of keymaps for this section
-- @param title string Section title
-- @param strip_prefix string|nil Prefix to strip from descriptions
-- @param is_disabled boolean Whether this is a disabled plugin
-- @param config table Configuration object
-- @return table List of markdown lines for this section
function M._generate_section_table(keymaps, title, strip_prefix, is_disabled, config)
    if #keymaps == 0 then
        return {}
    end

    local github_info = utils.get_github_info(config)

    local lines = {
        "",
        "## " .. title,
        "",
    }

    if is_disabled then
        table.insert(
            lines,
            "_This plugin is disabled by default and needs to be enabled in `neovim-dotfiles-personal` in order to use it._"
        )
        table.insert(lines, "")
    end

    table.insert(lines, "| Keymap | Mode | Description | Source |")
    table.insert(lines, "|--------|------|-------------|--------|")

    local consolidated = utils.consolidate_keymaps(keymaps)

    consolidated = M._sort_consolidated_keymaps(consolidated)

    for _, km in ipairs(consolidated) do
        local keymap_escaped = km.keymap:gsub("|", "\\|"):gsub("\n", " ")
        local desc = km.description

        if strip_prefix and desc:match("^" .. strip_prefix) then
            desc = desc:gsub("^" .. strip_prefix .. "%s*", "")
        end

        desc = desc:gsub("^(%l)", string.upper)

        local desc_escaped = desc:gsub("|", "\\|"):gsub("\n", " ")

        local modes = {}
        for mode in km.mode:gmatch("[^,]+") do
            table.insert(modes, "`" .. mode .. "`")
        end
        local mode_formatted = table.concat(modes, " ")

        local source_formatted = utils.format_source_with_links(km.source, github_info, km.line_number)
        local source_escaped = source_formatted:gsub("|", "\\|"):gsub("\n", " ")
        
        local keymap_formatted
        if km.keymap:match("`") then
            keymap_formatted = "``` " .. keymap_escaped .. " ```"
        else
            keymap_formatted = "`" .. keymap_escaped .. "`"
        end
        
        table.insert(
            lines,
            string.format("| %s | %s | %s | %s |", keymap_formatted, mode_formatted, desc_escaped, source_escaped)
        )
    end

    return lines
end

--- Sorts consolidated keymaps appropriately
-- @param consolidated table List of consolidated keymaps
-- @return table Sorted keymaps
function M._sort_consolidated_keymaps(consolidated)
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
        if a.built_in_order and not b.built_in_order then
            return true
        end
        if not a.built_in_order and b.built_in_order then
            return false
        end
        return a.keymap < b.keymap
    end)

    local result = {}
    for _, km in ipairs(built_in_keymaps) do
        table.insert(result, km)
    end
    for _, km in ipairs(plugin_keymaps) do
        table.insert(result, km)
    end
    for _, km in ipairs(other_keymaps) do
        table.insert(result, km)
    end

    return result
end

--- Categorizes keymaps by function and creates groupings
-- @param keymaps table List of keymaps to categorize
-- @return table, table Categories and prefix groups
function M._categorize_keymaps_by_function(keymaps)
    local categories = {}
    local prefix_groups = {}
    local plugin_groups = {}
    local essential_sections = {}

    local built_in_keymaps = {}
    local non_built_in_keymaps = {}

    for _, keymap in ipairs(keymaps) do
        if keymap.built_in_section then
            table.insert(built_in_keymaps, keymap)

            if not essential_sections[keymap.built_in_section] then
                essential_sections[keymap.built_in_section] = {}
            end
            table.insert(essential_sections[keymap.built_in_section], keymap)
        else
            table.insert(non_built_in_keymaps, keymap)
        end
    end

    for section_name, section_keymaps in pairs(essential_sections) do
        categories[section_name] = {
            keymaps = section_keymaps,
            disabled = false,
            is_built_in = true,
            order = 0,
        }
    end

    for _, keymap in ipairs(non_built_in_keymaps) do
        local desc = keymap.description
        local prefix = desc:match("^([^:]+):")
        local source = keymap.source

        if prefix == "Copilot" then
            if not prefix_groups[prefix] then
                prefix_groups[prefix] = {}
            end
            table.insert(prefix_groups[prefix], keymap)
        elseif source and source:match("^ftplugin/(.+)%.lua$") then
            local filetype = source:match("^ftplugin/(.+)%.lua$")
            local ftplugin_key = filetype:gsub("^%l", string.upper)
            if not plugin_groups[ftplugin_key] then
                plugin_groups[ftplugin_key] = {
                    keymaps = {},
                    disabled = false,
                }
            end
            table.insert(plugin_groups[ftplugin_key].keymaps, keymap)
        elseif keymap.plugin then
            local plugin_key = "Plugin: " .. keymap.plugin
            if not plugin_groups[plugin_key] then
                plugin_groups[plugin_key] = {
                    keymaps = {},
                    disabled = keymap.plugin_disabled or false,
                }
            end
            table.insert(plugin_groups[plugin_key].keymaps, keymap)
        else
            if prefix then
                if not prefix_groups[prefix] then
                    prefix_groups[prefix] = {}
                end
                table.insert(prefix_groups[prefix], keymap)
            end
        end
    end

    for plugin_name, plugin_data in pairs(plugin_groups) do
        if #plugin_data.keymaps > 0 then
            categories[plugin_name] = {
                keymaps = plugin_data.keymaps,
                disabled = plugin_data.disabled,
                is_built_in = false,
                order = 2,
            }
        end
    end

    for prefix, maps in pairs(prefix_groups) do
        if #maps >= 2 then
            categories[prefix] = {
                keymaps = maps,
                disabled = false,
                is_built_in = false,
                order = 2,
            }
        end
    end

    local remaining = {}
    for _, keymap in ipairs(non_built_in_keymaps) do
        local desc = keymap.description
        local prefix = desc:match("^([^:]+):")
        local plugin_key = keymap.plugin and ("Plugin: " .. keymap.plugin) or nil

        local in_copilot_prefix = (prefix == "Copilot" and categories[prefix])
        local in_plugin_group = (plugin_key and categories[plugin_key] and prefix ~= "Copilot")
        local in_other_prefix = (prefix and prefix ~= "Copilot" and categories[prefix])

        local in_ftplugin_group = false
        if keymap.source and keymap.source:match("^ftplugin/(.+)%.lua$") then
            local filetype = keymap.source:match("^ftplugin/(.+)%.lua$")
            local ftplugin_key = filetype:gsub("^%l", string.upper)
            in_ftplugin_group = categories[ftplugin_key] ~= nil
        end

        if not (in_copilot_prefix or in_plugin_group or in_other_prefix or in_ftplugin_group) then
            table.insert(remaining, keymap)
        end
    end

    local functional_categories = {
        ["LSP"] = {},
        ["Miscellaneous"] = {},
    }

    for _, keymap in ipairs(remaining) do
        local lhs = keymap.keymap
        local desc = keymap.description:lower()
        local source = keymap.source

        if source:match("lsp") or desc:match("lsp") or desc:match("diagnostic") or 
           desc:match("signature help") or lhs:match("^gr[arnri]$") or lhs == "gO" or lhs:match("^<C-S>$") then
            table.insert(functional_categories["LSP"], keymap)
        else
            table.insert(functional_categories["Miscellaneous"], keymap)
        end
    end

    for category, maps in pairs(functional_categories) do
        if #maps > 0 then
            categories[category] = {
                keymaps = maps,
                disabled = false,
                is_built_in = false,
                order = 3,
            }
        end
    end

    return categories, prefix_groups
end

return M