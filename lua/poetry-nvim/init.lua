local M = {}

local sep = package.config:sub(1, 1)
local path_sep = (sep == "\\") and ";" or ":"

-- State
local last_venv = nil
local current_project_root = nil
local lsp_restart_scheduled = false
local project_venvs = {} -- cache: project_root -> venv_path

-- Utilities
local function join(...) 
    return table.concat({ ... }, sep) 
end

local function is_root(dir)
    if sep == "\\" then
        return dir:match("^%a:\\$") ~= nil
    else
        return dir == "/"
    end
end

local function find_project_root(start_dir, max_up)
    local dir = start_dir and vim.fn.fnamemodify(start_dir, ":p") or vim.fn.getcwd()
    local depth = 0
    max_up = max_up or 20

    while dir and dir ~= "" and depth < max_up do
        if vim.fn.filereadable(join(dir, "poetry.lock")) == 1 then
            return dir
        end
        if is_root(dir) then break end
        local parent = vim.fn.fnamemodify(dir, ":h")
        if parent == dir then break end
        dir = parent
        depth = depth + 1
    end
    return nil
end

local function get_venv_path_cached(project_root)
    if project_venvs[project_root] then
        return project_venvs[project_root]
    end

    local cmd = { "poetry", "env", "info", "-p", "-C", project_root }
    if sep == "\\" then
        cmd = { "cmd", "/c", table.concat(cmd, " ") }
    end

    local output = vim.fn.system(cmd)
    local venv = ""
    if vim.v.shell_error == 0 and output ~= "" then
        venv = vim.fn.trim(output)
    end

    project_venvs[project_root] = venv
    return venv
end

-- Restart Python LSPs only if attached
local function safe_restart_lsp()
    local has_python_lsp = false
    for _, client in pairs(vim.lsp.get_clients()) do
        if client.config and client.config.cmd and client.config.cmd[1]:match("py") then
            has_python_lsp = true
            break
        end
    end
    if not has_python_lsp then return end

    if not lsp_restart_scheduled then
        lsp_restart_scheduled = true
        vim.defer_fn(function()
            vim.cmd("LspRestart")
            lsp_restart_scheduled = false
        end, 50)
    end
end

local function activate_venv(venv, project_root)
    if current_project_root == project_root or venv == "" then
        return
    end

    current_project_root = project_root
    last_venv = venv

    local scripts = (sep == "\\") and "Scripts" or "bin"
    local scripts_path = join(venv, scripts)

    vim.env.VIRTUAL_ENV = venv
    local current_path = vim.env.PATH or ""
    if not current_path:find(scripts_path, 1, true) then
        vim.env.PATH = scripts_path .. path_sep .. current_path
    end

    safe_restart_lsp()
end

-- Only relevant buffers: not special (e.g., Telescope, NvimTree, quickfix)
local function is_relevant_buffer()
    local buftype = vim.api.nvim_buf_get_option(0, "buftype")
    local filetype = vim.api.nvim_buf_get_option(0, "filetype")
    return buftype == "" and filetype == "python"
end

local function check_for_venv_for_buffer(buf_path)
    if not is_relevant_buffer() then return end

    local start_dir = (buf_path ~= "") and buf_path or vim.fn.getcwd()
    local root = find_project_root(start_dir, 20)
    if root then
        local venv = get_venv_path_cached(root)
        activate_venv(venv, root)
    end
end

-- Setup autocmds
function M.setup()
    -- Activate venv before LSP attaches
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function()
            local buf_path = vim.fn.expand("%:p:h")
            check_for_venv_for_buffer(buf_path)
        end,
    })

    -- Handle dynamic switching (BufEnter, DirChanged)
    vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
        callback = function()
            local buf_path = vim.fn.expand("%:p:h")
            check_for_venv_for_buffer(buf_path)
        end,
    })
end

return M
