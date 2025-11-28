local M = {}

local sep = package.config:sub(1, 1)      -- "/" on Unix, "\" on Windows
local path_sep = (sep == "\\") and ";" or ":" -- PATH env separator
local last_venv = nil                     -- Cache last activated virtualenv
local last_project_root = nil             -- Cache last project root

local function join(...)
    return table.concat({ ... }, sep)
end

-- Walk up directories until we find poetry.lock (limit + Windows-safe root)
local function find_project_root(start_dir, max_up)
    local dir = start_dir or vim.fn.getcwd()
    local depth = 0
    max_up = max_up or 20

    while dir and dir ~= "" and depth < max_up do
        if vim.fn.filereadable(join(dir, "poetry.lock")) == 1 then
            return dir
        end

        local parent = vim.fn.fnamemodify(dir, ":h")
        -- Stop if we've reached root (Unix "/" or Windows "C:\", "D:\", etc.)
        if parent == dir then
            break
        end

        dir = parent
        depth = depth + 1
    end

    return nil
end

-- Get Poetry virtualenv path
local function get_venv_path()
    local output = vim.fn.system("poetry env info -p 2>/dev/null")
    if vim.v.shell_error ~= 0 then
        return ""
    end
    return vim.fn.trim(output)
end

-- Activate virtualenv
local function activate_venv(venv)
    if venv == last_venv or venv == "" then
        return
    end
    last_venv = venv

    local scripts = (sep == "\\") and "Scripts" or "bin"
    local scripts_path = join(venv, scripts)

    -- Update env vars for child processes (LSP, linters, :!python, etc.)
    vim.env.VIRTUAL_ENV = venv

    -- Prepend to PATH only once
    local current_path = vim.env.PATH or ""
    if not current_path:find(scripts_path, 1, true) then
        vim.env.PATH = scripts_path .. path_sep .. current_path
    end
end

-- Check for poetry.lock and activate venv
local function checkForLockfile()
    local buf_path = vim.fn.expand("%:p:h")
    local start_dir = (buf_path ~= "") and buf_path or vim.fn.getcwd()

    local root = find_project_root(start_dir, 20)
    if not root then return end

    -- Avoid re-checking the same project
    if root == last_project_root then return end
    last_project_root = root

    local venv = get_venv_path()
    if venv ~= "" then
        activate_venv(venv)
    end
end

-- Setup autocmds
function M.setup()
    -- On Neovim startup
    vim.api.nvim_create_autocmd("VimEnter", {
        callback = checkForLockfile,
    })

    -- When switching buffers (works well with autochdir)
    vim.api.nvim_create_autocmd("BufEnter", {
        callback = checkForLockfile,
    })

    -- When directory changes explicitly (:cd, :lcd, :tcd)
    vim.api.nvim_create_autocmd("DirChanged", {
        callback = checkForLockfile,
    })
end

return M
