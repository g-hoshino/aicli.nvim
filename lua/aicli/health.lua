--- :checkhealth aicli

local M = {}

function M.check()
  local health = vim.health
  health.start("aicli.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10 or newer is required")
  end

  local Config = require("aicli.config")
  if Config.is_configured() then
    health.ok("setup() has been called")
  else
    health.warn("setup() has not been called", {
      "Provider commands and keymaps are only created by setup().",
      "Without it, only :Aicli, :AicliToggle and :AicliStatus exist.",
    })
  end

  local providers = Config.get().providers
  if #providers == 0 then
    health.error("no providers are configured")
    return
  end

  local found = 0
  for _, provider in ipairs(providers) do
    local path = vim.fn.exepath(provider.cmd)
    if path ~= "" then
      found = found + 1
      health.ok(("%s: %s"):format(provider.name, path))
    else
      health.warn(("%s: %s was not found in $PATH"):format(provider.name, provider.cmd))
    end
  end

  if found == 0 then
    health.error("none of the configured CLIs are installed")
  end
end

return M
