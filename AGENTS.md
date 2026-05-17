# project_toolchain.nvim - Agent Guide

## Project Identity
- Neovim plugin (Lua only), forked from [project.nvim](https://github.com/ahmedkhalf/project.nvim)
- Entry point: `lua/project_toolchain/init.lua` → `M.setup(opts)`
- Module loaded as: `require('project_toolchain')`
- lazy.nvim config in `lazy.lua` - fires on `BufRead` event
- Dependency: `MunifTanjim/nui.nvim`

## No Toolchain
**There is no build, test, lint, typecheck, or CI in this repo.** It is a pure Lua Neovim plugin. Do not try to run tests, linters, or build steps.

## Module Structure
| File | Responsibility |
|------|---------------|
| `lua/project_toolchain/init.lua` | Plugin entry, autocommand setup, logging init |
| `lua/project_toolchain/config.lua` | Default options, user config merge via `vim.tbl_deep_extend` |
| `lua/project_toolchain/project/init.lua` | Project root detection (LSP + pattern), `:lua cd` logic |
| `lua/project_toolchain/project/history.lua` | Project history persistence (max 100 entries) |
| `lua/project_toolchain/cfg/init.lua` | Per-project config loading/writing |
| `lua/project_toolchain/commands.lua` | `:ProjectRoot`, `:AddProject` user commands |
| `lua/telescope/_extensions/project_dir_cfg.lua` | Telescope extension (`require('telescope').load_extension('project_dir_cfg')`) |
| `lua/project_toolchain/util/path_util.lua` | Path utilities, history file paths |
| `lua/project_toolchain/util/log*.lua` | Custom logging framework |
| `lua/project_toolchain/types.lua` | Empty placeholder |
| `lua/project_toolchain/_extensions/proj_debug.lua` | Stub (unused) |
| `lua/project_toolchain/extension/init.lua` | Stub (unused) |

## Key Architecture Facts
- **`autochdir` must be disabled**: `vim.opt.autochdir = false` is set in `setup()`
- **Detection methods run in order**, falling through if one returns nil. Default: `{"lsp", "pattern"}`
- **LSP detection**: uses `vim.lsp.get_clients()` root_dir; `lua_ls` is excluded by default (`config.ignore_lsp`)
- **Pattern detection**: searches upward from current buffer for markers in `proj_patterns` (`.nvim_proj`, `.git`, `_darcs`, `.hg`, `.bzr`, `.svn`, `Makefile`, `package.json`). Supports prefix modifiers: `=` (exact name), `^` (ancestor), `>` (child), `!` (exclude)
- **Per-project config**: stored in `<project_root>/.nvim_proj/config.json` (JSON format, loaded async via libuv)
- **History file**: stored at `<stdpath("data")>/project_nvim/project_history`, one path per line, max 100 entries
- **Filesystem ops use libuv** (`vim.uv`) — mostly async with callbacks
- **LSP attachment**: plugin monkey-patches `vim.lsp.start_client` to trigger root recalculation after LSP starts

## User Commands
- `:ProjectRoot` — Manually trigger project root detection and `cd`
- `:AddProject` — Manually add current directory as a project root

## Telescope Extension
Load: `require('telescope').load_extension('project_dir_cfg')`
Pick: `require('telescope').extensions.project_dir_cfg.projects()`

Key mappings:
| Mode | Key | Action |
|------|-----|--------|
| Insert | `<CR>` | Select project → find files |
| Insert | `<C-f>` | Find files in Project |
| Insert | `<C-s>` | Live grep in project |
| Insert | `<C-b>` | File browser in project |
| Insert | `<C-r>` | Recent files for project |
| Insert | `<C-w>` | Change working directory |
| Insert | `<C-d>` | Delete project from history |
| Normal | Same keys (no Ctrl prefix) | Same actions |

## `.opencode/` Directory
Contains OpenCode MCP plugin dependencies (`@opencode-ai/plugin`, `yaml`, `toml`, etc.) and memory files. **Not related to the Neovim plugin.** Do not modify or remove.

## Config (setup options)
```lua
require('project_toolchain').setup({
    debug = true,
    log_level = 'info',
    manual_mode = false,         -- if true, no auto-cd on buffer enter
    detection_methods = {"lsp", "pattern"}, -- order matters
    ignore_lsp = {'lua_ls'},    -- LSP clients to skip
    exclude_dirs = {},          -- glob patterns to exclude
    proj_patterns = {"..."},    -- project root markers
    show_hidden = false,        -- telescope shows hidden files
    silent_chdir = true,        -- suppress chdir notification
    scope_chdir = 'global',     -- global|tab|win
    datapath = vim.fn.stdpath("data"), -- base dir for history
})
```

## Development Notes
- `lua/project_toolchain/init.lua` lines 74-80 contain a debug block triggered by `LOCAL_LUA_DEBUGGER_VSCODE=1` env var
- No test framework exists — verify changes by loading plugin in Neovim manually
- History watch uses `fs_event` to reload when history file changes
- `config.options.exclude_dirs` are converted to Lua patterns at setup time (not glob)
