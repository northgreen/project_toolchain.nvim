# 🗂️ project_toolchain.nvim

> 基于 [project.nvim](https://github.com/ahmedkhalf/project.nvim) 增强的 Neovim 项目根目录检测与管理插件。

## ✨ 特性

- **自动项目检测** — 进入缓冲区时自动识别项目根目录并切换工作目录
- **多种检测方式** — 支持 LSP 和文件模式匹配，按顺序回退
- **项目级 Lua 配置** — 每个项目可拥有独立的 `init.lua`、LSP 配置和 ftplugin
- **信任机制** — SHA256 哈希校验，防止恶意配置自动执行
- **Telescope 项目选择器** — 快速在历史项目间跳转
- **项目历史记录** — 自动记录最近访问的 100 个项目
- **灵活的作用域** — 支持 `global` / `tab` / `win` 级别的目录切换

## 📦 安装

### lazy.nvim（推荐）

```lua
{
    "ictye/project_toolchain.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    config = function()
        require("project_toolchain").setup()
    end,
}
```

### packer.nvim

```lua
use {
    "ictye/project_toolchain.nvim",
    requires = { "MunifTanjim/nui.nvim" },
    config = function()
        require("project_toolchain").setup()
    end,
}
```

## ⚙️ 配置

### 默认选项

```lua
require("project_toolchain").setup({
    debug = false,
    log_level = "info",
    manual_mode = false,
    detection_methods = { "lsp", "pattern" },
    ignore_lsp = { "lua_ls" },
    exclude_dirs = {},
    proj_patterns = {
        ".nvim_proj", ".git", "_darcs", ".hg", ".bzr", ".svn",
        "Makefile", "package.json",
    },
    show_hidden = false,
    silent_chdir = true,
    scope_chdir = "global",
    auto_load_project_config = true,
    datapath = vim.fn.stdpath("data"),
})
```

### 关键选项说明

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `manual_mode` | `boolean` | `false` | `true` 时禁用自动切换，仅手动触发 |
| `detection_methods` | `string[]` | `{"lsp", "pattern"}` | 检测方式及回退顺序 |
| `ignore_lsp` | `string[]` | `{"lua_ls"}` | 忽略的 LSP 客户端名称 |
| `exclude_dirs` | `string[]` | `{}` | 排除的目录模式（支持 `~/` 前缀） |
| `proj_patterns` | `string[]` | 见上方 | 项目根目录标记文件/目录 |
| `scope_chdir` | `string` | `"global"` | 切换范围：`global` / `tab` / `win` |
| `silent_chdir` | `boolean` | `true` | 静默切换，不弹出通知 |
| `show_hidden` | `boolean` | `false` | Telescope 中显示隐藏文件 |
| `auto_load_project_config` | `boolean` | `true` | 自动加载项目级 Lua 配置 |

## 🚀 使用

### 用户命令

| 命令 | 说明 |
|------|------|
| `:ProjectRoot` | 手动触发项目根目录检测并切换 |
| `:AddProject` | 将当前目录手动添加为项目根目录 |

### Telescope 扩展

加载扩展：

```lua
require("telescope").load_extension("project_dir_cfg")
```

调用项目选择器：

```lua
require("telescope").extensions.project_dir_cfg.projects()
```

#### 快捷键

| 模式 | 按键 | 动作 |
|------|------|------|
| Insert | `<CR>` | 选择项目 → 查找文件 |
| Insert | `<C-f>` | 在项目内查找文件 |
| Insert | `<C-s>` | 在项目内搜索内容 |
| Insert | `<C-b>` | 浏览项目文件 |
| Insert | `<C-r>` | 最近打开的文件 |
| Insert | `<C-w>` | 切换工作目录 |
| Insert | `<C-d>` | 从历史中删除项目 |

> Normal 模式下使用相同按键（无需 `Ctrl` 前缀）。

## 📁 项目级配置

在项目根目录创建 `.nvim_proj/` 目录，即可为该项目加载专属配置：

```
my-project/
├── .nvim_proj/
│   ├── init.lua              # 项目初始化脚本
│   ├── lsp/
│   │   └── my_lsp.lua        # 项目专属 LSP 配置
│   ├── ftplugin/
│   │   ├── common.lua        # 对所有 filetype 生效
│   │   └── python.lua        # 仅对 Python 生效
│   └── config.json           # 自动管理，无需手动编辑
```

### 信任机制

首次加载含 Lua 配置的项目时，插件会提示信任。配置内容变更（SHA256 哈希变化）时将重新提示，确保安全性。

## ⚠️ 注意事项

- 插件会自动禁用 `vim.opt.autochdir`
- 项目历史最多保存 **100** 条记录
- 历史文件路径：`<datapath>/project_nvim/project_history`
- 项目配置路径：`<project_root>/.nvim_proj/config.json`

## 🔀 与 project.nvim 的主要区别

| 特性 | project.nvim | project_toolchain.nvim |
|------|:------------:|:----------------------:|
| 项目级 Lua 配置 | ❌ | ✅ |
| 信任机制 / 哈希校验 | ❌ | ✅ |
| ftplugin 支持 | ❌ | ✅ |
| Telescope 扩展名 | `projects` | `project_dir_cfg` |
