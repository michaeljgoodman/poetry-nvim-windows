local M = {}

local sep = package.config:sub(1, 1)          -- "/" on Unix, "\" on Windows
local path_sep = (sep == "\\" ) and ";" or ":" -- PATH env separator

local last_venv = nil                          -- Cache last activated venv path
local current_project_root = nil               -- Tracks active project root
local lsp_restart_scheduled = false            -- Throttle LSP restarts

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

-- Activate venv if project root changed
local function activate_venv(venv, project_root)
    if current_project_root == project_root then
        -- Already active, skip
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

    -- Throttled LspRestart for Python LSPs
    if not lsp_restart_scheduled then
        lsp_restart_scheduled = true
        vim.defer_fn(function()
            vim.cmd("LspRestart")
            lsp_restart_scheduled = false
        end, 50)
    end
end

-- Check for poetry.lock starting from buffer path
local function check_for_venv_for_buffer(buf_path)
    local start_dir = (buf_path ~= "") and buf_path or vim.fn.getcwd()
    local root = find_project_root(start_dir, 20)
    if not root then
        -- No project here
        return
    end

    local venv = get_venv_path(root)
    activate_venv(venv, root)
end

-- Setup autocmds
function M.setup()
    -- Check on buffer open: pre-activate venv before LSP attaches
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function()
            local buf_path = vim.fn.expand("%:p:h")
            check_for_venv_for_buffer(buf_path)
        end,
    })

    -- Optional: also handle DirChanged or BufEnter for dynamic switching
    vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
        callback = function()
            local buf_path = vim.fn.expand("%:p:h")
            check_for_venv_for_buffer(buf_path)
        end,
    })
end

return M
