# cheatsheet_generator.nvim

A Neovim plugin for automatically generating comprehensive keymap cheatsheets in Markdown format.

## Features

- 🔍 **Comprehensive Detection**: Finds keymaps from built-in defaults, custom config, plugins, and ftplugins
- 📁 **Configurable Paths**: Specify which directories and files to scan
- 🔗 **GitHub Integration**: Automatically generates links to source files with line numbers
- 🎯 **Smart Categorization**: Groups keymaps by function, plugin, or custom categories
- ⚡ **Fast Parsing**: Efficient static analysis of Lua plugin configurations
- 🛠️ **Extensible**: Plugin-specific fixes and custom post-processing

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/cheatsheet_generator.nvim",
  opts = {
    -- Configuration options (see below)
  },
  cmd = "CheatsheetGenerate",
}
```

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "your-username/cheatsheet_generator.nvim",
  config = function()
    require("cheatsheet_generator").setup({
      -- Configuration options
    })
  end
}
```

## Configuration

```lua
require("cheatsheet_generator").setup({
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
    ["eyeliner.nvim"] = { keymap = "<leader>uf", source = "lua/plugins/editor.lua" }
  },
  
  -- Exclude patterns
  exclude = {
    sources = { "lua/personal/" },
    keymaps = { "^<Plug>" },
    descriptions = { "<Plug>" }
  }
})
```

## Usage

### Generate Cheatsheet

```vim
:CheatsheetGenerate
```

Or in Lua:

```lua
require("cheatsheet_generator").generate()
```

### Example Integration with Git Hooks

You can automatically generate the cheatsheet on every commit by adding it to your git hooks:

```bash
#!/bin/sh
# .git/hooks/pre-commit
nvim --headless -c "CheatsheetGenerate" -c "qa"
git add CHEATSHEET.md
```

## Keymap Detection

The plugin detects keymaps from multiple sources:

1. **Built-in Neovim defaults** - Standard Vim/Neovim keymaps
2. **Custom configuration** - Your personal keymaps from config files
3. **Plugin specifications** - Keymaps defined in lazy.nvim plugin specs
4. **Runtime keymaps** - Dynamically created keymaps from running plugins
5. **Filetype plugins** - Language-specific keymaps from ftplugin files

## Output Format

The generated cheatsheet includes:

- **Mode Legend** - Explanation of mode abbreviations
- **Categorized Tables** - Keymaps grouped by function or plugin
- **Source Links** - Direct links to source files with line numbers (GitHub)
- **Descriptions** - Human-readable descriptions for each keymap

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details.