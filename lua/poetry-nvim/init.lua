local M = {}

local sep = package.config:sub(1, 1)          -- "/" on Unix, "\" on Windows
local path_sep = (sep == "\\" ) and ";" or ":" -- PATH env separator

local last_venv = nil                          -- Cache last activated venv path
local current_project_root = nil               -- Tracks active project root
local restarting_lsp = false                   -- Prevent overlapping LspRestart

local function join(...) 
    return table.concat({ ... }, sep) 
end

-- Detect if dir is root
local function is_root(dir)
    if sep == "\\" then
        return dir:match("^%a:\\$") ~= nil
    else
        return dir == "/"
    end
end

-- Walk up directories to find poetry.lock
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

-- Get Poetry virtualenv path using -C
local function get_venv_path(project_root)
    local cmd = { "poetry", "env", "info", "-p", "-C", project_root }
    if sep == "\\" then
        cmd = { "cmd", "/c", table.concat(cmd, " ") }
    end

    local output = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 or output == "" then
        print("poetry_venv: failed to get venv path for project at " .. project_root)
        return ""
    end
    return vim.fn.trim(output)
end

-- Safely restart Python LSPs
local function safe_lsp_restart()
    if restarting_lsp then return end

    local clients_to_restart = {}
    for _, client in pairs(vim.lsp.get_clients()) do
        if client.config and client.config.cmd and client.config.cmd[1]:match("py") then
            table.insert(clients_to_restart, client.id)
        end
    end

    if #clients_to_restart == 0 then return end

    restarting_lsp = true
    vim.schedule(function()
        for _, id in ipairs(clients_to_restart) do
            vim.lsp.stop_client(id)
        end
        vim.defer_fn(function()
            -- Reattach buffers to restart LSP
            vim.cmd("edit")
            restarting_lsp = false
        end, 100)
    end)
end

-- Activate venv if project root changed
local function activate_venv(venv, project_root)
    if current_project_root == project_root then
        print("poetry_venv: project already active, skipping activation")
        return
    end

    if venv == "" then
        print("poetry_venv: no venv found, skipping activation")
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

    print("poetry_venv: activated venv:", venv)

    safe_lsp_restart()
end

-- Check for poetry.lock and activate venv
local function checkForLockfile()
    local buf_path = vim.fn.expand("%:p:h")
    local start_dir = (buf_path ~= "") and buf_path or vim.fn.getcwd()
    print("poetry_venv: checking from", start_dir)

    local root = find_project_root(start_dir, 20)
    if not root then
        print("poetry_venv: no poetry.lock found")
        return
    end

    local venv = get_venv_path(root)
    activate_venv(venv, root)
end

-- Pre-init: run immediately on module load to set venv for first LSP attach
local function pre_init()
    local buf_path = vim.fn.expand("%:p:h")
    local start_dir = (buf_path ~= "") and buf_path or vim.fn.getcwd()
    local root = find_project_root(start_dir, 20)
    if root then
        local venv = get_venv_path(root)
        activate_venv(venv, root)
    end
end

-- Setup autocmds for dynamic switching
function M.setup()
    vim.api.nvim_create_autocmd("VimEnter", { callback = checkForLockfile })
    vim.api.nvim_create_autocmd("BufEnter", { callback = checkForLockfile })
    vim.api.nvim_create_autocmd("DirChanged", { callback = checkForLockfile })
end

pre_init()

return M
