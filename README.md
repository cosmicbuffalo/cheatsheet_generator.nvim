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

### Minimal Configuration

The plugin works out of the box with sensible defaults:

```lua
require("cheatsheet_generator").setup({
  -- That's it! Uses defaults for everything
})
```

### Full Configuration Example

```lua
require("cheatsheet_generator").setup({
  -- File paths and directories to scan (optional overrides)
  plugin_dirs = { "lua/plugins" }, -- Default: { "lua/plugins" }
  config_keymap_files = { "lua/config/keymaps.lua" }, -- Default: { "lua/config/keymaps.lua" }
  -- ftplugin_dir = "ftplugin", -- Always included automatically
  
  -- Built-in keymaps (uses plugin's built-in keymaps by default)
  built_in_keymaps = {
    enabled = true, -- Default: true
    -- module and section_order use plugin defaults
  },
  
  -- Git/GitHub configuration
  git = {
    enabled = true, -- Default: true
    default_branch = "main", -- Default: "main"
    base_url = nil, -- Default: auto-detected from git remote
  },
  
  -- Output configuration
  output = {
    file = "CHEATSHEET.md", -- Default: "CHEATSHEET.md"
    title = "Neovim Keymap Cheatsheet", -- Default title
    include_date = true, -- Default: true
    generation_info = {
      enabled = true, -- Default: true
      script_path = "bin/generate_cheatsheet.lua", -- Optional: for legacy references
      hook_path = "hooks/pre-commit", -- Optional: git hook reference
    },
    runtime_note = {
      enabled = true, -- Default: true
      suggestion = ":map", -- Default: ":map"
      keymap_search = "<leader>sk", -- Optional: keymap for fuzzy search
    },
    additional_notes = {
      "Any additional custom notes can go here",
    }
  },
  
  -- Plugin-specific fixes/post-processing (optional)
  plugin_fixes = {
    ["eyeliner.nvim"] = { keymap = "<leader>uf", source = "lua/plugins/editor.lua" }
  },
  
  -- Exclude patterns (optional)
  exclude = {
    sources = { "lua/personal/" },
    keymaps = { "^<Plug>" },
    descriptions = { "<Plug>" }
  }
})
```

### Key Features

- **Automatic Defaults**: Works with zero configuration for standard Neovim setups
- **Built-in Keymaps**: Includes comprehensive built-in Neovim keymap definitions
- **Dynamic Notes**: Automatically generates documentation based on your configuration
- **Smart Detection**: Auto-detects Git repositories and file structures

## Usage

### Generate Cheatsheet

```vim
:CheatsheetGenerate
```

Or in Lua:

```lua
require("cheatsheet_generator").generate()
```

### Install Pre-commit Hook

The plugin includes a pre-commit hook that automatically generates the cheatsheet when you commit:

```vim
:CheatsheetInstallHook
```

Or in Lua:

```lua
require("cheatsheet_generator").install_hook()
```

This will:
- Copy the pre-commit hook to `.git/hooks/pre-commit`
- Make it executable
- Automatically generate the cheatsheet on every commit
- Add the updated cheatsheet to the commit if it changed

### Manual Git Hook Setup

If you prefer to set up the git hook manually:

```bash
#!/bin/sh
# .git/hooks/pre-commit
nvim --headless -c "lua require('cheatsheet_generator').generate_with_context('pre-commit')" -c "qa"
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
