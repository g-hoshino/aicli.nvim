--- aicli.nvim - CLI-based LLMs (Claude Code, Codex CLI, ...) in a floating
--- terminal, built on Neovim's own window and job APIs.
---
--- Public entry points: `setup()`, `toggle()`, `open()`, `close()`, `select()`,
--- `status()`. Everything else is an implementation detail.

local Config = require("aicli.config")
local Terminal = require("aicli.terminal")
local util = require("aicli.util")

local M = {}

--- Live terminals, keyed by provider name and project root, so the same CLI
--- keeps one session per project.
---@type table<string, AicliTerminal>
local terminals = {}

--- Provider whose terminal was opened last. Reported by :AicliStatus.
---@type string|nil
local active = nil

local augroup = vim.api.nvim_create_augroup("aicli", { clear = true })

---@param name string
---@param cwd string
---@return string
local function terminal_key(name, cwd)
  return name .. "\0" .. cwd
end

---@param name string
---@return AicliProvider|nil
local function find_provider(name)
  for _, provider in ipairs(Config.get().providers) do
    if provider.name == name then
      return provider
    end
  end
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

--- The terminal for `provider` in the current project, created on demand.
---@param provider AicliProvider
---@return AicliTerminal|nil
local function get_terminal(provider)
  if not util.executable(provider.cmd) then
    util.notify(provider.cmd .. " was not found in $PATH", vim.log.levels.ERROR)
    return nil
  end

  local config = Config.get()
  local cwd = util.project_root(config.root_markers)
  local key = terminal_key(provider.name, cwd)

  local term = terminals[key]
  if term and term:buf_valid() then
    return term
  end

  local cmd = { provider.cmd }
  for _, arg in ipairs(provider.args or {}) do
    table.insert(cmd, arg)
  end

  term = Terminal.new({
    name = provider.name,
    cmd = cmd,
    cwd = cwd,
    config = config,
    env = provider.env,
  })
  terminals[key] = term
  return term
end

---@param name string
---@return AicliTerminal|nil
local function resolve(name)
  local provider = find_provider(name)
  if not provider then
    util.notify(name .. " is not a configured provider", vim.log.levels.ERROR)
    return nil
  end
  return get_terminal(provider)
end

--- Show a provider's terminal, starting its CLI on first use.
---@param name string Provider display name, e.g. "Claude".
function M.open(name)
  local term = resolve(name)
  if term then
    active = name
    term:open()
  end
end

--- Hide a provider's terminal without stopping the CLI.
---@param name string
function M.close(name)
  local term = resolve(name)
  if term then
    term:close()
  end
end

---@param name string
function M.toggle(name)
  local term = resolve(name)
  if not term then
    return
  end

  if term:is_open() then
    term:close()
  else
    active = name
    term:open()
  end
end

--- Stop a provider's CLI and discard its buffer.
---@param name string
function M.shutdown(name)
  local term = resolve(name)
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

--- Report the provider whose terminal was opened last.
function M.status()
  if not active then
    util.notify("no terminal has been opened yet")
    return
  end

  local term = resolve(active)
  local state = "not running"
  if term then
    if term:is_running() then
      state = term:is_open() and "running, visible" or "running, hidden"
    elseif term.exit_code then
      state = "exited with " .. term.exit_code
    end
  end

  util.notify(("%s (%s)"):format(active, state))
end

--- Every live terminal, for users writing their own statusline or commands.
---@return AicliTerminal[]
function M.list()
  return vim.tbl_values(terminals)
end

local function define_highlights()
  vim.api.nvim_set_hl(0, "AicliNormal", { link = "NormalFloat", default = true })
  vim.api.nvim_set_hl(0, "AicliBorder", { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, "AicliTitle", { link = "FloatTitle", default = true })
end

---@param config table
local function define_provider_mappings(config)
  for _, provider in ipairs(config.providers) do
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
  -- whenever focus comes back or a terminal is left.
  vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "TermClose" }, {
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
  define_highlights()
  define_provider_mappings(config)
  define_autocmds(config)
end

return M
