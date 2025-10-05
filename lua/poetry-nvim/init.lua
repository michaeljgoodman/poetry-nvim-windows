local M = {}

local checkForLockfile = function()
  local match = vim.fn.glob(vim.fn.getcwd() .. "/poetry.lock")
  if match ~= "" then
    local poetry_venv = vim.fn.trim(vim.fn.system("poetry env info -p"))
    local path_extended = string.format("%s/bin:%s", poetry_venv, vim.env.PATH)
    vim.env.VIRTUAL_ENV = poetry_venv
    vim.env.PATH = path_extended
  end
end

M.setup = function()
  -- run on startup
  checkForLockfile()
  -- and when changing directory
  vim.api.nvim_create_autocmd({ "DirChanged" }, {
    callback = function()
      checkForLockfile()
    end,
  })
end

return M
