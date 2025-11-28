local M = {}

local sep = package.config:sub(1, 1) -- "/" on Unix, "\" on Windows
local path_sep = (sep == "\\") and ";" or ":" -- for PATH env variable
local last_venv = nil -- Cache to avoid re-activating the same env

local function join(...)
	return table.concat({ ... }, sep)
end

-- Walk up directories until we find poetry.lock
local function find_project_root(start_dir)
	local dir = start_dir or vim.fn.getcwd()
	while dir and dir ~= "/" and dir ~= "" do
		if vim.fn.filereadable(join(dir, "poetry.lock")) == 1 then
			return dir
		end
		dir = vim.fn.fnamemodify(dir, ":h") -- go up one level
	end
	return nil
end

local function get_venv_path()
	local output = vim.fn.system("poetry env info -p 2>/dev/null")
	if vim.v.shell_error ~= 0 then
		return ""
	end
	return vim.fn.trim(output)
end

local function activate_venv(venv)
	if venv == last_venv or venv == "" then
		return
	end
	last_venv = venv

	local scripts = (sep == "\\") and "Scripts" or "bin"
	local scripts_path = join(venv, scripts)

	-- Update env vars for child processes (LSP, linters, :!python, etc.)
	vim.env.VIRTUAL_ENV = venv

	-- Prepend only once
	local current_path = vim.env.PATH or ""
	if not current_path:find(scripts_path, 1, true) then
		vim.env.PATH = scripts_path .. path_sep .. current_path
	end
end

local function checkForLockfile()
	-- Use buffer's path if available, otherwise cwd
	local buf_path = vim.fn.expand("%:p:h")
	local start_dir = (buf_path ~= "") and buf_path or vim.fn.getcwd()

	local root = find_project_root(start_dir)
	if not root then
		return
	end

	local venv = get_venv_path()
	if venv ~= "" then
		activate_venv(venv)
	end
end

function M.setup()
	-- When Neovim finishes startup
	vim.api.nvim_create_autocmd("VimEnter", {
		callback = checkForLockfile,
	})

	-- Works well with autochdir (fires after CWD updates)
	vim.api.nvim_create_autocmd("BufEnter", {
		callback = checkForLockfile,
	})

	-- For explicit :cd, :lcd, :tcd
	vim.api.nvim_create_autocmd("DirChanged", {
		callback = checkForLockfile,
	})
end

return M
