local M = {}

local function generate_sources_list(config)
    local sources = {}
    
    -- Built-in keymaps
    if config.built_in_keymaps and config.built_in_keymaps.enabled then
        table.insert(sources, "- Built-in Neovim defaults")
    end
    
    -- Config keymap files
    if config.config_keymap_files and #config.config_keymap_files > 0 then
        for _, file in ipairs(config.config_keymap_files) do
            local display_text = "Custom configuration in [`" .. file .. "`](" .. file .. ")"
            table.insert(sources, "- " .. display_text)
        end
    end
    
    -- Plugin directories
    if config.plugin_dirs and #config.plugin_dirs > 0 then
        for _, dir in ipairs(config.plugin_dirs) do
            local display_text = "Plugin-specific keymaps from [`" .. dir .. "/`](" .. dir .. "/)"
            table.insert(sources, "- " .. display_text)
        end
    end
    
    -- Ftplugin directory
    if config.ftplugin_dir then
        local display_text = "Filetype-specific keymaps from [`" .. config.ftplugin_dir .. "/`](" .. config.ftplugin_dir .. "/)"
        table.insert(sources, "- " .. display_text)
    end
    
    return sources
end

local function generate_generation_info(config, context)
    local lines = {}
    
    if not config.output.generation_info or not config.output.generation_info.enabled then
        return lines
    end
    
    -- Try to auto-detect script path if not provided
    local script_path = config.output.generation_info.script_path
    if not script_path then
        -- Check if we're being called from a specific script
        local info = debug.getinfo(2, "S")
        if info and info.source and info.source:match("@.*") then
            local source_file = info.source:sub(2) -- Remove @ prefix
            local cwd = vim.fn.getcwd()
            if source_file:find(cwd, 1, true) == 1 then
                script_path = source_file:sub(#cwd + 2)
            end
        end
    end
    
    -- Build generation description with context
    local generation_parts = {}
    
    if context == "pre-commit" then
        table.insert(generation_parts, "the cheatsheet generator plugin")
        if config.output.generation_info.hook_path then
            table.insert(generation_parts, "via a [pre-commit hook](" .. config.output.generation_info.hook_path .. ")")
        else
            table.insert(generation_parts, "via a pre-commit hook")
        end
    elseif context == "manual" then
        if script_path then
            table.insert(generation_parts, "[`" .. script_path .. "`](" .. script_path .. ")")
        else
            table.insert(generation_parts, "the cheatsheet generator plugin")
        end
        table.insert(generation_parts, "(manual generation)")
    else
        -- Default/unknown context
        if script_path then
            table.insert(generation_parts, "[`" .. script_path .. "`](" .. script_path .. ")")
        else
            table.insert(generation_parts, "the cheatsheet generator plugin")
        end
        if config.output.generation_info.hook_path then
            table.insert(generation_parts, "via a [pre-commit hook](" .. config.output.generation_info.hook_path .. ")")
        end
    end
    
    local generation_text = "This cheatsheet is automatically generated"
    if #generation_parts > 0 then
        generation_text = generation_text .. " by " .. table.concat(generation_parts, " ")
    end
    generation_text = generation_text .. "."
    
    table.insert(lines, generation_text)
    
    return lines
end

local function generate_runtime_note(config)
    local lines = {}
    
    if not config.output.runtime_note or not config.output.runtime_note.enabled then
        return lines
    end
    
    local note_parts = {
        "This cheatsheet does not include keymaps added automatically by configured plugins at runtime, such as those from most legacy vim plugins.",
        "To see all keymaps available in your current Neovim session, use the"
    }
    
    local suggestions = {}
    if config.output.runtime_note.suggestion then
        table.insert(suggestions, "`" .. config.output.runtime_note.suggestion .. "` command")
    end
    
    if config.output.runtime_note.keymap_search then
        table.insert(suggestions, "the `" .. config.output.runtime_note.keymap_search .. "` keymap to open a fuzzy search for keymaps")
    end
    
    if #suggestions > 0 then
        if #suggestions == 1 then
            note_parts[2] = note_parts[2] .. " " .. suggestions[1] .. "."
        else
            note_parts[2] = note_parts[2] .. " " .. table.concat(suggestions, ", or ") .. "."
        end
    else
        note_parts[2] = note_parts[2] .. " `:map` command."
    end
    
    table.insert(lines, "> [!NOTE]")
    table.insert(lines, "> " .. table.concat(note_parts, " "))
    
    return lines
end

function M.generate_notes(config, context)
    local lines = {}
    
    -- Generation info
    local generation_info = generate_generation_info(config, context)
    for _, line in ipairs(generation_info) do
        table.insert(lines, line)
    end
    
    if #generation_info > 0 then
        table.insert(lines, "")
    end
    
    -- Sources list
    table.insert(lines, "It includes all keymaps from:")
    table.insert(lines, "")
    
    local sources = generate_sources_list(config)
    for _, source in ipairs(sources) do
        table.insert(lines, source)
    end
    
    table.insert(lines, "")
    
    -- Runtime note
    local runtime_note = generate_runtime_note(config)
    for _, line in ipairs(runtime_note) do
        table.insert(lines, line)
    end
    
    if #runtime_note > 0 then
        table.insert(lines, "")
    end
    
    -- Additional notes
    if config.output.additional_notes and #config.output.additional_notes > 0 then
        for _, note in ipairs(config.output.additional_notes) do
            table.insert(lines, note)
        end
        table.insert(lines, "")
    end
    
    return lines
end

return M