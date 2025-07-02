--- Keymap collection module for gathering runtime and built-in keymaps
-- @module cheatsheet_generator.keymap_collector

local utils = require("cheatsheet_generator.utils")
local keymap_parser = require("cheatsheet_generator.keymap_parser")
local M = {}

--- Collects all keymaps from runtime, built-in definitions, and static analysis
-- @param config table Configuration object
-- @return table List of all collected keymaps
function M.collect_all_keymaps(config)
    local all_keymaps = {}

    local built_in_keymaps_ok, built_in_keymaps = pcall(require, "cheatsheet_generator.built_in_keymaps")
    if not built_in_keymaps_ok then
        print("Warning: Could not load cheatsheet_generator.built_in_keymaps, falling back to config.built_in_keymaps")
        built_in_keymaps_ok, built_in_keymaps = pcall(require, "config.built_in_keymaps")
        if not built_in_keymaps_ok then
            print("Warning: Could not load config.built_in_keymaps, falling back to hardcoded built-in keymaps")
            built_in_keymaps = nil
        end
    end

    local modes = { "n", "i", "v", "x", "s", "o", "t", "c" }

    local runtime_keymaps = M._collect_runtime_keymaps(modes)

    local runtime_lookup = {}
    for _, runtime_keymap in ipairs(runtime_keymaps) do
        local key = runtime_keymap.mode .. "|" .. runtime_keymap.keymap
        runtime_lookup[key] = runtime_keymap
    end

    if built_in_keymaps then
        M._process_built_in_keymaps(built_in_keymaps, runtime_lookup, all_keymaps)
    end

    local plugin_keymaps = keymap_parser.parse_plugin_keymaps(config)
    M._add_plugin_keymaps(plugin_keymaps, all_keymaps)

    local deduplicated = M._deduplicate_keymaps(all_keymaps)

    M._add_manual_keymaps(config, deduplicated)

    return deduplicated
end

--- Collects runtime keymaps from Neovim
-- @param modes table List of modes to collect keymaps for
-- @return table List of runtime keymaps
function M._collect_runtime_keymaps(modes)
    local runtime_keymaps = {}

    for _, mode in ipairs(modes) do
        local keymaps = vim.api.nvim_get_keymap(mode)
        for _, keymap in ipairs(keymaps) do
            M._process_single_keymap(keymap, mode, runtime_keymaps, false)
        end

        local buf_keymaps = vim.api.nvim_buf_get_keymap(0, mode)
        for _, keymap in ipairs(buf_keymaps) do
            M._process_single_keymap(keymap, mode, runtime_keymaps, true)
        end
    end

    return runtime_keymaps
end

--- Processes a single keymap and adds it to the runtime keymaps if valid
-- @param keymap table Raw keymap from nvim_get_keymap
-- @param mode string Keymap mode
-- @param runtime_keymaps table List to add processed keymap to
-- @param is_buffer_local boolean Whether this is a buffer-local keymap
function M._process_single_keymap(keymap, mode, runtime_keymaps, is_buffer_local)
    if not keymap.lhs or keymap.lhs == "" then
        return
    end

    local desc = keymap.desc
    if not desc or desc == "" or desc == "No description" then
        desc = keymap.rhs or "No description"
    end

    desc = utils.normalize_description(desc)

    local source = utils.get_keymap_source(keymap)
    local normalized_lhs = utils.normalize_keymap(keymap.lhs)

    if M._should_skip_keymap(source, keymap.lhs, desc) then
        return
    end

    if source == "External: _defaults.lua" then
        source = "Built-in Neovim default"
    end

    table.insert(runtime_keymaps, {
        mode = mode,
        keymap = normalized_lhs,
        description = desc,
        source = source,
        raw_keymap = keymap,
    })
end

--- Checks if a keymap should be skipped based on source and content
-- @param source string Keymap source
-- @param lhs string Left-hand side of keymap
-- @param desc string Keymap description
-- @return boolean True if keymap should be skipped
function M._should_skip_keymap(source, lhs, desc)
    return (source and source:match("lua/personal/")) or
           lhs:match("^<Plug>") or
           desc:match("<Plug>")
end

--- Processes built-in keymaps and adds them to the all_keymaps list
-- @param built_in_keymaps table Built-in keymap definitions
-- @param runtime_lookup table Lookup map for runtime keymaps
-- @param all_keymaps table List to add processed keymaps to
function M._process_built_in_keymaps(built_in_keymaps, runtime_lookup, all_keymaps)
    for section_name, section_keymaps in pairs(built_in_keymaps) do
        for _, built_in_keymap in ipairs(section_keymaps) do
            local normalized_lhs = utils.normalize_keymap(built_in_keymap.lhs)
            local mode = built_in_keymap.mode
            local key = mode .. "|" .. normalized_lhs

            local runtime_override = runtime_lookup[key]

            local final_keymap
            if runtime_override and not (runtime_override.source == "Built-in Neovim default") then
                local should_use_override = true

                if runtime_override.description and runtime_override.description:match("^:help") then
                    should_use_override = false
                end

                if should_use_override then
                    final_keymap = {
                        mode = runtime_override.mode,
                        keymap = runtime_override.keymap,
                        description = runtime_override.description,
                        source = runtime_override.source,
                        raw_keymap = runtime_override.raw_keymap,
                        built_in_section = section_name,
                        built_in_order = #all_keymaps + 1,
                    }
                else
                    local description = built_in_keymap.desc or "No description"
                    description = utils.normalize_description(description)

                    final_keymap = {
                        mode = mode,
                        keymap = normalized_lhs,
                        description = description,
                        source = "Built-in Neovim default",
                        raw_keymap = { lhs = built_in_keymap.lhs, desc = built_in_keymap.desc, rhs = "" },
                        built_in_section = section_name,
                        built_in_order = #all_keymaps + 1,
                    }
                end
            else
                local description = built_in_keymap.desc or "No description"
                description = utils.normalize_description(description)

                final_keymap = {
                    mode = mode,
                    keymap = normalized_lhs,
                    description = description,
                    source = "Built-in Neovim default",
                    raw_keymap = { lhs = built_in_keymap.lhs, desc = built_in_keymap.desc, rhs = "" },
                    built_in_section = section_name,
                    built_in_order = #all_keymaps + 1,
                }
            end

            table.insert(all_keymaps, final_keymap)
        end
    end
end

--- Adds plugin keymaps from static analysis to the all_keymaps list
-- @param plugin_keymaps table List of plugin keymaps from static analysis
-- @param all_keymaps table List to add keymaps to
function M._add_plugin_keymaps(plugin_keymaps, all_keymaps)
    for _, plugin_key in ipairs(plugin_keymaps) do
        local normalized_lhs = utils.normalize_keymap(plugin_key.lhs)

        if not plugin_key.lhs:match("^<Plug>") then
            local description = plugin_key.desc
            if not description or description == "" then
                description = plugin_key.rhs or "No description"
            end

            description = utils.normalize_description(description)

            if not description:match("<Plug>") then
                table.insert(all_keymaps, {
                    mode = plugin_key.mode,
                    keymap = normalized_lhs,
                    description = description,
                    source = plugin_key.source,
                    plugin = plugin_key.plugin,
                    plugin_disabled = plugin_key.plugin_disabled,
                    line_number = plugin_key.line_number,
                    raw_keymap = { lhs = plugin_key.lhs, desc = plugin_key.desc, rhs = plugin_key.rhs },
                })
            end
        end
    end
end

--- Deduplicates keymaps, prioritizing essential keymaps and their overrides
-- @param all_keymaps table List of all keymaps to deduplicate
-- @return table Deduplicated and sorted keymaps
function M._deduplicate_keymaps(all_keymaps)
    local deduplicated = {}
    local seen = {}

    for _, keymap in ipairs(all_keymaps) do
        local key = keymap.mode .. "|" .. keymap.keymap
        local existing = seen[key]

        if not existing then
            seen[key] = keymap
            table.insert(deduplicated, keymap)
        else
            local current_priority = M._get_keymap_priority(keymap)
            local existing_priority = M._get_keymap_priority(existing)

            if current_priority > existing_priority or
               (current_priority == existing_priority and keymap.built_in_section and 
                (not existing.built_in_section or keymap.built_in_order < existing.built_in_order)) then
                for i, entry in ipairs(deduplicated) do
                    if entry.mode == existing.mode and entry.keymap == existing.keymap then
                        deduplicated[i] = keymap
                        seen[key] = keymap
                        break
                    end
                end
            end
        end
    end

    table.sort(deduplicated, function(a, b)
        if a.built_in_section and b.built_in_section then
            return a.built_in_order < b.built_in_order
        elseif a.built_in_section and not b.built_in_section then
            return true
        elseif not a.built_in_section and b.built_in_section then
            return false
        else
            if a.mode ~= b.mode then
                return a.mode < b.mode
            end
            return a.keymap < b.keymap
        end
    end)

    return deduplicated
end

--- Gets the priority value for a keymap for deduplication purposes
-- @param keymap table Keymap to get priority for
-- @return number Priority value (higher = more important)
function M._get_keymap_priority(keymap)
    if keymap.built_in_section then
        return 10
    elseif keymap.source:match("lsp") or keymap.source:match("plugins/lsp%.lua") then
        return 5
    elseif keymap.plugin and keymap.plugin ~= "" and keymap.plugin ~= "nil" then
        return 6 -- Static analysis with plugin attribution gets high priority
    elseif keymap.source:match("config") then
        return keymap.line_number and 4 or 2
    elseif keymap.source == "Built-in Neovim default" then
        return 1
    else
        return 3
    end
end

--- Adds manual keymaps from configuration to the all_keymaps list
-- @param config table Configuration object
-- @param all_keymaps table List to add keymaps to
function M._add_manual_keymaps(config, all_keymaps)
    if not config or not config.manual_keymaps then
        return
    end
    
    for plugin_name, keymaps in pairs(config.manual_keymaps) do
        for _, manual_keymap in ipairs(keymaps) do
            local normalized_lhs = utils.normalize_keymap(manual_keymap.keymap)
            local description = utils.normalize_description(manual_keymap.desc)
            local source = manual_keymap.source or "Manual addition"
            
            table.insert(all_keymaps, {
                mode = manual_keymap.mode,
                keymap = normalized_lhs,
                description = description,
                source = source,
                plugin = plugin_name,
                plugin_disabled = false,
                line_number = nil,
                raw_keymap = { 
                    lhs = manual_keymap.keymap, 
                    desc = manual_keymap.desc, 
                    rhs = "manual" 
                },
            })
        end
    end
end

return M
