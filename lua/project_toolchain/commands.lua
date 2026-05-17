local M = {}

local Command = vim.api.nvim_create_user_command

function M.setup()
    Command('ProjectRoot', function()
        require("project_toolchain.project").on_buf_enter()
    end, {})
    Command('AddProject', function()
        require("project_toolchain.project").add_project_manually()
    end, {})
    Command('ProjectLoadConfig', function()
        local project_path = vim.fn.getcwd()
        require("project_toolchain.project_config").load_project_config(project_path)
    end, {})
    Command('ProjectTrust', function()
        local project_path = vim.fn.getcwd()
        require("project_toolchain.project_config").trust_project(project_path)
        vim.notify("Project trusted: " .. project_path)
    end, {})
end

return M
