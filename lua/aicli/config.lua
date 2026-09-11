--- Configuration handling for aicli.nvim.
---
--- `M.defaults` documents every option. `M.setup()` merges user options on top
--- and is the only place that decides what the rest of the plugin sees.

local M = {}

---@class AicliProvider
---@field name string        Display name. Shown in the picker, the border title and :AicliStatus.
---@field cmd string         Executable looked up in $PATH. Providers not found are skipped.
---@field args? string[]     Extra arguments passed to the executable.
---@field key? string|false  Normal-mode toggle key. Omit or set to false for none.
---@field command? string|false User command name to create. Omit or set to false for none.
---@field env? table<string,string> Extra environment variables for this provider only.

M.defaults = {
  --- LLM CLIs to manage. Replaced wholesale when set (not merged element-wise),
  --- so listing your own providers overrides the defaults below.
  ---@type AicliProvider[]
  providers = {
    { name = "Claude", cmd = "claude", key = "<leader>ac", command = "Claude" },
    { name = "Codex", cmd = "codex", key = "<leader>ax", command = "Codex" },
  },

  --- Normal-mode key that opens the provider picker. false disables it.
  select_key = "<leader>aa",

  --- Files or directories that mark a project root. The first match walking up
  --- from the current buffer wins; the cwd is used when nothing matches.
  root_markers = { ".git", ".hg", "pyproject.toml", "Cargo.toml", "package.json", "go.mod" },

  --- Floating window geometry and appearance.
  --- Sizes accept a fraction of the editor (0 < n <= 1), an absolute cell count
  --- (n > 1), or a function receiving the available cells and returning either.
  float = {
    anchor = "right", ---@type "left"|"center"|"right" Ignored when `col` is set.
    width = 0.5,
    height = 0.9,
    margin = 5, --- Cells kept between the window and the screen edge for left/right.
    row = nil, --- Explicit row. nil centres vertically.
    col = nil, --- Explicit column. nil uses `anchor`.
    border = "rounded", ---@type string|string[] Any value `nvim_open_win` accepts.
    title = true, --- Show the provider name in the border. Needs a border.
    title_pos = "center", ---@type "left"|"center"|"right"
    winblend = 0,
    zindex = 50,
  },

  --- Buffer-local keys inside an aicli terminal. Set the table to false to bind
  --- nothing, or an individual entry to false to skip just that key.
  keys = {
    normal_mode = "<Esc><Esc>", --- Leave terminal mode.
    hide = "<C-e>", --- Hide the window, keeping the session running.
  },

  --- Enter terminal mode when the window opens.
  start_insert = true,

  --- Close the window and drop the buffer once the CLI exits. When false the
  --- final output stays readable until the terminal is toggled again.
  close_on_exit = false,

  --- Run :checktime when focus returns, so buffers edited by the CLI reload.
  --- Requires 'autoread' (on by default).
  auto_reload = true,

  --- Extra environment variables for every provider.
  ---@type table<string,string>|nil
  env = nil,

  --- Hooks. `term` is the terminal object (see lua/aicli/terminal.lua).
  ---@type fun(term: table)|nil
  on_open = nil,
  ---@type fun(term: table, code: integer)|nil
  on_exit = nil,
}

---@type table|nil
local config = nil

--- Reject configuration mistakes early, where the message can still point at
--- the offending entry.
local function validate(cfg)
  if type(cfg.providers) ~= "table" then
    error("aicli.nvim: `providers` must be a list of provider tables")
  end

  local seen = {}
  for index, provider in ipairs(cfg.providers) do
    local where = ("aicli.nvim: providers[%d]"):format(index)
    if type(provider.name) ~= "string" or provider.name == "" then
      error(where .. " is missing a `name`")
    end
    if type(provider.cmd) ~= "string" or provider.cmd == "" then
      error(where .. " (" .. provider.name .. ") is missing a `cmd`")
    end
    if seen[provider.name] then
      error(where .. ": duplicate provider name " .. provider.name)
    end
    seen[provider.name] = true
  end
end

--- Merge user options over the defaults and remember the result.
---@param opts table|nil
---@return table
function M.setup(opts)
  opts = opts or {}
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)

  -- `providers` is a list: a deep merge would splice user entries into the
  -- default ones by index. Replace it instead.
  if opts.providers ~= nil then
    merged.providers = vim.deepcopy(opts.providers)
  end

  -- `keys = false` has to survive the merge as a plain false.
  if opts.keys == false then
    merged.keys = false
  end

  validate(merged)
  config = merged
  return config
end

--- The active configuration, falling back to the defaults when `setup()` was
--- never called. This is what lets :Aicli work with no configuration at all.
---@return table
function M.get()
  if not config then
    return M.setup({})
  end
  return config
end

---@return boolean
function M.is_configured()
  return config ~= nil
end

return M
