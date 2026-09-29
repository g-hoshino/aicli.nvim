# aicli.nvim

Run CLI-based LLM coding agents — [Claude Code](https://claude.com/claude-code),
[Codex CLI](https://developers.openai.com/codex/cli), or anything else that
lives in your terminal — inside a floating Neovim window.

<!--
  Demo GIF goes here, e.g.
  <p align="center"><img src="https://github.com/user-attachments/assets/..." alt="aicli.nvim demo" width="800"></p>
  Suggested script: open a file, <leader>ac, let the agent edit it, <C-e> to
  hide (the buffer reloads), <leader>ac to come back to the same conversation.
-->

## Quick start

Install with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "g-hoshino/aicli.nvim", opts = {} }
```

Then, in any file of a project:

1. `<leader>ac` opens Claude Code in a float at the project root
   (`<leader>ax` for Codex CLI, `<leader>aa` to pick).
2. Ask it to change something. `<C-e>` hides the window; the agent keeps
   running, and the buffers it edited reload.
3. `<leader>ac` again brings back the same conversation.

`<C-q>` switches the terminal to normal mode, to scroll or yank its output.

## Features

- **One session per project.** The terminal opens at the project root detected
  from the current buffer, and each root keeps its own session.
- **Hiding is not quitting.** Toggling the window closed leaves the CLI running
  with its scrollback and context intact. If the CLI has exited, the next
  toggle starts a fresh one.
- **Edited files reload.** Buffers changed by the agent are refreshed when focus
  returns to Neovim.
- **Any CLI.** Providers are a list; add one entry and get a command and a key.
- **Escape belongs to the agent.** `Esc` and `Esc Esc` are not mapped, so they
  still interrupt and rewind in Claude Code and Codex CLI.

## Why not a general toggle terminal?

[toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim),
[snacks.nvim](https://github.com/folke/snacks.nvim)'s terminal or a plain
`:terminal` can all run `claude` in a float, and they are the better choice for
general shell work (splits, numbered shells, sending lines to a REPL).

Terminal agents are a narrower job: they edit your files for minutes at a
time and hold a conversation about one project. aicli.nvim ships the pieces
you would otherwise add on top of a terminal plugin for that:

| To get this | On a general terminal plugin | aicli.nvim |
| --- | --- | --- |
| A separate conversation per project | Give each project its own terminal ID and working directory | Keyed by agent and project root, found from the current buffer |
| See the agent's edits in open buffers | Add a `:checktime` autocmd | Built in (`auto_reload`) |
| Several agents | Define a terminal and a mapping for each | One `providers` entry gives a command, a key and a picker entry |
| Offer only installed agents | Check the executables yourself | The picker skips missing ones; `:checkhealth aicli` shows each path |
| Keep `Esc` for the agent | Avoid the common `<Esc><Esc>` → normal mode mapping | `Esc` is not mapped by default |

It does nothing else: the window is always a float, and there is one kind of
terminal. It has no plugin dependencies. The floating window and the terminal
job are built on Neovim's own `nvim_open_win()` and `jobstart()`.

## Requirements

- Neovim >= 0.10
- At least one agent CLI on your `$PATH`

Authentication is handled by each CLI, not by Neovim.

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

With [vim.pack](https://neovim.io/doc/user/pack.html) (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/g-hoshino/aicli.nvim" })
require("aicli").setup()
```

With [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({ "g-hoshino/aicli.nvim", config = function() require("aicli").setup() end })
```

`setup()` is what creates the per-provider commands and keymaps. Without it you
still get `:Aicli`, `:AicliToggle` and `:AicliStatus`, but nothing is bound to a
key on your behalf.

## Usage

| Action | Command | Default key |
| --- | --- | --- |
| Pick an installed agent | `:Aicli` | `<leader>aa` |
| Toggle Claude Code | `:Claude` | `<leader>ac` |
| Toggle Codex CLI | `:Codex` | `<leader>ax` |
| Toggle a named provider | `:AicliToggle {name}` | - |
| Show the last opened terminal | `:AicliStatus` | - |

Inside the terminal window:

| Action | Key |
| --- | --- |
| Leave terminal mode | `<C-q>` |
| Hide the window, keep the session | `<C-e>` |

Escape is deliberately left unmapped. Claude Code and Codex CLI use `Esc` to
interrupt the agent and `Esc Esc` to rewind the conversation, and a
terminal-mode mapping on `<Esc><Esc>` would delay the first and swallow the
second. Neovim's own `<C-\><C-n>` also leaves terminal mode. To get the old
key back, set `keys = { normal_mode = "<Esc><Esc>" }`.

`:Aicli` only lists providers whose executable was found, so an agent you have
not installed never shows up in the picker.

## Configuration

`setup()` takes the table below. Every field is optional; the values shown are
the defaults. The same list is in `:help aicli-configuration`.

<details>
<summary>All options and their defaults</summary>

```lua
require("aicli").setup({
  -- Agents to manage. Setting this replaces the default list entirely.
  providers = {
    { name = "Claude", cmd = "claude", key = "<leader>ac", command = "Claude" },
    { name = "Codex",  cmd = "codex",  key = "<leader>ax", command = "Codex" },
  },

  -- Normal-mode key for the picker. false disables it.
  select_key = "<leader>aa",

  -- Project root detection, searched upwards from the current buffer.
  root_markers = { ".git", ".hg", "pyproject.toml", "Cargo.toml", "package.json", "go.mod" },

  float = {
    anchor = "right",      -- "left" | "center" | "right". Ignored when col is set.
    width = 0.5,           -- fraction of the editor, absolute cells (> 1), or a function
    height = 0.9,
    margin = 5,            -- gap to the screen edge for "left"/"right"
    row = nil,             -- explicit row; nil centres vertically
    col = nil,             -- explicit column; nil uses anchor
    border = "rounded",    -- anything nvim_open_win() accepts
    title = true,          -- show the provider name on the border
    title_pos = "center",
    winblend = 0,
    zindex = 50,
  },

  -- Buffer-local keys inside the terminal. Set to false to bind nothing.
  keys = {
    normal_mode = "<C-q>",
    hide = "<C-e>",
  },

  start_insert = true,   -- enter terminal mode when the window opens
  close_on_exit = false, -- drop the window and buffer when the CLI exits
  auto_reload = true,    -- :checktime on FocusGained/TermLeave/TermClose
  env = nil,             -- extra environment variables for every provider

  on_open = nil,         -- function(term)
  on_exit = nil,         -- function(term, code)
})
```

</details>

### Provider fields

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | `string` | Display name, used by the picker, the border title and `:AicliStatus`. Required. |
| `cmd` | `string` | Executable looked up in `$PATH`. Required. |
| `args` | `string[]` | Extra arguments passed to the executable. |
| `key` | `string`\|`false` | Normal-mode toggle key. |
| `command` | `string`\|`false` | User command to create. |
| `env` | `table` | Environment variables for this provider only. |

### Recipes

Add your own agent:

```lua
require("aicli").setup({
  providers = {
    { name = "Claude", cmd = "claude", key = "<leader>ac", command = "Claude" },
    { name = "Codex",  cmd = "codex",  key = "<leader>ax", command = "Codex" },
    { name = "Aider",  cmd = "aider",  key = "<leader>ai", command = "Aider" },
  },
})
```

Resume the previous Claude Code session instead of starting a new one:

```lua
providers = {
  { name = "Claude", cmd = "claude", args = { "--continue" }, key = "<leader>ac", command = "Claude" },
}
```

A large centred window with no border:

```lua
float = { anchor = "center", width = 0.85, height = 0.85, border = "none" }
```

Bind nothing and drive it yourself:

```lua
require("aicli").setup({
  providers = { { name = "Claude", cmd = "claude" } },
  select_key = false,
})
vim.keymap.set("n", "<C-g>", function() require("aicli").toggle("Claude") end)
```

## API

```lua
local aicli = require("aicli")

aicli.toggle("Claude")   -- toggle the terminal for the current project
aicli.open("Claude")     -- show it, starting the CLI on first use
aicli.close("Claude")    -- hide it, leaving the CLI running
aicli.shutdown("Claude") -- stop the CLI and discard the buffer
aicli.select()           -- pick among installed agents via vim.ui.select
aicli.status()           -- report the last opened terminal
aicli.list()             -- every live terminal object
```

## Highlight groups

| Group | Links to |
| --- | --- |
| `AicliNormal` | `NormalFloat` |
| `AicliBorder` | `FloatBorder` |
| `AicliTitle` | `FloatTitle` |

## Troubleshooting

Run `:checkhealth aicli`. It reports your Neovim version, whether `setup()` ran,
and the resolved path of every configured CLI.

If files edited by the agent do not refresh, check that `'autoread'` is on —
`auto_reload` issues `:checktime`, which relies on it.

## License

MIT
