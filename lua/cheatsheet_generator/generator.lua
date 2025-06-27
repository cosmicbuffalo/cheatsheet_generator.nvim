--- Main generator module for executing the external script
-- @module cheatsheet_generator.generator

local M = {}

--- Executes the external script with injected configuration
-- @param config table Plugin configuration
-- @param context string Generation context (e.g., "manual", "pre-commit")
-- @return boolean Success status
function M.generate(config, context)
    local script_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/external_script.lua"
    
    -- Prepare config as JSON string
    local config_json = vim.json.encode(config or {})
    
    -- Determine the Neovim config directory
    local nvim_config_dir
    local nvim_appname = os.getenv("NVIM_APPNAME")
    if nvim_appname and nvim_appname ~= "" then
        nvim_config_dir = vim.fn.expand("~/.config/" .. nvim_appname)
    else
        nvim_config_dir = vim.fn.expand("~/.config/nvim")
    end
    
    -- Prepare the command to execute the external script from the Neovim config directory
    local cmd = string.format(
        'cd %s && nvim --clean --headless -c "set rtp+=~/%s" -c "set rtp+=." -l %s %s',
        vim.fn.shellescape(nvim_config_dir),
        "cheatsheet_generator.nvim",
        vim.fn.shellescape(script_path),
        vim.fn.shellescape(config_json)
    )
    
    -- Execute the command
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        error("Failed to execute external cheatsheet generation script")
    end
    
    local output = handle:read("*a")
    local success, exit_type, exit_code = handle:close()
    
    if not success then
        error("External script failed with exit code " .. (exit_code or "unknown") .. "\nOutput: " .. output)
    end
    
    print(output)
    return true
end

return M