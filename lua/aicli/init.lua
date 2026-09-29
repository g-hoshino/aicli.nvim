--- aicli.nvim - CLI-based LLMs (Claude Code, Codex CLI, ...) in a floating
--- terminal, built on Neovim's own window and job APIs.
---
--- Public entry points: `setup()`, `toggle()`, `open()`, `close()`,
--- `shutdown()`, `select()`, `status()`, `list()`. Everything else is an
--- implementation detail.

local Config = require("aicli.config")
local Terminal = require("aicli.terminal")
local util = require("aicli.util")

local M = {}

--- Terminals started so far, keyed by provider name and project root, so the
--- same CLI keeps one session per project.
---@type table<string, AicliTerminal>
local terminals = {}

--- Group for every autocmd this module creates, so a repeated `setup()` can
--- replace them instead of stacking duplicates.
local augroup = vim.api.nvim_create_augroup("aicli", { clear = true })

--- Key into `terminals`. NUL is used as the separator because it cannot occur
--- in a path, so distinct (name, cwd) pairs do not produce the same key.
---@param name string
---@param cwd string
---@return string
local function terminal_key(name, cwd)
  return name .. "\0" .. cwd
end

--- Look up a provider by its display name, reporting unknown names.
---@param name string
---@return AicliProvider|nil
local function find_provider(name)
  for _, provider in ipairs(Config.get().providers) do
    if provider.name == name then
      return provider
    end
  end
  util.notify(name .. " is not a configured provider", vim.log.levels.ERROR)
  return nil
end

--- Providers whose executable is actually installed.
---@return AicliProvider[]
local function available_providers()
  local available = {}
  for _, provider in ipairs(Config.get().providers) do
    if util.executable(provider.cmd) then
      table.insert(available, provider)
    end
  end
  return available
end

--- The project the current buffer belongs to. An aicli terminal has no file
--- path to search from, so it belongs to the project it was started in.
---@param markers string[]
---@return string
local function current_project(markers)
  local bufnr = vim.api.nvim_get_current_buf()
  for _, term in pairs(terminals) do
    if term.bufnr == bufnr then
      return term.cwd
    end
  end
  return util.project_root(markers)
end

--- The terminal `name` has in the current project, or nil when none was
--- started there. The project root is returned too, for creating one.
---@param name string
---@return AicliTerminal|nil term
---@return string cwd
local function find_terminal(name)
  local cwd = current_project(Config.get().root_markers)
  return terminals[terminal_key(name, cwd)], cwd
end

--- The terminal for `name` in the current project, created on demand.
---@param name string
---@return AicliTerminal|nil
local function get_terminal(name)
  local provider = find_provider(name)
  if not provider then
    return nil
  end

  -- Reuse the session while its buffer is alive. Once the buffer is gone
  -- (shutdown(), :bwipeout, ...) a new terminal takes over the slot.
  local term, cwd = find_terminal(name)
  if term and term:buf_valid() then
    return term
  end

  if not util.executable(provider.cmd) then
    util.notify(provider.cmd .. " was not found in $PATH", vim.log.levels.ERROR)
    return nil
  end

  -- The command is kept as a list so jobstart() runs it without a shell and
  -- arguments need no quoting.
  local cmd = { provider.cmd }
  for _, arg in ipairs(provider.args or {}) do
    table.insert(cmd, arg)
  end

  term = Terminal.new({
    name = provider.name,
    cmd = cmd,
    cwd = cwd,
    config = Config.get(),
    env = provider.env,
  })
  terminals[terminal_key(name, cwd)] = term
  return term
end

--- Show `term`, hiding the other aicli windows in this tab page first. They all
--- take the same position, so a second one would only cover the first. Hiding
--- keeps their CLIs running.
---@param term AicliTerminal
local function show(term)
  for _, other in pairs(terminals) do
    if other ~= term and other:is_open() then
      other:close()
    end
  end
  term:open()
end

--- Show a provider's terminal, starting its CLI on first use.
---@param name string Provider display name, e.g. "Claude".
function M.open(name)
  local term = get_terminal(name)
  if term then
    show(term)
  end
end

--- Hide a provider's terminal without stopping the CLI.
---@param name string
function M.close(name)
  local term = find_terminal(name)
  if term then
    term:close()
  end
end

--- Hide a provider's terminal when the cursor is in it; otherwise show it and
--- move there, including when it is visible but another window has focus.
---@param name string
function M.toggle(name)
  local term = get_terminal(name)
  if not term then
    return
  end

  if term:is_focused() then
    term:close()
  else
    show(term)
  end
end

--- Stop a provider's CLI and discard its buffer.
---@param name string
function M.shutdown(name)
  local term = find_terminal(name)
  if term then
    term:shutdown()
  end
end

--- Pick among the installed providers and toggle the chosen one. Uses
--- `vim.ui.select`, so it follows whatever picker the user has installed.
function M.select()
  local available = available_providers()

  if #available == 0 then
    util.notify("no configured LLM CLI was found in $PATH", vim.log.levels.ERROR)
    return
  end

  local names = vim.tbl_map(function(provider)
    return provider.name
  end, available)

  vim.ui.select(names, { prompt = "LLM terminal" }, function(choice)
    if choice then
      M.toggle(choice)
    end
  end)
end

---@param term AicliTerminal
---@return string
local function describe(term)
  local state = "not running"
  if term:is_running() then
    state = term:is_open() and "running, visible" or "running, hidden"
  elseif term.exit_code then
    state = "exited with " .. term.exit_code
  end
  return ("%s  %s  (%s)"):format(term.name, vim.fn.fnamemodify(term.cwd, ":~"), state)
end

--- Report every terminal started so far, with its project and state.
function M.status()
  local lines = vim.tbl_map(describe, vim.tbl_values(terminals))
  if #lines == 0 then
    util.notify("no terminal has been started yet")
    return
  end

  table.sort(lines)
  util.notify(table.concat(lines, "\n"))
end

--- Every terminal started so far, running or not, for users writing their own
--- statusline or commands.
---@return AicliTerminal[]
function M.list()
  return vim.tbl_values(terminals)
end

--- Link the plugin's groups to the standard float groups. `default = true`
--- leaves any definition from the colour scheme or the user in place.
local function define_highlights()
  vim.api.nvim_set_hl(0, "AicliNormal", { link = "NormalFloat", default = true })
  vim.api.nvim_set_hl(0, "AicliBorder", { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, "AicliTitle", { link = "FloatTitle", default = true })
end

--- Create the per-provider user commands and keymaps, plus the picker key.
---@param config table
local function define_provider_mappings(config)
  for _, provider in ipairs(config.providers) do
    -- One closure per provider, shared by its command and its keymap.
    local function toggle()
      M.toggle(provider.name)
    end

    if provider.command then
      vim.api.nvim_create_user_command(provider.command, toggle, {
        desc = "Toggle the " .. provider.name .. " terminal",
      })
    end

    if provider.key then
      vim.keymap.set("n", provider.key, toggle, {
        silent = true,
        desc = "Toggle the " .. provider.name .. " terminal",
      })
    end
  end

  if config.select_key then
    vim.keymap.set("n", config.select_key, M.select, {
      silent = true,
      desc = "Choose an LLM terminal",
    })
  end
end

---@param config table
local function define_autocmds(config)
  -- Start from an empty group so calling setup() again does not add
  -- duplicate handlers.
  vim.api.nvim_clear_autocmds({ group = augroup })

  -- Keep open windows proportional to the editor.
  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      for _, term in pairs(terminals) do
        term:resize()
      end
    end,
  })

  -- Colour scheme changes wipe highlight groups; re-link ours.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = define_highlights,
  })

  if not config.auto_reload then
    return
  end

  -- A CLI editing files behind Neovim's back leaves buffers stale. Check them
  -- whenever focus comes back or a terminal is left, and also on BufEnter and
  -- CursorHold, since a hidden CLI keeps editing while the user works here.
  vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "TermClose", "BufEnter", "CursorHold" }, {
    group = augroup,
    callback = function()
      -- :checktime is not allowed while the command-line window is open.
      if vim.fn.getcmdwintype() == "" then
        vim.cmd("checktime")
      end
    end,
  })
end

--- Apply configuration and create the provider commands, keymaps and autocmds.
--- Calling this is what turns `providers` into `:Claude` and `<leader>ac`.
---@param opts table|nil See `require("aicli.config").defaults`.
function M.setup(opts)
  local config = Config.setup(opts)
  define_provider_mappings(config)
  define_autocmds(config)
end

-- The commands in plugin/aicli.lua work without setup(), so highlights and
-- autocmds have to be in place as soon as this module is loaded.
define_highlights()
define_autocmds(Config.get())

return M
