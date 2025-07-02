--- Configuration validation module
-- @module cheatsheet_generator.config_validator

local M = {}

--- Validates the configuration object and provides helpful error messages
-- @param config table|nil Configuration object to validate
-- @return boolean, string Success status and error message if validation fails
function M.validate_config(config)
    if not config then
        return true, nil
    end
    
    if type(config) ~= "table" then
        return false, "Configuration must be a table, got " .. type(config)
    end
    
    if config.plugin_dirs then
        if type(config.plugin_dirs) ~= "table" then
            return false, "config.plugin_dirs must be a table/list of strings"
        end
        
        for i, dir in ipairs(config.plugin_dirs) do
            if type(dir) ~= "string" then
                return false, string.format("config.plugin_dirs[%d] must be a string, got %s", i, type(dir))
            end
            if dir == "" then
                return false, string.format("config.plugin_dirs[%d] cannot be empty", i)
            end
        end
    end
    
    if config.config_keymap_files then
        if type(config.config_keymap_files) ~= "table" then
            return false, "config.config_keymap_files must be a table/list of strings"
        end
        
        for i, file in ipairs(config.config_keymap_files) do
            if type(file) ~= "string" then
                return false, string.format("config.config_keymap_files[%d] must be a string, got %s", i, type(file))
            end
            if file == "" then
                return false, string.format("config.config_keymap_files[%d] cannot be empty", i)
            end
        end
    end
    
    if config.manual_keymaps then
        local success, err = M._validate_manual_keymaps(config.manual_keymaps)
        if not success then
            return false, err
        end
    end
    
    if config.built_in_keymaps then
        local success, err = M._validate_built_in_keymaps(config.built_in_keymaps)
        if not success then
            return false, err
        end
    end
    
    if config.git then
        local success, err = M._validate_git_config(config.git)
        if not success then
            return false, err
        end
    end
    
    if config.output then
        local success, err = M._validate_output_config(config.output)
        if not success then
            return false, err
        end
    end
    
    return true, nil
end

--- Validates manual_keymaps configuration
-- @param manual_keymaps table Manual keymaps configuration
-- @return boolean, string Success status and error message
function M._validate_manual_keymaps(manual_keymaps)
    if type(manual_keymaps) ~= "table" then
        return false, "config.manual_keymaps must be a table"
    end
    
    for plugin_name, keymaps in pairs(manual_keymaps) do
        if type(plugin_name) ~= "string" then
            return false, "config.manual_keymaps keys must be plugin names (strings)"
        end
        
        if type(keymaps) ~= "table" then
            return false, string.format("config.manual_keymaps[\"%s\"] must be a table/list of keymap objects", plugin_name)
        end
        
        for i, keymap in ipairs(keymaps) do
            if type(keymap) ~= "table" then
                return false, string.format("config.manual_keymaps[\"%s\"][%d] must be a table", plugin_name, i)
            end
            
            -- Required fields
            if not keymap.keymap or type(keymap.keymap) ~= "string" then
                return false, string.format("config.manual_keymaps[\"%s\"][%d].keymap is required and must be a string", plugin_name, i)
            end
            
            if not keymap.mode or type(keymap.mode) ~= "string" then
                return false, string.format("config.manual_keymaps[\"%s\"][%d].mode is required and must be a string", plugin_name, i)
            end
            
            if not keymap.desc or type(keymap.desc) ~= "string" then
                return false, string.format("config.manual_keymaps[\"%s\"][%d].desc is required and must be a string", plugin_name, i)
            end
            
            -- Optional fields
            if keymap.source and type(keymap.source) ~= "string" then
                return false, string.format("config.manual_keymaps[\"%s\"][%d].source must be a string if provided", plugin_name, i)
            end
        end
    end
    
    return true, nil
end

--- Validates built_in_keymaps configuration
-- @param built_in_config table Built-in keymaps configuration
-- @return boolean, string Success status and error message
function M._validate_built_in_keymaps(built_in_config)
    if type(built_in_config) ~= "table" then
        return false, "config.built_in_keymaps must be a table"
    end
    
    if built_in_config.enabled ~= nil and type(built_in_config.enabled) ~= "boolean" then
        return false, "config.built_in_keymaps.enabled must be a boolean"
    end
    
    if built_in_config.module and type(built_in_config.module) ~= "string" then
        return false, "config.built_in_keymaps.module must be a string"
    end
    
    if built_in_config.section_order then
        if type(built_in_config.section_order) ~= "table" then
            return false, "config.built_in_keymaps.section_order must be a table/list"
        end
        
        for i, section in ipairs(built_in_config.section_order) do
            if type(section) ~= "string" then
                return false, string.format("config.built_in_keymaps.section_order[%d] must be a string", i)
            end
        end
    end
    
    return true, nil
end

--- Validates git configuration
-- @param git_config table Git configuration
-- @return boolean, string Success status and error message
function M._validate_git_config(git_config)
    if type(git_config) ~= "table" then
        return false, "config.git must be a table"
    end
    
    if git_config.enabled ~= nil and type(git_config.enabled) ~= "boolean" then
        return false, "config.git.enabled must be a boolean"
    end
    
    if git_config.default_branch and type(git_config.default_branch) ~= "string" then
        return false, "config.git.default_branch must be a string"
    end
    
    if git_config.base_url and type(git_config.base_url) ~= "string" then
        return false, "config.git.base_url must be a string"
    end
    
    return true, nil
end

--- Validates output configuration
-- @param output_config table Output configuration
-- @return boolean, string Success status and error message
function M._validate_output_config(output_config)
    if type(output_config) ~= "table" then
        return false, "config.output must be a table"
    end
    
    if output_config.file and type(output_config.file) ~= "string" then
        return false, "config.output.file must be a string"
    end
    
    if output_config.title and type(output_config.title) ~= "string" then
        return false, "config.output.title must be a string"
    end
    
    if output_config.include_date ~= nil and type(output_config.include_date) ~= "boolean" then
        return false, "config.output.include_date must be a boolean"
    end
    
    if output_config.generation_info then
        if type(output_config.generation_info) ~= "table" then
            return false, "config.output.generation_info must be a table"
        end
        
        local gen_info = output_config.generation_info
        if gen_info.enabled ~= nil and type(gen_info.enabled) ~= "boolean" then
            return false, "config.output.generation_info.enabled must be a boolean"
        end
    end
    
    if output_config.runtime_note then
        if type(output_config.runtime_note) ~= "table" then
            return false, "config.output.runtime_note must be a table"
        end
        
        local runtime_note = output_config.runtime_note
        if runtime_note.enabled ~= nil and type(runtime_note.enabled) ~= "boolean" then
            return false, "config.output.runtime_note.enabled must be a boolean"
        end
        
        if runtime_note.keymap_search and type(runtime_note.keymap_search) ~= "string" then
            return false, "config.output.runtime_note.keymap_search must be a string"
        end
    end
    
    
    return true, nil
end


--- Validates and applies defaults to configuration
-- @param config table|nil User configuration
-- @return table Validated configuration with defaults applied
function M.validate_and_apply_defaults(config)
    local success, err = M.validate_config(config)
    if not success then
        error("Configuration validation failed: " .. err)
    end
    
    local default_config = require("cheatsheet_generator").get_config()
    return vim.tbl_deep_extend("force", default_config, config or {})
end

return M