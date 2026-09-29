--- Commands that work without calling setup(), so the plugin is usable as soon
--- as it is installed. Provider commands and keymaps are created by setup(),
--- which is where the user opts into having keys bound for them.

-- Define the commands only once, even if this file is sourced again.
if vim.g.loaded_aicli then
  return
end
vim.g.loaded_aicli = true

-- The plugin relies on jobstart({ term = true }), added in Neovim 0.11.
if vim.fn.has("nvim-0.11") == 0 then
  vim.notify("aicli.nvim requires Neovim 0.11 or newer", vim.log.levels.ERROR, { title = "aicli.nvim" })
  return
end

--- Provider names, for command completion. A Lua `complete` function gets no
--- filtering from Neovim, so the prefix already typed is matched here.
---@param arg_lead string
---@return string[]
local function provider_names(arg_lead)
  local names = {}
  for _, provider in ipairs(require("aicli.config").get().providers) do
    if arg_lead == "" or vim.startswith(provider.name, arg_lead) then
      table.insert(names, provider.name)
    end
  end
  return names
end

-- The modules are required inside the callbacks, so they are loaded on first
-- use rather than at startup.
vim.api.nvim_create_user_command("Aicli", function()
  require("aicli").select()
end, { desc = "Choose an LLM terminal" })

vim.api.nvim_create_user_command("AicliToggle", function(args)
  require("aicli").toggle(args.args)
end, {
  nargs = 1,
  complete = provider_names,
  desc = "Toggle the terminal of the named provider",
})

vim.api.nvim_create_user_command("AicliStatus", function()
  require("aicli").status()
end, { desc = "Show every started LLM terminal" })
