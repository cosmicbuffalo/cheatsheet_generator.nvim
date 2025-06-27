local M = {}

-- Default configuration
local default_config = {
	-- File paths and directories to scan
	plugin_dirs = { "lua/plugins" },
	ftplugin_dir = "ftplugin", -- Automatically included
	config_keymap_files = { "lua/config/keymaps.lua" },

	-- Built-in keymaps configuration
	built_in_keymaps = {
		enabled = true,
		module = "cheatsheet_generator.built_in_keymaps", -- Automatically uses plugin's built-in keymaps
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
		},
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
		generation_info = {
			enabled = true,
			script_path = nil, -- Auto-detected or can be set manually
			hook_path = nil, -- Optional git hook path
		},
		runtime_note = {
			enabled = true,
			suggestion = ":map", -- Command to suggest for viewing runtime keymaps
			keymap_search = "<leader>sk", -- Keymap for fuzzy search (optional)
		},
		additional_notes = {
			-- Any additional custom notes to include
		},
	},

	-- Plugin-specific fixes/post-processing
	plugin_fixes = {
		-- Example: ["eyeliner.nvim"] = { keymap = "<leader>uf", source = "lua/plugins/editor.lua" }
	},

	-- Exclude patterns
	exclude = {
		sources = {},
		keymaps = {},
		descriptions = {},
	},
}

local config = {}

function M.setup(user_config)
	config = vim.tbl_deep_extend("force", default_config, user_config or {})
end

function M.get_config()
	return config
end

-- Generate the cheatsheet with context
function M.generate(context)
	local generator = require("cheatsheet_generator.generator")
	return generator.generate(config, context or "manual")
end

-- Generate with specific context (used by pre-commit hook)
function M.generate_with_context(context)
	return M.generate(context)
end

-- Install pre-commit hook
function M.install_hook()
	local cwd = vim.fn.getcwd()
	local git_dir = vim.fn.finddir(".git", cwd .. ";")

	if git_dir == "" then
		vim.notify("Not in a git repository", vim.log.levels.ERROR)
		return false
	end

	local hooks_dir = git_dir .. "/hooks"
	local hook_path = hooks_dir .. "/pre-commit"

	-- Create hooks directory if it doesn't exist
	vim.fn.mkdir(hooks_dir, "p")

	-- Get the plugin directory
	local plugin_path = debug.getinfo(1, "S").source:sub(2)
	local plugin_dir = vim.fn.fnamemodify(plugin_path, ":h:h:h")
	local source_hook = plugin_dir .. "/hooks/pre-commit"

	-- Determine the Neovim config directory
	local nvim_config_dir
	local nvim_appname = os.getenv("NVIM_APPNAME")
	if nvim_appname and nvim_appname ~= "" then
		nvim_config_dir = vim.fn.stdpath("config"):gsub("/nvim$", "/" .. nvim_appname)
	else
		nvim_config_dir = vim.fn.stdpath("config")
	end

	-- Read the source hook and customize it for this config
	local source_content = vim.fn.readfile(source_hook)
	local customized_content = {}

	for _, line in ipairs(source_content) do
		if line:match("nvim %-%-headless") then
			-- Customize the nvim command to use the correct config directory
			if nvim_appname and nvim_appname ~= "" then
				line = line:gsub("nvim %-%-headless", "NVIM_APPNAME=" .. nvim_appname .. " nvim --headless")
			end
		end
		table.insert(customized_content, line)
	end

	-- Write the customized hook
	vim.fn.writefile(customized_content, hook_path)

	-- Make it executable
	vim.fn.system("chmod +x '" .. hook_path .. "'")
	if vim.v.shell_error ~= 0 then
		vim.notify("Failed to make pre-commit hook executable", vim.log.levels.ERROR)
		return false
	end

	vim.notify(
		"Pre-commit hook installed successfully at " .. hook_path .. " (configured for " .. nvim_config_dir .. ")",
		vim.log.levels.INFO
	)
	return true
end

-- Create user commands
function M.create_commands()
	vim.api.nvim_create_user_command("CheatsheetGenerate", function()
		local success, err = pcall(M.generate, "manual")
		if success then
			vim.notify("Cheatsheet generated successfully!", vim.log.levels.INFO)
		else
			vim.notify("Error generating cheatsheet: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, { desc = "Generate keymap cheatsheet" })

	vim.api.nvim_create_user_command("CheatsheetInstallHook", function()
		M.install_hook()
	end, { desc = "Install pre-commit hook for automatic cheatsheet generation" })
end

return M
