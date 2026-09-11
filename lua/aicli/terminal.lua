--- A single CLI session living in a floating window.
---
--- This is the part that replaces toggleterm.nvim. A terminal owns one scratch
--- buffer and one job; the window is created and destroyed as it is toggled, so
--- hiding a terminal never interrupts the CLI running inside it.

local util = require("aicli.util")

---@class AicliTerminal
---@field name string
---@field cmd string[]      Executable plus arguments, passed to jobstart as a list.
---@field cwd string
---@field config table
---@field bufnr integer|nil
---@field winid integer|nil
---@field job_id integer|nil
---@field exit_code integer|nil
local Terminal = {}
Terminal.__index = Terminal

--- Neovim 0.11 replaced termopen() with jobstart({ term = true }).
local has_term_option = vim.fn.has("nvim-0.11") == 1

---@param opts { name: string, cmd: string[], cwd: string, config: table, env: table|nil }
---@return AicliTerminal
function Terminal.new(opts)
  return setmetatable({
    name = opts.name,
    cmd = opts.cmd,
    cwd = opts.cwd,
    config = opts.config,
    env = opts.env,
    bufnr = nil,
    winid = nil,
    job_id = nil,
    exit_code = nil,
  }, Terminal)
end

---@return boolean
function Terminal:buf_valid()
  return self.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.bufnr)
end

---@return boolean
function Terminal:is_open()
  return self.winid ~= nil and vim.api.nvim_win_is_valid(self.winid)
end

---@return boolean True while the CLI process is still running.
function Terminal:is_running()
  return self.job_id ~= nil
end

--- Geometry for `nvim_open_win`, recomputed on every open and on VimResized so
--- the window tracks the editor size instead of freezing at its first layout.
---@return table
function Terminal:win_config()
  local float = self.config.float
  local columns = vim.o.columns
  -- Rows the floating window may occupy: everything but the command line and
  -- the global statusline.
  local lines = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)

  local has_border = float.border ~= nil and float.border ~= "none" and float.border ~= ""
  -- A border is drawn just outside the window: one cell on each side. `edge` is
  -- that one cell, so positions can be expressed against the visible outline
  -- rather than against the text area.
  local edge = has_border and 1 or 0
  local margin = float.margin or 0

  local width = util.resolve_size(float.width, columns, math.floor(columns * 0.5))
  local height = util.resolve_size(float.height, lines, math.floor(lines * 0.9))
  width = math.max(1, math.min(width, columns - 2 * edge))
  height = math.max(1, math.min(height, lines - 2 * edge))

  local col
  if float.col ~= nil then
    col = util.resolve_size(float.col, columns, 0)
  elseif float.anchor == "left" then
    col = margin + edge
  elseif float.anchor == "right" then
    col = columns - width - margin - edge
  else
    col = math.floor((columns - width) / 2)
  end
  col = math.min(math.max(col, edge), columns - width - edge)

  local row
  if float.row ~= nil then
    row = util.resolve_size(float.row, lines, 0)
  else
    row = math.floor((lines - height) / 2)
  end
  row = math.min(math.max(row, edge), lines - height - edge)

  local win_config = {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = has_border and float.border or "none",
    zindex = float.zindex,
  }

  -- nvim_open_win rejects a title when there is no border to draw it on.
  if has_border and float.title then
    win_config.title = " " .. self.name .. " "
    win_config.title_pos = float.title_pos or "center"
  end

  return win_config
end

function Terminal:apply_win_options()
  local win = self.winid
  vim.wo[win].winblend = self.config.float.winblend or 0
  vim.wo[win].winhighlight = "Normal:AicliNormal,FloatBorder:AicliBorder,FloatTitle:AicliTitle"
  vim.wo[win].cursorline = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].spell = false
  vim.wo[win].list = false
end

function Terminal:set_buf_keymaps()
  local keys = self.config.keys
  if keys == false or keys == nil then
    return
  end

  if keys.normal_mode then
    vim.keymap.set("t", keys.normal_mode, [[<C-\><C-n>]], {
      buffer = self.bufnr,
      silent = true,
      desc = "aicli: leave terminal mode",
    })
  end

  if keys.hide then
    vim.keymap.set({ "n", "t" }, keys.hide, function()
      self:close()
    end, {
      buffer = self.bufnr,
      silent = true,
      desc = "aicli: hide terminal",
    })
  end
end

--- Spawn the CLI. The buffer must already be current and displayed, because the
--- pty takes its initial size from the window showing it.
function Terminal:start_job()
  local opts = {
    cwd = self.cwd,
    on_exit = function(_, code)
      self:handle_exit(code)
    end,
  }

  local env = self.config.env
  if self.env then
    env = vim.tbl_extend("force", env or {}, self.env)
  end
  opts.env = env

  local job
  if has_term_option then
    opts.term = true
    job = vim.fn.jobstart(self.cmd, opts)
  else
    job = vim.fn.termopen(self.cmd, opts)
  end

  if job <= 0 then
    util.notify("failed to start " .. table.concat(self.cmd, " "), vim.log.levels.ERROR)
    return false
  end

  self.job_id = job
  self.exit_code = nil
  vim.b[self.bufnr].aicli_provider = self.name
  return true
end

---@param code integer
function Terminal:handle_exit(code)
  self.job_id = nil
  self.exit_code = code

  if self.config.on_exit then
    pcall(self.config.on_exit, self, code)
  end

  if self.config.close_on_exit then
    -- Deferred: the job callback runs while the terminal buffer is still being
    -- torn down, which is not a safe moment to delete it.
    vim.schedule(function()
      self:shutdown()
    end)
  end
end

function Terminal:enter_insert()
  if self.config.start_insert and self:is_running() then
    vim.cmd("startinsert")
  end
end

--- Show the terminal, starting the CLI the first time.
function Terminal:open()
  if self:is_open() then
    vim.api.nvim_set_current_win(self.winid)
    self:enter_insert()
    return
  end

  -- A terminal buffer cannot host a second job once its first one has exited,
  -- so a session that ended is reopened from a fresh buffer. This is what lets
  -- toggling restart a CLI the user quit, instead of showing its dead output
  -- for ever.
  if self:buf_valid() and not self:is_running() then
    pcall(vim.api.nvim_buf_delete, self.bufnr, { force = true })
    self.bufnr = nil
  end

  local fresh = not self:buf_valid()
  if fresh then
    self.bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[self.bufnr].bufhidden = "hide"
  end

  self.winid = vim.api.nvim_open_win(self.bufnr, true, self:win_config())
  self:apply_win_options()

  if fresh then
    if not self:start_job() then
      self:close()
      vim.api.nvim_buf_delete(self.bufnr, { force = true })
      self.bufnr = nil
      return
    end
    self:set_buf_keymaps()
  end

  self:enter_insert()

  if self.config.on_open then
    pcall(self.config.on_open, self)
  end
end

--- Hide the window. The job keeps running and the buffer is kept, so reopening
--- returns to the same session.
function Terminal:close()
  if self:is_open() then
    -- Closing a window from a terminal-mode mapping leaves the editor in a
    -- half-entered insert state; drop back to normal mode first.
    if vim.api.nvim_get_current_win() == self.winid and vim.fn.mode() == "t" then
      vim.cmd("stopinsert")
    end
    pcall(vim.api.nvim_win_close, self.winid, true)
  end
  self.winid = nil
end

function Terminal:toggle()
  if self:is_open() then
    self:close()
  else
    self:open()
  end
end

--- Re-apply the layout, e.g. after the editor was resized.
function Terminal:resize()
  if self:is_open() then
    pcall(vim.api.nvim_win_set_config, self.winid, self:win_config())
  end
end

--- Stop the CLI and drop the buffer. The terminal is unusable afterwards.
function Terminal:shutdown()
  self:close()

  if self.job_id then
    pcall(vim.fn.jobstop, self.job_id)
    self.job_id = nil
  end

  if self:buf_valid() then
    pcall(vim.api.nvim_buf_delete, self.bufnr, { force = true })
  end
  self.bufnr = nil
end

return Terminal
