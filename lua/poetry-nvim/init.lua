local M = {}

local function checkForLockfile()
	local cwd = vim.fn.getcwd()
	local lockfile = cwd .. "\\poetry.lock"

	if vim.fn.filereadable(lockfile) == 1 then
		local poetry_venv = vim.fn.trim(vim.fn.system("poetry env info -p"))
		if poetry_venv ~= "" then
			local scripts_path = poetry_venv .. "\\Scripts"
			local path_extended = scripts_path .. ";" .. vim.env.PATH
			vim.env.VIRTUAL_ENV = poetry_venv
			vim.env.PATH = path_extended
		end
	end
end

M.setup = function()
	checkForLockfile()
	vim.api.nvim_create_autocmd("DirChanged", {
		callback = checkForLockfile,
	})
end

return M
