local M = {}

local sep = package.config:sub(1, 1)
local path_sep = (sep == "\\") and ";" or ":"

local last_venv = nil
local current_project_root = nil
local lsp_restart_scheduled = false

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

local function get_venv_path(project_root)
    local cmd = { "poetry", "env", "info", "-p", "-C", project_root }
    if sep == "\\" then
        cmd = { "cmd", "/c", table.concat(cmd, " ") }
    end

    local output = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 or output == "" then
        return ""
    end
    return vim.fn.trim(output)
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

    if not lsp_restart_scheduled then
        lsp_restart_scheduled = true
        vim.defer_fn(function()
            vim.cmd("LspRestart")
            lsp_restart_scheduled = false
        end, 50)
    end
end

local function check_for_venv_for_buffer(buf_path)
    local start_dir = (buf_path ~= "") and buf_path or vim.fn.getcwd()
    local root = find_project_root(start_dir, 20)
    if root then
        local venv = get_venv_path(root)
        activate_venv(venv, root)
    end
end

function M.setup()
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function()
            local buf_path = vim.fn.expand("%:p:h")
            check_for_venv_for_buffer(buf_path)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
        callback = function()
            local buf_path = vim.fn.expand("%:p:h")
            check_for_venv_for_buffer(buf_path)
        end,
    })
end

return M
