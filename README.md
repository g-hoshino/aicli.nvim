# aicli.nvim

Run CLI coding agents such as [Claude Code](https://claude.com/claude-code) and
[Codex CLI](https://developers.openai.com/codex/cli) in a floating Neovim
terminal. No plugin dependencies.

- **One session per project.** Each agent starts at the project root of the
  current buffer, and each root keeps its own session.
- **Hiding is not quitting.** The CLI keeps running while its window is hidden.
- **Edited files reload.** Buffers the agent changed on disk are refreshed.
- **Any CLI.** Add a provider entry to get a command and a key for it.

## Requirements

- Neovim 0.11 or newer
- At least one agent CLI on your `$PATH`

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "g-hoshino/aicli.nvim",
  cmd = { "Aicli", "Claude", "Codex" },
  keys = { "<leader>aa", "<leader>ac", "<leader>ax" },
  opts = {},
}
```

With any other plugin manager, call `require("aicli").setup()`. It creates the
provider commands and keys; without it only `:Aicli`, `:AicliToggle` and
`:AicliStatus` exist.

## Usage

| Action | Command | Key |
| --- | --- | --- |
| Pick an installed agent | `:Aicli` | `<leader>aa` |
| Toggle Claude Code | `:Claude` | `<leader>ac` |
| Toggle Codex CLI | `:Codex` | `<leader>ax` |
| Toggle a provider by name | `:AicliToggle {name}` | |
| List sessions and their state | `:AicliStatus` | |

Toggling hides the window when the cursor is in it, and otherwise shows it and
moves the cursor there. Each tab page shows one agent window at a time.

Inside the window, `<C-q>` hides it and `<C-\><C-n>` leaves terminal mode.
`<Esc>` and `<C-e>` are left to the agent.

## Configuration

Defaults:

```lua
require("aicli").setup({
  -- Replaces the default list when set.
  providers = {
    { name = "Claude", cmd = "claude", key = "<leader>ac", command = "Claude" },
    { name = "Codex",  cmd = "codex",  key = "<leader>ax", command = "Codex" },
  },
  select_key = "<leader>aa",
  root_markers = { ".git", ".hg", "pyproject.toml", "Cargo.toml", "package.json", "go.mod" },
  float = { width = 0.5, height = 0.9, border = "rounded" }, -- fractions of the editor
  keys = { normal_mode = false, hide = "<C-q>" },
  start_insert = true,
  close_on_exit = false,
  auto_reload = true,
  env = nil,
  on_open = nil, -- function(term)
  on_exit = nil, -- function(term, code)
})
```

A provider also accepts `args` (extra arguments) and `env` (its own environment
variables). For example, to resume the last Claude Code session:

```lua
{ name = "Claude", cmd = "claude", args = { "--continue" }, key = "<leader>ac", command = "Claude" }
```

## API

```lua
local aicli = require("aicli")
aicli.toggle("Claude")   -- same as :Claude
aicli.open("Claude")     -- show it, starting the CLI if needed
aicli.close("Claude")    -- hide it, leaving the CLI running
aicli.shutdown("Claude") -- stop the CLI
aicli.select()           -- pick via vim.ui.select
aicli.status()           -- report every session
aicli.list()             -- every terminal object
```

See `:help aicli.txt` for every option and highlight group, and run
`:checkhealth aicli` if something does not work.

## License

MIT
