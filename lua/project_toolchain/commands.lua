local M = {}

local Command = vim.api.nvim_create_user_command

function M.setup()
    Command('ProjectRoot', function()
        require("project_toolchain.project").on_buf_enter()
    end, {})
    Command('AddProject', function()
        require("project_toolchain.project").add_project_manually()
    end, {})
end

return M
