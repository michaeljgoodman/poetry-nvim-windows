local M = {}

local sep = package.config:sub(1, 1)          -- "/" on Unix, "\" on Windows
local path_sep = (sep == "\\") and ";" or ":" -- PATH env separator
local last_venv = nil                         -- Cache last activated virtualenv
local last_project_root = nil                 -- Cache last project root

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

-- Walk up directories until we find poetry.lock
local function find_project_root(start_dir, max_up)
    local dir = start_dir and vim.fn.fnamemodify(start_dir, ":p") or vim.fn.getcwd()
    local depth = 0
    max_up = max_up or 20

    while dir and dir ~= "" and depth < max_up do
        local lockfile = dir .. sep .. "poetry.lock"
        if vim.fn.filereadable(lockfile) == 1 then
            return dir
        end

        if is_root(dir) then break end
        local parent = vim.fn.fnamemodify(dir, ":h")
        if parent == dir then break end -- extra safety
        dir = parent
        depth = depth + 1
    end
    return nil
end

-- Get Poetry virtualenv path, running in project_root
local function get_venv_path(project_root)
    local cmd = { "poetry", "env", "info", "-p", "-C", project_root }

    -- On Windows, run through cmd /c if needed
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


-- Activate virtualenv
local function activate_venv(venv)
    if venv == last_venv or venv == "" then
        print("poetry_venv: venv already active:", last_venv or "none")
        return
    end
    last_venv = venv

    local scripts = (sep == "\\") and "Scripts" or "bin"
    local scripts_path = join(venv, scripts)

    vim.env.VIRTUAL_ENV = venv
    local current_path = vim.env.PATH or ""
    if not current_path:find(scripts_path, 1, true) then
        vim.env.PATH = scripts_path .. path_sep .. current_path
    end

    print("poetry_venv: activated venv:", venv)
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

    if root == last_project_root then
        print("poetry_venv: project already activated, current venv:", last_venv or "none")
        return
    end
    last_project_root = root
    print("poetry_venv: found project root", root)

    local venv = get_venv_path(root)
    if venv ~= "" then
        activate_venv(venv)
    else
        print("poetry_venv: no virtualenv detected for project at " .. root)
    end
end

-- Setup autocmds
function M.setup()
    vim.api.nvim_create_autocmd("VimEnter", { callback = checkForLockfile })
    vim.api.nvim_create_autocmd("BufEnter", { callback = checkForLockfile })
    vim.api.nvim_create_autocmd("DirChanged", { callback = checkForLockfile })
end

return M
