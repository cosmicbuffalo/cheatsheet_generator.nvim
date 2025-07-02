local M = {}

local default_config = {
	plugin_dirs = { "lua/plugins" },
	config_keymap_files = { "lua/config/keymaps.lua" },
	
	manual_keymaps = {},

	built_in_keymaps = {
		enabled = true,
		module = "cheatsheet_generator.built_in_keymaps",
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

	git = {
		enabled = true,
		default_branch = "main",
		base_url = nil,
	},

	output = {
		file = "CHEATSHEET.md",
		title = "Neovim Keymap Cheatsheet",
		include_date = true,
		generation_info = {
			enabled = true,
		},
		runtime_note = {
			enabled = true,
			keymap_search = nil,
		},
	},
}

local config = {}

--- Sets up the plugin with user configuration
-- @param user_config table|nil User configuration to merge with defaults
function M.setup(user_config)
	config = vim.tbl_deep_extend("force", default_config, user_config or {})
end

--- Gets the current plugin configuration
-- @return table Current configuration with defaults applied
function M.get_config()
	return config
end

--- Generates the cheatsheet with optional context
-- @param context string|nil Context for generation (e.g., "manual", "pre-commit")
-- @return boolean Success status
function M.generate(context)
	local generator = require("cheatsheet_generator.generator")
	return generator.generate(config, context or "manual")
end

--- Generates cheatsheet with specific context (used by pre-commit hook)
-- @param context string Context for generation
-- @return boolean Success status
function M.generate_with_context(context)
	return M.generate(context)
end

--- Installs the pre-commit hook for automatic cheatsheet generation
-- @return boolean Success status
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

--- Creates user commands for the plugin
-- Creates :CheatsheetGenerate and :CheatsheetInstallHook commands
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
