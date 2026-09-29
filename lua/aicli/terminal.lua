--- A single CLI session living in a floating window.
---
--- A terminal owns one scratch buffer and one job; the window is created and
--- destroyed as it is toggled, so hiding a terminal never interrupts the CLI
--- running inside it.

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

--- Cells kept free between the window's outline and the right edge.
local MARGIN = 5

--- Only records the settings. The buffer, window and job are created lazily by
--- `open()`, so creating a terminal is cheap and starts nothing.
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

--- Handles are checked for validity rather than trusted, because the user can
--- delete the buffer or close the window without going through this module.
---@return boolean
function Terminal:buf_valid()
  return self.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.bufnr)
end

--- Whether the window exists at all, possibly in another tab page.
---@return boolean
function Terminal:has_window()
  return self.winid ~= nil and vim.api.nvim_win_is_valid(self.winid)
end

--- Whether the window is visible in the current tab page. Floats belong to one
--- tab page, so a window elsewhere does not count as open.
---@return boolean
function Terminal:is_open()
  return self:has_window() and vim.api.nvim_win_get_tabpage(self.winid) == vim.api.nvim_get_current_tabpage()
end

--- Whether the cursor is in the window.
---@return boolean
function Terminal:is_focused()
  return self:has_window() and vim.api.nvim_get_current_win() == self.winid
end

--- `job_id` is cleared by the job's own exit callback, so together with a live
--- buffer it doubles as the running flag.
---@return boolean True while the CLI process is still running.
function Terminal:is_running()
  return self:buf_valid() and self.job_id ~= nil
end

--- Geometry for `nvim_open_win`, recomputed on every open and on VimResized so
--- the window tracks the editor size instead of freezing at its first layout.
--- The window sits against the right edge, centred vertically.
---@return table
function Terminal:win_config()
  local float = self.config.float
  local columns = vim.o.columns
  -- Rows the window may cover: everything but the command line and the
  -- statusline of the window below it.
  local lines = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)

  local has_border = float.border ~= "none"
  -- A border is drawn just outside the text area, one cell on each side.
  local edge = has_border and 1 or 0

  -- Clamp the size so the window and its border always fit on screen.
  local width = math.max(1, math.min(math.floor(columns * float.width), columns - 2 * edge))
  local height = math.max(1, math.min(math.floor(lines * float.height), lines - 2 * edge))

  local win_config = {
    relative = "editor",
    width = width,
    height = height,
    col = math.max(edge, columns - width - edge - MARGIN),
    row = math.floor((lines - height) / 2),
    style = "minimal",
    border = float.border,
  }

  -- nvim_open_win rejects a title when there is no border to draw it on.
  if has_border then
    win_config.title = (" %s · %s "):format(self.name, vim.fs.basename(self.cwd))
    win_config.title_pos = "center"
  end

  return win_config
end

--- Window-local options for the float: route its highlights through the
--- Aicli* groups and keep editor decorations out of the terminal output.
function Terminal:apply_win_options()
  local win = self.winid
  vim.wo[win].winhighlight = "Normal:AicliNormal,FloatBorder:AicliBorder,FloatTitle:AicliTitle"
  -- Keep :edit and friends from replacing the terminal inside this window.
  vim.wo[win].winfixbuf = true
  -- style = "minimal" turns off numbers, cursorline, spell and list, but leaves
  -- the sign column on "auto".
  vim.wo[win].signcolumn = "no"
end

--- Buffer-local keys, so they exist only inside this terminal. Called once per
--- buffer, right after its job starts.
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
    term = true,
    cwd = self.cwd,
    -- Only the current job owns this terminal's state. The exit of a job that
    -- was already replaced (shutdown() then open()) must not touch it.
    on_exit = function(id, code)
      if id == self.job_id then
        self:handle_exit(code)
      end
    end,
  }

  -- Provider-specific variables override the ones shared by every provider.
  local env = self.config.env
  if self.env then
    env = vim.tbl_extend("force", env or {}, self.env)
  end
  opts.env = env

  -- jobstart() returns <= 0 for a bad command but raises for other errors,
  -- such as a cwd that was deleted after the session first started.
  local ok, job = pcall(vim.fn.jobstart, self.cmd, opts)
  if not ok or job <= 0 then
    local reason = ok and "" or (": " .. tostring(job))
    util.notify("failed to start " .. table.concat(self.cmd, " ") .. reason, vim.log.levels.ERROR)
    return false
  end

  self.job_id = job
  self.exit_code = nil
  return true
end

--- Record the exit so `open()` knows to restart the CLI, then run the hook.
---@param code integer
function Terminal:handle_exit(code)
  self.job_id = nil
  self.exit_code = code

  -- User hooks run under pcall so an error in them cannot leave the terminal
  -- in an inconsistent state.
  if self.config.on_exit then
    pcall(self.config.on_exit, self, code)
  end

  if self.config.close_on_exit then
    -- Deferred: the job callback runs while the terminal buffer is still being
    -- torn down, which is not a safe moment to delete it. By then a new session
    -- may have been started, and that one must be left alone.
    vim.schedule(function()
      if not self:is_running() then
        self:shutdown()
      end
    end)
  end
end

--- Terminal mode is only entered while the CLI is alive; the output of an
--- exited job is left to read in normal mode.
function Terminal:enter_insert()
  if self.config.start_insert and self:is_running() then
    vim.cmd("startinsert")
  end
end

--- Show the terminal, starting the CLI when no session is running.
function Terminal:open()
  -- Already visible with a live CLI: just focus it.
  if self:is_open() and self:is_running() then
    vim.api.nvim_set_current_win(self.winid)
    self:enter_insert()
    return
  end

  -- A window left open in another tab page, or one still showing a session
  -- that ended, is closed so a live session is shown here instead.
  self:close()

  -- A terminal buffer cannot host a second job once its first one has exited,
  -- so a session that ended is reopened from a fresh buffer. This is what lets
  -- toggling restart a CLI the user quit, instead of showing its dead output
  -- for ever.
  -- The new buffer is an unlisted scratch buffer. `bufhidden = hide` keeps
  -- it, and the job in it, alive after its window is closed.
  local start = not self:is_running()
  if start then
    self:delete_buffer()
    self.bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[self.bufnr].bufhidden = "hide"
  end

  self.winid = vim.api.nvim_open_win(self.bufnr, true, self:win_config())
  self:apply_win_options()

  -- The job can only start now that the buffer is shown (see start_job()).
  -- If it fails, shutdown() drops the half-built window and buffer so the
  -- next open() starts from a clean state.
  if start then
    if not self:start_job() then
      self:shutdown()
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
  if self:has_window() then
    -- Closing a window from a terminal-mode mapping leaves the editor in a
    -- half-entered insert state; drop back to normal mode first.
    if vim.api.nvim_get_current_win() == self.winid and vim.fn.mode() == "t" then
      vim.cmd("stopinsert")
    end
    pcall(vim.api.nvim_win_close, self.winid, true)
  end
  -- Also forget a handle the user already closed by other means (:q, ...).
  self.winid = nil
end

--- Hide the window when the cursor is in it; otherwise show it and move there.
function Terminal:toggle()
  if self:is_focused() then
    self:close()
  else
    self:open()
  end
end

--- Re-apply the layout, e.g. after the editor was resized.
function Terminal:resize()
  if self:has_window() then
    pcall(vim.api.nvim_win_set_config, self.winid, self:win_config())
  end
end

function Terminal:delete_buffer()
  if self:buf_valid() then
    pcall(vim.api.nvim_buf_delete, self.bufnr, { force = true })
  end
  self.bufnr = nil
end

--- Stop the CLI and drop the buffer. `job_id` is cleared by the job's own exit
--- callback, which also runs the `on_exit` hook.
function Terminal:shutdown()
  self:close()

  if self.job_id then
    pcall(vim.fn.jobstop, self.job_id)
  end

  self:delete_buffer()
end

return Terminal
