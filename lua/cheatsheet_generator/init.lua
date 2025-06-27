local M = {}

-- Default configuration
local default_config = {
    -- File paths and directories to scan
    plugin_dirs = { "lua/plugins" },
    ftplugin_dir = "ftplugin",
    config_keymap_files = { "lua/config/keymaps.lua" },
    
    -- Built-in keymaps configuration
    built_in_keymaps = {
        enabled = true,
        module = "config.built_in_keymaps", -- Module to require for built-in keymaps
        section_order = {
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
    },
    
    -- Git/GitHub configuration
    git = {
        enabled = true,
        default_branch = "main",
        base_url = nil, -- Auto-detected from git remote
    },
    
    -- Output configuration
    output = {
        file = "CHEATSHEET.md",
        title = "Neovim Keymap Cheatsheet",
        include_date = true,
        notes = {
            "This cheatsheet is automatically generated.",
            "It includes all keymaps from built-in defaults, custom configuration, plugins, and ftplugins.",
        }
    },
    
    -- Plugin-specific fixes/post-processing
    plugin_fixes = {
        -- Example: ["eyeliner.nvim"] = { keymap = "<leader>uf", source = "lua/plugins/editor.lua" }
    },
    
    -- Exclude patterns
    exclude = {
        sources = { "lua/personal/" },
        keymaps = { "^<Plug>" },
        descriptions = { "<Plug>" }
    }
}

local config = {}

function M.setup(user_config)
    config = vim.tbl_deep_extend("force", default_config, user_config or {})
end

function M.get_config()
    return config
end

-- Generate the cheatsheet
function M.generate()
    local generator = require("cheatsheet_generator.generator")
    return generator.generate(config)
end

-- Command to generate cheatsheet
function M.create_command()
    vim.api.nvim_create_user_command("CheatsheetGenerate", function()
        local success, err = pcall(M.generate)
        if success then
            vim.notify("Cheatsheet generated successfully!", vim.log.levels.INFO)
        else
            vim.notify("Error generating cheatsheet: " .. tostring(err), vim.log.levels.ERROR)
        end
    end, { desc = "Generate keymap cheatsheet" })
end

return M