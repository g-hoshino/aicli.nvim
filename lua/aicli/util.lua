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

--- Resolve a size given as a fraction, an absolute cell count, or a function.
---@param value number|fun(total: integer): number|nil
---@param total integer Cells available along that axis.
---@param fallback integer Used when `value` does not resolve to a number.
---@return integer
function M.resolve_size(value, total, fallback)
  -- A user function that errors falls back instead of breaking the layout.
  if type(value) == "function" then
    local ok, result = pcall(value, total)
    value = ok and result or nil
  end

  if type(value) ~= "number" then
    return fallback
  end

  -- 1 is treated as a fraction (the whole axis), not as a single cell.
  if value > 0 and value <= 1 then
    return math.floor(total * value)
  end

  return math.floor(value)
end

return M
