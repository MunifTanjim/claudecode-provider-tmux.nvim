# claudecode.nvim TMUX Provider

A [tmux](https://github.com/tmux/tmux) terminal provider for [claudecode.nvim](https://github.com/coder/claudecode.nvim).

Runs the Claude Code CLI in a real tmux pane next to Neovim, instead of a
Neovim `:terminal` buffer or floating window.

## Requirements

- [claudecode.nvim](https://github.com/coder/claudecode.nvim)
- Neovim running inside a **tmux** session
- [`tmux-ctrl`](https://github.com/MunifTanjim/tmux-ctrl):

  ```sh
  gh api -H "Accept: application/vnd.github.raw" \
    repos/MunifTanjim/tmux-ctrl/contents/scripts/install.sh | bash
  ```

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "coder/claudecode.nvim",
  dependencies = {
    "MunifTanjim/claudecode-provider-tmux.nvim",
  },
  opts = function()
    return {
      terminal = {
        provider = require("claudecode.terminal.tmux"),
        provider_opts = {
          split_direction = "right",
          split_size = 80,
        },
      },
    }
  end,
}
```

## Configuration

`provider_opts`:

| Option            | Default   | Description                                                                                              |
| ----------------- | --------- | -------------------------------------------------------------------------------------------------------- |
| `split_direction` | `"right"` | Pane position: `left`, `right`, `top`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`. |
| `split_size`      | `80`      | Pane size: lines, columns, percentage, or a fraction `0 < n < 1`.                                        |

Both fall back to claudecode.nvim's `split_side` / `split_width_percentage` when
unset.

## License

Licensed under the MIT License. Check the [LICENSE](./LICENSE) file for details.
