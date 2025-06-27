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
  cmd = { "CheatsheetGenerate", "CheatsheetInstallHook" },
}
```

## Configuration

### Minimal Configuration

The plugin works out of the box with sensible defaults that assume the current neovim config uses lazy as a plugin manager. The default config assumes custom keymaps are located in `lua/config/keymaps.lua`, but this can be configured with the `config_keymap_files` option

### Full Configuration Example

```lua
require("cheatsheet_generator").setup({
  -- Where should the generator look for lazy plugin specs
  plugin_dirs = { "lua/plugins" }, 
  -- Where should the generator look for custom keymaps
  config_keymap_files = { "lua/config/keymaps.lua" },
  
  -- Built-in keymaps (uses plugin's built-in keymaps by default)
  built_in_keymaps = {
    enabled = true,
    -- change this if you want to use a different file for built in keymaps
    module = "cheatsheet_generator.built_in_keymaps", 
    -- change this to modify the display order of built in keymaps
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
  -- Git detection configuration
  git = {
    enabled = true, -- default behavior looks at your git repo to create source links
    default_branch = "main", -- the branch to use for source links
    base_url = nil, -- the base url to use for git links, leave nil to auto-detect 
  },
  -- Output configuration
  output = {
    file = "CHEATSHEET.md",
    title = "Neovim Keymap Cheatsheet",
    include_date = true,
    generation_info = {
      enabled = true,
    },
    runtime_note = {
      enabled = true,
      keymap_search = "<leader>sk", -- Optional: keymap for fuzzy search (only shown if set)
    },
  },
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

The plugin includes a convenient command to install a pre-commit hook that automatically generates the cheatsheet when you commit. This is especially useful for Neovim configuration repositories where you want to keep the cheatsheet up-to-date automatically.

#### Installation Command

Run this command from within your Neovim configuration repository:

```vim
:CheatsheetInstallHook
```

Or in Lua:

```lua
require("cheatsheet_generator").install_hook()
```

#### What the Hook Does

This command will:
- **Detect your git repository** - Works in any git repository (like your nvim config repo)
- **Handle custom Neovim configs** - Automatically detects and configures for `NVIM_APPNAME` setups
- **Copy the pre-commit hook** to `.git/hooks/pre-commit`
- **Make it executable** with proper permissions
- **Automatically generate the cheatsheet** on every commit
- **Add the updated cheatsheet to the commit** if it changed
- **Warn but not fail** if cheatsheet generation fails (so commits aren't blocked)

#### Requirements

- Must be run from within a git repository
- The repository should contain your Neovim configuration files
- Git must be available in your PATH

The hook will automatically work with both standard Neovim configs and custom `NVIM_APPNAME` configurations.

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
