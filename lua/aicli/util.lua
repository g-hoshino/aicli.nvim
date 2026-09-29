--- Small helpers shared by the other modules.

local M = {}

--- Whether `cmd` can be found in $PATH.
---@param cmd string
---@return boolean
function M.executable(cmd)
  return vim.fn.executable(cmd) == 1
end

--- `vim.notify` with the plugin's title, so messages are recognisable.
---@param msg string
---@param level? integer One of vim.log.levels. Defaults to INFO.
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "aicli.nvim" })
end

--- Directory the terminal should start in.
---
--- Search upwards from the current file so that opening a CLI from a buffer
--- gives it that project, not wherever Neovim happened to be started. Terminal,
--- help and other special buffers have no meaningful path, so they fall back to
--- the cwd.
---@param markers string[]
---@return string
function M.project_root(markers)
  local cwd = vim.fn.getcwd()
  local start = cwd

  -- Only normal buffers with a name are backed by a real file.
  if vim.bo.buftype == "" then
    local name = vim.api.nvim_buf_get_name(0)
    if name ~= "" then
      start = vim.fs.dirname(name)
    end
  end

  return vim.fs.root(start, markers) or cwd
end

return M
