local M = {}

local function get_keymap_source(keymap)
	-- Check if this is a built-in Neovim keymap
	if keymap.sid and keymap.sid == -1 then
		return "Built-in Neovim default"
	end

	-- For buffer-local keymaps, try to find the actual source location
	local info
	if type(keymap.callback) == "function" then
		info = debug.getinfo(keymap.callback, "S")
	elseif type(keymap.rhs) == "string" and keymap.rhs:match("^:lua") then
		-- Try to extract source from lua command if possible
		local lua_code = keymap.rhs:match("^:lua%s+(.+)")
		if lua_code then
			local func, err = load("return " .. lua_code)
			if func then
				local ok, result = pcall(func)
				if ok and type(result) == "function" then
					info = debug.getinfo(result, "S")
				end
			end
		end
	end

	if info and info.source then
		local source = info.source
		if source:sub(1, 1) == "@" then
			source = source:sub(2)
			local cwd = vim.fn.getcwd()
			if source:find(cwd, 1, true) == 1 then
				source = source:sub(#cwd + 2)
				return source
			else
				-- Check if this is keymaps.lua from config directory
				for _, config_file in ipairs(vim.tbl_get(M.config, "config_keymap_files") or {}) do
					if source:match("/" .. config_file:gsub("lua/", ""):gsub("%.lua$", "%.lua$")) then
						return config_file
					end
				end
				return source
			end
		elseif source:sub(1, 1) == "=" then
			return source:sub(2)
		end
	end

	-- If we can't determine source, this is likely from keymaps.lua
	return (vim.tbl_get(M.config, "config_keymap_files") or {})[1] or "lua/config/keymaps.lua"
end

local function normalize_keymap(lhs)
	local leader = vim.g.mapleader or "\\"
	local localleader = vim.g.maplocalleader or "\\"

	-- Remove <silent> prefix if present
	lhs = lhs:gsub("^<silent>%s*", "")
	-- change this if we ever end up using an actual localleader key
	lhs = lhs:gsub("<[Ll]ocal[Ll]eader>", "<leader>")

	-- Normalize leader key
	lhs = lhs:gsub(vim.pesc(leader), "<leader>")
	lhs = lhs:gsub(vim.pesc(localleader), "<leader>")
	lhs = lhs:gsub("<[Ll]eader>", "<leader>")

	return lhs
end

local function normalize_description(desc)
	-- Clean up multiple spaces
	desc = desc:gsub("%s+", " ")
	desc = desc:gsub("^%s+", "")
	desc = desc:gsub("%s+$", "")

	-- Replace comma+space with /
	desc = desc:gsub(", ", "/")

	-- Convert snake_case to Title Case with spaces
	desc = desc:gsub("([%w]+)_([%w]+)", function(first, rest)
		-- Convert to title case with spaces
		local first_title = first:gsub("^%l", string.upper)
		local rest_title = rest:gsub("_", " "):gsub("(%l)(%w*)", function(f, r)
			return string.upper(f) .. r
		end)
		return first_title .. " " .. rest_title
	end)

	desc = desc:gsub("(%w)_(%w)", function(before, after)
		return before .. " " .. after
	end)

	-- Fix capitalization after /
	desc = desc:gsub("/(%l)", function(letter)
		return "/" .. string.upper(letter)
	end)

	return desc
end

local function find_files_in_directory(dir, pattern)
	local files = {}
	local handle = io.popen("find " .. dir .. " -name '" .. pattern .. "' -type f 2>/dev/null")
	if handle then
		for file in handle:lines() do
			table.insert(files, file)
		end
		handle:close()
	end
	return files
end

local function parse_plugin_keymaps(config)
	local plugin_keymaps = {}
	local plugin_files = {}

	-- Add all files from configured plugin directories
	for _, plugin_dir in ipairs(config.plugin_dirs or {}) do
		local files = find_files_in_directory(plugin_dir, "*.lua")
		for _, file in ipairs(files) do
			table.insert(plugin_files, file)
		end
	end

	-- Add all files from ftplugin directory
	if config.ftplugin_dir then
		local files = find_files_in_directory(config.ftplugin_dir, "*.lua")
		for _, file in ipairs(files) do
			table.insert(plugin_files, file)
		end
	end

	-- Add config keymap files
	for _, config_file in ipairs(config.config_keymap_files or {}) do
		table.insert(plugin_files, config_file)
	end

	for _, file in ipairs(plugin_files) do
		local full_path = file
		local f = io.open(full_path, "r")
		if f then
			f:close()

			-- Track current plugin name and status for plugin-specific groupings
			local current_plugin = nil
			local current_plugin_disabled = false
			local in_keys_section = false
			local keys_section_plugin = nil
			local keys_section_locked = false
			local brace_depth = 0
			local plugin_start_depth = 0
			local main_plugin = nil
			local main_plugin_depth = 0
			local plugin_stack = {} -- Track plugin hierarchy by depth

			-- Multi-line keymap tracking
			local multiline_keymap = nil
			local multiline_lhs = nil
			local multiline_desc = nil
			local multiline_line_num = nil

			local line_num = 1
			for line in io.lines(full_path) do
				-- Track brace depth to understand nested structures
				local open_braces = select(2, line:gsub("{", ""))
				local close_braces = select(2, line:gsub("}", ""))
				brace_depth = brace_depth + open_braces - close_braces

				-- Detect plugin name from lazy plugin specs (GitHub-style author/repo)
				local plugin_name = line:match('"([%w%-_%.]+/[%w%-_%.]+)"') or line:match("'([%w%-_%.]+/[%w%-_%.]+)'")
				if plugin_name and not keys_section_locked then
					current_plugin = plugin_name:match("([^/]+)$") -- Extract just the plugin name

					-- Store plugin at current depth
					plugin_stack[brace_depth] = current_plugin

					-- If this is a top-level plugin (depth 2 in a return { } structure), it's a main plugin
					if brace_depth == 2 then
						main_plugin = current_plugin
						main_plugin_depth = brace_depth
						current_plugin_disabled = false
						in_keys_section = false
					end
				end

				-- Detect if plugin is disabled (only at top level of plugin spec)
				if line:match("^%s*enabled%s*=%s*false") and brace_depth == 3 and main_plugin then
					current_plugin_disabled = true
				end

				-- Detect entering keys section
				if line:match("keys%s*=") then
					in_keys_section = true
					-- Keys belong to the closest plugin that contains them
					keys_section_plugin = current_plugin
					if not keys_section_plugin then
						-- If no immediate plugin, find the plugin that owns this keys section
						for depth = brace_depth - 1, 1, -1 do
							if plugin_stack[depth] then
								keys_section_plugin = plugin_stack[depth]
								break
							end
						end
					end

					-- Don't allow further plugin changes while in keys section
					keys_section_locked = true
				end

				-- Reset keys section when we exit it
				if
					in_keys_section
					and not line:match("keys%s*=")
					and not line:match("^%s*{")
					and not line:match("^%s*%[")
				then
					local open_braces = select(2, line:gsub("{", ""))
					local close_braces = select(2, line:gsub("}", ""))
					if close_braces > open_braces and (line:match("},%s*$") or line:match("}%s*$")) then
						in_keys_section = false
						keys_section_plugin = nil
						keys_section_locked = false
					end
				end

				-- Reset plugin context when we exit any plugin scope
				for depth = brace_depth + 1, 10 do
					plugin_stack[depth] = nil
				end

				if current_plugin and plugin_stack[brace_depth] ~= current_plugin then
					current_plugin = plugin_stack[brace_depth]
				end

				-- Reset plugin context only when we exit the main plugin table
				if brace_depth < main_plugin_depth and main_plugin then
					main_plugin = nil
					main_plugin_depth = 0
					current_plugin = nil
					current_plugin_disabled = false
					in_keys_section = false
					keys_section_plugin = nil
					keys_section_locked = false
					plugin_start_depth = 0
				end

				-- Handle multi-line keymap collection
				if multiline_keymap then
					local desc = line:match('desc = "([^"]+)"')
					if desc then
						table.insert(plugin_keymaps, {
							lhs = multiline_lhs,
							rhs = "function",
							desc = desc,
							mode = "n",
							source = file,
							plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
							plugin_disabled = current_plugin_disabled,
							line_number = multiline_line_num,
						})
						multiline_keymap = nil
						multiline_lhs = nil
						multiline_desc = nil
						multiline_line_num = nil
					end
				end

				-- Check for start of multi-line keymap definition
				local multiline_start_lhs = line:match('^%s*{ "([^"]+)",%s*$')
				if multiline_start_lhs and in_keys_section then
					multiline_keymap = true
					multiline_lhs = multiline_start_lhs
					multiline_line_num = line_num
				end

				if line:match("^%s*{%s*$") and in_keys_section then
					multiline_keymap = "starting"
					multiline_line_num = line_num
				end

				if multiline_keymap == "starting" then
					local key_line_lhs = line:match('^%s*"([^"]+)",%s*$')
					if key_line_lhs then
						multiline_keymap = true
						multiline_lhs = key_line_lhs
						multiline_line_num = line_num
					end
				end

				-- Parse various keymap patterns (simplified - add all your patterns here)
				-- Pattern 1: { "key", "command", desc = "description" }
				local lhs, rhs, desc = line:match('{ "([^"]+)",%s*"([^"]+)",%s*desc = "([^"]+)"')
				if lhs then
					table.insert(plugin_keymaps, {
						lhs = lhs,
						rhs = rhs,
						desc = desc,
						mode = "n",
						source = file,
						plugin = in_keys_section and (current_plugin or keys_section_plugin or main_plugin) or nil,
						plugin_disabled = current_plugin_disabled,
						line_number = line_num,
					})
				end

				-- Add more patterns here as needed from your original script...

				line_num = line_num + 1
			end
		end
	end

	-- Apply plugin-specific fixes if configured
	if config.plugin_fixes then
		for plugin_name, fix in pairs(config.plugin_fixes) do
			for _, keymap in ipairs(plugin_keymaps) do
				if keymap.lhs == fix.keymap and keymap.source == fix.source then
					keymap.plugin = plugin_name
				end
			end
		end
	end

	return plugin_keymaps
end

local function collect_all_keymaps(config)
	local all_keymaps = {}

	-- First, load built-in keymaps if enabled
	local built_in_keymaps = nil
	if config.built_in_keymaps and config.built_in_keymaps.enabled then
		local built_in_keymaps_ok, result = pcall(require, config.built_in_keymaps.module)
		if not built_in_keymaps_ok then
			print("Warning: Could not load " .. config.built_in_keymaps.module .. ", skipping built-in keymaps")
		else
			built_in_keymaps = result
		end
	end

	local modes = { "n", "i", "v", "x", "s", "o", "t", "c" }

	-- Collect runtime keymaps from neovim
	local runtime_keymaps = {}
	for _, mode in ipairs(modes) do
		-- Get all keymaps including defaults
		local keymaps = vim.api.nvim_get_keymap(mode)
		for _, keymap in ipairs(keymaps) do
			if keymap.lhs and keymap.lhs ~= "" then
				local desc = keymap.desc
				if not desc or desc == "" or desc == "No description" then
					desc = keymap.rhs or "No description"
				end

				desc = normalize_description(desc)
				local source = get_keymap_source(keymap)
				local normalized_lhs = normalize_keymap(keymap.lhs)

				-- Check exclude patterns
				local should_exclude = false
				for _, exclude_pattern in ipairs(config.exclude.sources or {}) do
					if source and source:match(exclude_pattern) then
						should_exclude = true
						break
					end
				end

				for _, exclude_pattern in ipairs(config.exclude.keymaps or {}) do
					if keymap.lhs:match(exclude_pattern) then
						should_exclude = true
						break
					end
				end

				for _, exclude_pattern in ipairs(config.exclude.descriptions or {}) do
					if desc:match(exclude_pattern) then
						should_exclude = true
						break
					end
				end

				if not should_exclude then
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
			end
		end

		-- Get buffer-local keymaps (similar logic)
		local buf_keymaps = vim.api.nvim_buf_get_keymap(0, mode)
		for _, keymap in ipairs(buf_keymaps) do
			-- Similar processing as above
			if keymap.lhs and keymap.lhs ~= "" then
				local desc = keymap.desc
				if not desc or desc == "" or desc == "No description" then
					desc = keymap.rhs or "No description"
				end

				desc = normalize_description(desc)
				local source = get_keymap_source(keymap)
				local normalized_lhs = normalize_keymap(keymap.lhs)

				-- Apply same exclude logic
				local should_exclude = false
				for _, exclude_pattern in ipairs(config.exclude.sources or {}) do
					if source and source:match(exclude_pattern) then
						should_exclude = true
						break
					end
				end

				for _, exclude_pattern in ipairs(config.exclude.keymaps or {}) do
					if keymap.lhs:match(exclude_pattern) then
						should_exclude = true
						break
					end
				end

				for _, exclude_pattern in ipairs(config.exclude.descriptions or {}) do
					if desc:match(exclude_pattern) then
						should_exclude = true
						break
					end
				end

				if not should_exclude then
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
			end
		end
	end

	-- Create runtime lookup map
	local runtime_lookup = {}
	for _, runtime_keymap in ipairs(runtime_keymaps) do
		local key = runtime_keymap.mode .. "|" .. runtime_keymap.keymap
		runtime_lookup[key] = runtime_keymap
	end

	-- Process built-in keymaps if available
	if built_in_keymaps then
		for section_name, section_keymaps in pairs(built_in_keymaps) do
			for _, built_in_keymap in ipairs(section_keymaps) do
				local normalized_lhs = normalize_keymap(built_in_keymap.lhs)
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
						description = normalize_description(description)

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
					description = normalize_description(description)

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

	-- Add plugin keymaps from static analysis
	local plugin_keymaps = parse_plugin_keymaps(config)
	for _, plugin_key in ipairs(plugin_keymaps) do
		local normalized_lhs = normalize_keymap(plugin_key.lhs)

		-- Check exclude patterns
		local should_exclude = false
		for _, exclude_pattern in ipairs(config.exclude.keymaps or {}) do
			if plugin_key.lhs:match(exclude_pattern) then
				should_exclude = true
				break
			end
		end

		if not should_exclude then
			local description = plugin_key.desc
			if not description or description == "" then
				description = plugin_key.rhs or "No description"
			end

			description = normalize_description(description)

			-- Check description excludes
			local desc_excluded = false
			for _, exclude_pattern in ipairs(config.exclude.descriptions or {}) do
				if description:match(exclude_pattern) then
					desc_excluded = true
					break
				end
			end

			if not desc_excluded then
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

	-- Deduplicate keymaps with priority logic
	local deduplicated = {}
	local seen = {}

	for _, keymap in ipairs(all_keymaps) do
		local key = keymap.mode .. "|" .. keymap.keymap
		local existing = seen[key]

		if not existing then
			seen[key] = keymap
			table.insert(deduplicated, keymap)
		else
			-- Priority logic here (simplified for now)
			local current_priority = 0
			local existing_priority = 0

			if keymap.built_in_section then
				current_priority = 10
			elseif keymap.source:match("lsp") then
				current_priority = 5
			elseif keymap.plugin then
				current_priority = 6
			elseif keymap.source:match("config") then
				current_priority = keymap.line_number and 4 or 2
			elseif keymap.source == "Built-in Neovim default" then
				current_priority = 1
			else
				current_priority = 3
			end

			-- Similar logic for existing priority
			if existing.built_in_section then
				existing_priority = 10
			elseif existing.source:match("lsp") then
				existing_priority = 5
			elseif existing.plugin then
				existing_priority = 6
			elseif existing.source:match("config") then
				existing_priority = existing.line_number and 4 or 2
			elseif existing.source == "Built-in Neovim default" then
				existing_priority = 1
			else
				existing_priority = 3
			end

			if current_priority > existing_priority then
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

	return deduplicated
end

local function categorize_keymaps_by_function(keymaps)
	local categories = {}
	local prefix_groups = {}
	local plugin_groups = {}
	local essential_sections = {}

	-- Separate built-in keymaps from others
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

	-- Add built-in sections to categories
	for section_name, section_keymaps in pairs(essential_sections) do
		categories[section_name] = {
			keymaps = section_keymaps,
			disabled = false,
			is_built_in = true,
			order = 0,
		}
	end

	-- Process non-built-in keymaps
	for _, keymap in ipairs(non_built_in_keymaps) do
		local desc = keymap.description
		local prefix = desc:match("^([^:]+):")
		local source = keymap.source

		-- Special handling for Copilot
		if prefix == "Copilot" then
			if not prefix_groups[prefix] then
				prefix_groups[prefix] = {}
			end
			table.insert(prefix_groups[prefix], keymap)
		-- Group by ftplugin filetype
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
		-- Group by plugin
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
			-- Group by description prefix
			if prefix then
				if not prefix_groups[prefix] then
					prefix_groups[prefix] = {}
				end
				table.insert(prefix_groups[prefix], keymap)
			end
		end
	end

	-- Add plugin sections
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

	-- Create sections for prefixes with 2+ keymaps
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

	-- Categorize remaining keymaps functionally
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

	-- Functional categorization for remaining keymaps
	local functional_categories = {
		["LSP"] = {},
		["Miscellaneous"] = {},
	}

	for _, keymap in ipairs(remaining) do
		local lhs = keymap.keymap
		local desc = keymap.description:lower()
		local source = keymap.source

		if
			source:match("lsp")
			or desc:match("lsp")
			or desc:match("diagnostic")
			or desc:match("signature help")
			or lhs:match("^gr[arnri]$")
			or lhs == "gO"
			or lhs:match("^<C-S>$")
		then
			table.insert(functional_categories["LSP"], keymap)
		else
			table.insert(functional_categories["Miscellaneous"], keymap)
		end
	end

	-- Merge functional categories
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

local function generate_markdown(keymaps, config, context)
	local markdown = require("cheatsheet_generator.markdown")
	local notes = require("cheatsheet_generator.notes")

	local lines = {
		"# " .. (config.output.title or "Neovim Keymap Cheatsheet"),
		"",
	}

	if config.output.include_date then
		table.insert(lines, "Up to date as of: " .. os.date("%Y-%m-%d"))
		table.insert(lines, "")
	end

	-- Add dynamically generated notes
	local generated_notes = notes.generate_notes(config, context)
	for _, note in ipairs(generated_notes) do
		table.insert(lines, note)
	end

	-- Mode legend
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

	-- Categorize keymaps
	local categories, prefix_groups = categorize_keymaps_by_function(keymaps)

	-- Separate categories by type
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

	-- Add built-in sections in configured order
	local built_in_order = config.built_in_keymaps and config.built_in_keymaps.section_order or {}
	for _, section_name in ipairs(built_in_order) do
		if categories[section_name] and categories[section_name].is_built_in then
			local category_data = categories[section_name]
			local title = section_name:gsub("_", " "):gsub("(%l)(%w*)", function(f, r)
				return string.upper(f) .. r
			end)
			local section =
				markdown.generate_section_table(category_data.keymaps, title, nil, category_data.disabled, config)
			for _, line in ipairs(section) do
				table.insert(lines, line)
			end
		end
	end

	-- Add prefix sections
	table.sort(prefix_sections)
	for _, prefix in ipairs(prefix_sections) do
		local category_data = categories[prefix]
		local section = markdown.generate_section_table(
			category_data.keymaps,
			prefix,
			prefix .. ":",
			category_data.disabled,
			config
		)
		for _, line in ipairs(section) do
			table.insert(lines, line)
		end
	end

	-- Add plugin sections
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

		local section = markdown.generate_section_table(
			category_data.keymaps,
			category,
			strip_prefix,
			category_data.disabled,
			config
		)
		for _, line in ipairs(section) do
			table.insert(lines, line)
		end
	end

	-- Add other sections
	table.sort(other_sections)
	for _, category in ipairs(other_sections) do
		local category_data = categories[category]
		local section =
			markdown.generate_section_table(category_data.keymaps, category, nil, category_data.disabled, config)
		for _, line in ipairs(section) do
			table.insert(lines, line)
		end
	end

	return table.concat(lines, "\n")
end

function M.generate(config, context)
	M.config = config -- Store config for use in other functions
	M.context = context or "manual" -- Store generation context

	-- Load core configuration without plugins (if specified)
	if config.load_config then
		for _, module in ipairs(config.load_config) do
			require(module)
		end
	end

	print("Loading configuration and collecting all keymaps...")
	local keymaps = collect_all_keymaps(config)
	print("Found " .. #keymaps .. " keymaps")

	print("Generating markdown...")
	local markdown_content = generate_markdown(keymaps, config, context)

	local output_file = config.output.file or "CHEATSHEET.md"
	local file = io.open(output_file, "w")
	if file then
		file:write(markdown_content)
		file:close()
		print("Cheatsheet written to " .. output_file)
		return true
	else
		error("Could not write to " .. output_file)
	end
end

return M

