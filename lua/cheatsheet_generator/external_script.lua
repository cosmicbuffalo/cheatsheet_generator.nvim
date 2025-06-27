#!/usr/bin/env nvim -l

vim.g.mapleader = " "

local keymap_collector = require("cheatsheet_generator.keymap_collector")
local formatter = require("cheatsheet_generator.formatter")
local config_validator = require("cheatsheet_generator.config_validator")

--- Main function to generate the cheatsheet
-- @param config table Configuration object
-- @return number Exit code
local function main()
    local config = nil
    if arg and arg[1] then
        local json_str = arg[1]
        local success, parsed_config = pcall(vim.json.decode, json_str)
        if success then
            config = parsed_config
        else
            print("Warning: Failed to parse configuration JSON, using defaults")
        end
    end
    
    if config then
        local valid, err = config_validator.validate_config(config)
        if not valid then
            print("Error: Configuration validation failed: " .. err)
            return 1
        end
    end

    -- Require keymap files from configuration if specified
    if config and config.config_keymap_files and #config.config_keymap_files > 0 then
        for _, keymap_file in ipairs(config.config_keymap_files) do
            -- Convert file path to module path (remove .lua extension and convert / to .)
            local module_path = keymap_file:gsub("%.lua$", ""):gsub("/", ".")
            local success, err = pcall(require, module_path)
            if not success then
                print("Warning: Could not load keymap file '" .. keymap_file .. "': " .. tostring(err))
            end
        end
    end

    print("Loading configuration and collecting all keymaps...")
    local keymaps = keymap_collector.collect_all_keymaps(config)
    print("Found " .. #keymaps .. " keymaps")

    print("Generating markdown...")
    local markdown = formatter.generate_markdown(keymaps, config)

    local output_file = (config and config.output and config.output.file) or "CHEATSHEET.md"
    local file_success, file = pcall(io.open, output_file, "w")
    if file_success and file then
        local write_success = pcall(function()
            file:write(markdown)
            file:close()
        end)
        
        if write_success then
            print("Cheatsheet written to " .. output_file)
        else
            print("Error: Failed to write content to " .. output_file)
            return 1
        end
    else
        print("Error: Could not open " .. output_file .. " for writing")
        return 1
    end

    return 0
end

main()
