local M = {}

local path = require("project_toolchain.util.path_util")
local project = require("project_toolchain.project")
local config = require("project_toolchain.config")
local log = require("project_toolchain.util.log")
local module_name = "project_toolchain.project_config"
local uv = vim.uv

-- 信任列表文件路径
M.trusted_file = nil

-- 已信任项目记录 { [project_path] = { hash = string | nil } }
M.trusted_projects = {}

-- Session 级拒绝记录 { [project_path] = true }
M.denied_projects = {}

-- 已加载的项目（防止重复加载）
M.loaded_projects = {}

-- 初始化：设置信任文件路径并加载信任列表
function M.init()
    M.trusted_file = path.datapath .. "/trusted_projects.json"
    M.load_trusted_list()
end

-- 从 JSON 文件加载信任列表（同步）
function M.load_trusted_list()
    if M.trusted_file == nil then return end

    local fd = uv.fs_open(M.trusted_file, "r", 438)
    if fd == nil then return end

    local stat = uv.fs_fstat(fd)
    if stat == nil then
        uv.fs_close(fd)
        return
    end

    local data = uv.fs_read(fd, stat.size, -1)
    uv.fs_close(fd)

    if data and #data > 0 then
        local ok, result = pcall(vim.json.decode, data)
        if ok and type(result) == "table" then
            M.trusted_projects = {}
            for _, entry in ipairs(result) do
                if type(entry) == "string" then
                    -- 旧格式迁移：string → { path = string, hash = nil }
                    M.trusted_projects[entry] = { hash = nil }
                elseif type(entry) == "table" and entry.path then
                    -- 新格式：{ path = string, hash = string | nil }
                    M.trusted_projects[entry.path] = { hash = entry.hash or nil }
                end
            end
        end
    end
end

-- 保存信任列表到 JSON 文件（同步）
function M.save_trusted_list()
    if M.trusted_file == nil then return end

    -- Convert record map to list of { path, hash } objects
    local list = {}
    for project_path, record in pairs(M.trusted_projects) do
        table.insert(list, { path = project_path, hash = record.hash })
    end

    local encoded = vim.json.encode(list)
    local fd = uv.fs_open(M.trusted_file, "w", 438)
    if fd ~= nil then
        uv.fs_write(fd, encoded)
        uv.fs_close(fd)
    end
end

-- 获取信任记录
function M.get_trusted_record(project_path)
    return M.trusted_projects[project_path] or nil
end

-- 检查项目是否已信任
function M.is_trusted(project_path)
    return M.trusted_projects[project_path] ~= nil
end

-- 信任项目（立即保存）
function M.trust_project(project_path, hash)
    M.trusted_projects[project_path] = { hash = hash or nil }
    M.denied_projects[project_path] = nil
    M.save_trusted_list()
end

-- 撤销信任
function M.untrust_project(project_path)
    M.trusted_projects[project_path] = nil
    M.save_trusted_list()
end

-- Phase 2.1: 计算单个文件的 SHA256 哈希值
-- 同步读取文件内容，失败时返回 nil（不抛出异常）
function M.compute_file_hash(file_path)
    if type(file_path) ~= "string" or file_path == "" then
        return nil
    end

    local fd = uv.fs_open(file_path, "r", 438)
    if fd == nil then
        return nil
    end

    local stat = uv.fs_fstat(fd)
    if stat == nil or stat.size == 0 then
        uv.fs_close(fd)
        return nil
    end

    local content = uv.fs_read(fd, stat.size, -1)
    uv.fs_close(fd)

    if content == nil then
        return nil
    end

    return vim.fn.sha256(content)
end

-- Phase 2.2: 计算项目配置的聚合哈希值
-- 收集关键文件（init.lua、lsp/*.lua、ftplugin/*.lua），
-- 对每个文件计算 SHA256，排序后拼接再 hash，确保确定性
function M.compute_project_hash(cfg_dir)
    if type(cfg_dir) ~= "string" or cfg_dir == "" then
        return vim.fn.sha256("")
    end

    local key_files = {}

    -- 收集 init.lua
    local init_path = path.join(cfg_dir, "init.lua")
    if path.file_exists(init_path) then
        table.insert(key_files, init_path)
    end

    -- 收集 lsp/*.lua
    local lsp_dir = path.join(cfg_dir, "lsp")
    if path.dir_exists(lsp_dir) then
        local dir = uv.fs_scandir(lsp_dir)
        if dir then
            while true do
                local name = uv.fs_scandir_next(dir)
                if not name then break end
                if name:match("%.lua$") then
                    table.insert(key_files, path.join(lsp_dir, name))
                end
            end
        end
    end

    -- 收集 ftplugin/*.lua
    local ft_dir = path.join(cfg_dir, "ftplugin")
    if path.dir_exists(ft_dir) then
        local dir = uv.fs_scandir(ft_dir)
        if dir then
            while true do
                local name = uv.fs_scandir_next(dir)
                if not name then break end
                if name:match("%.lua$") then
                    table.insert(key_files, path.join(ft_dir, name))
                end
            end
        end
    end

    -- 计算每个文件的哈希，跳过失败的文件
    local hashes = {}
    for _, file_path in ipairs(key_files) do
        local file_hash = M.compute_file_hash(file_path)
        if file_hash then
            table.insert(hashes, file_hash)
        end
    end

    -- 排序确保确定性
    table.sort(hashes)

    -- 拼接后再次 hash
    local combined = table.concat(hashes, "|")
    return vim.fn.sha256(combined)
end

-- 询问用户是否信任（使用 vim.ui.select）
function M.prompt_trust(project_path, hash, on_trust, on_deny)
    vim.ui.select({ "Trust", "Don't Trust" }, {
        prompt = string.format("Trust project '%s'? This will load its .nvim_proj/ Lua config.", project_path),
    }, function(choice)
        if choice == "Trust" then
            M.trust_project(project_path, hash)
            if on_trust then on_trust() end
        else
            M.denied_projects[project_path] = true
            if on_deny then on_deny() end
        end
    end)
end

-- 检查是否有需要信任的配置（含 ftplugin）
local function has_executable_config(cfg_dir)
    if path.file_exists(path.join(cfg_dir, "init.lua")) then
        return true
    end
    if path.dir_exists(path.join(cfg_dir, "lsp")) then
        return true
    end
    if path.dir_exists(path.join(cfg_dir, "ftplugin")) then
        return true
    end
    return false
end

-- 加载 .nvim_proj/init.lua
function M.load_init_lua(cfg_dir)
    local init_path = path.join(cfg_dir, "init.lua")
    if path.file_exists(init_path) then
        local ok, err = pcall(dofile, init_path)
        if not ok then
            log.error(module_name, "Failed to load init.lua: " .. tostring(err))
        else
            log.info(module_name, "Loaded init.lua from " .. cfg_dir)
        end
    end
end

-- 加载 .nvim_proj/lsp/ 下所有 .lua 文件
function M.load_lsp_configs(cfg_dir)
    local lsp_dir = path.join(cfg_dir, "lsp")
    if not path.dir_exists(lsp_dir) then return end

    local dir = uv.fs_scandir(lsp_dir)
    if dir == nil then return end

    while true do
        local name = uv.fs_scandir_next(dir)
        if not name then break end
        if name:match("%.lua$") then
            local file_path = path.join(lsp_dir, name)
            local ok, err = pcall(dofile, file_path)
            if not ok then
                log.error(module_name, "Failed to load lsp/" .. name .. ": " .. tostring(err))
            else
                log.info(module_name, "Loaded lsp/" .. name)
            end
        end
    end
end

-- 加载 .nvim_proj/ftplugin/ 下匹配当前 buffer filetype 的文件
function M.load_ftplugin(cfg_dir)
    local ft_dir = path.join(cfg_dir, "ftplugin")
    if not path.dir_exists(ft_dir) then return end

    local current_ft = vim.bo.filetype
    if not current_ft or current_ft == "" then return end

    -- 精确匹配: ftplugin/<filetype>.lua
    local ft_file = path.join(ft_dir, current_ft .. ".lua")
    if path.file_exists(ft_file) then
        local ok, err = pcall(dofile, ft_file)
        if not ok then
            log.error(module_name, "Failed to load ftplugin/" .. current_ft .. ".lua: " .. tostring(err))
        else
            log.info(module_name, "Loaded ftplugin/" .. current_ft .. ".lua")
        end
    end

    -- 通用配置: ftplugin/common.lua（对所有 filetype 生效）
    local common_file = path.join(ft_dir, "common.lua")
    if path.file_exists(common_file) then
        local ok, err = pcall(dofile, common_file)
        if not ok then
            log.error(module_name, "Failed to load ftplugin/common.lua: " .. tostring(err))
        else
            log.info(module_name, "Loaded ftplugin/common.lua")
        end
    end
end

-- 实际加载逻辑（内部）
function M._do_load(cfg_dir)
    M.load_init_lua(cfg_dir)
    M.load_lsp_configs(cfg_dir)
end

-- 主入口：加载项目配置（含信任检查 + 哈希比对）
function M.load_project_config(project_path)
    if not project_path then return end
    if M.loaded_projects[project_path] then return end
    if M._loading then return end
    M._loading = true

    local cfg_dir = path.join(project_path, ".nvim_proj")
    if not path.dir_exists(cfg_dir) then
        M._loading = nil
        return
    end

    -- 无可执行配置 → 直接加载
    if not has_executable_config(cfg_dir) then
        M._do_load(cfg_dir)
        M.loaded_projects[project_path] = true
        M._loading = nil
        return
    end

    -- 计算当前项目哈希
    local current_hash = M.compute_project_hash(cfg_dir)
    local record = M.get_trusted_record(project_path)

    -- 未信任 → 弹出信任提示
    if record == nil then
        if M.denied_projects[project_path] then
            M._loading = nil
            return
        end

        M.prompt_trust(project_path, current_hash, function()
            M._do_load(cfg_dir)
            M.loaded_projects[project_path] = true
        end, function() end)
        M._loading = nil
        return
    end

    -- 文件变更 → 清除缓存与拒绝记录，弹出信任提示
    if record.hash ~= current_hash then
        M.loaded_projects[project_path] = nil
        M.denied_projects[project_path] = nil

        M.prompt_trust(project_path, current_hash, function()
            M._do_load(cfg_dir)
            M.loaded_projects[project_path] = true
        end, function() end)
        M._loading = nil
        return
    end

    -- 哈希匹配 → 直接加载
    M._do_load(cfg_dir)
    M.loaded_projects[project_path] = true
    M._loading = nil
end

-- ftplugin 单独加载（由 BufEnter 触发，针对当前 buffer 的 filetype）
function M.load_ftplugin_for_buffer()
    if not project.last_project then return end
    local cfg_dir = path.join(project.last_project, ".nvim_proj")
    if not path.dir_exists(cfg_dir) then return end

    -- ftplugin 不需要信任检查，也不需要加载缓存检查
    -- 因为 filetype 可能变化，每次都检查是否已加载
    local ft_dir = path.join(cfg_dir, "ftplugin")
    if path.dir_exists(ft_dir) then
        M.load_ftplugin(cfg_dir)
    end
end

return M