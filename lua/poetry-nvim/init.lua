local M = {}

local sep = package.config:sub(1, 1) -- "/" on Unix, "\" on Windows
local last_venv = nil -- Cache to avoid re-activating the same env

local function join(...)
	return table.concat({ ... }, sep)
end

local function get_venv_path()
	local output = vim.fn.system("poetry env info -p")
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
		vim.env.PATH = scripts_path .. sep .. current_path
	end
end

local function checkForLockfile()
	local cwd = vim.fn.getcwd()
	local lockfile = join(cwd, "poetry.lock")

	if vim.fn.filereadable(lockfile) == 1 then
		local venv = get_venv_path()
		if venv ~= "" then
			activate_venv(venv)
		end
	end
end

function M.setup()
	-- When Neovim finishes startup (important for nvim <dir>)
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
