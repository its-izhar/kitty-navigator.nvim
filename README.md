# Nvim <-> Kitty Navigator (Even over SSH!)

Minimal async Neovim ↔ Kitty window navigator.

This plugin is a lua rewrite and port of [vim-kitty-navigator](https://github.com/knubie/vim-kitty-navigator) plugin with following enhancements:
 
- Supports navigation over SSH
- Zero noise by default (hooks are opt‑in)  
- Always tries Neovim split movement first; only talks to Kitty when at an edge  
- Pure Lua, uses `vim.system` (Neovim ≥ 0.10) for async, no shell quoting issues  
- Graceful fallback outside Kitty (acts like ordinary window navigation)
- Support for zellij <-> Kitty navigation (coming soon)

## Requirements

- Neovim ≥ 0.11.2 (Use latest stable release)
- Kitty ≥ 0.30.0 (for `focus-window --match neighbor:`)
- Kitty remote control enabled (see Setup → Kitty)

## Features

- Hybrid navigation (local and remote over SSH)
- Default keymaps: `<C-Left> <C-Down> <C-Up> <C-Right>`
- User commands: `:KittyNavigateLeft/Right/Up/Down`
- Hooks: `on_command`, `on_success`, `on_error`
- Optional target socket via `to_socket_str`
- Callable module sugar: `require("kitty_navigator")(opts)`
- Lightweight

## Usage

This plugin provides the following mappings which allow you to move between
Vim panes and kitty splits seamlessly.

These are defaults but easily changeable.

- `<ctrl-left>` → Left
- `<ctrl-down>` → Down
- `<ctrl-up>` → Up
- `<ctrl-right>` → Right

If you want to use alternate key mappings, see the [configuration section below](#configuration).


## Installation (Neovim)

### lazy.nvim
```lua
{
  "its-izhar/kitty-navigator.nvim",
  config = function()
    require("kitty_navigator").setup()
  end,
}
```

## Installation (Kitty)

To configure the kitty side of this customization there are three parts:

#### 1. Add `pass_keys.py` and `get_layout.py` kittens

Move both `pass_keys.py` and `get_layout.py` kittens to the `~/.config/kitty/` directory.

This can be done manually or with a post-update hook in your package manager.

```lua
{
  "its-izhar/kitty-navigator.nvim",
  build = "cp ./kitty/* ~/.config/kitty/",
  config = function()
    require("kitty_navigator").setup()
  end,
}
```

The `pass_keys.py` kitten is used to intercept keybindings defined in your kitty conf and "pass" them through to vim when it is focused. The `get_layout.py` kitten is used to check whether the current kitty tab is in `stack` layout mode so that it can prevent accidentally navigating to a hidden stack window.

#### 2. Add this snippet to kitty.conf

Add the following to your `~/.config/kitty/kitty.conf` file:

```conf
map ctrl+down  kitten pass_keys.py bottom ctrl+down   "nvim,ssh"
map ctrl+up    kitten pass_keys.py top    ctrl+up     "nvim,ssh"
map ctrl+left  kitten pass_keys.py left   ctrl+left   "nvim,ssh"
map ctrl+right kitten pass_keys.py right  ctrl+right  "nvim,ssh"
```

#### 3. Make kitty listen to control messages

Start kitty with the `listen-on` option so that vim can send commands to it.

```
# For linux only:
kitty -o allow_remote_control=yes --single-instance --listen-on unix:@mykitty

# Other unix systems:
kitty -o allow_remote_control=yes --single-instance --listen-on unix:/tmp/mykitty
```

or if you don't want to start kitty with above mentioned command,
simply add below configuration in your `kitty.conf` file.

```
# For linux only:
allow_remote_control yes
listen_on unix:@mykitty

# Other unix systems:
allow_remote_control yes
listen_on unix:/tmp/mykitty
```

> [!TIP]
> After updating kitty.conf, close kitty completely and restart. Kitty does not support enabling `allow_remote_control` on configuration reload.

## Configuration Reference (Neovim)
```lua

require("kitty_navigator").setup({
  set_keymaps = true,            -- install default <C-Arrow> maps
  to_socket_str = nil,           -- e.g. "unix:@mykitty" or "/tmp/mykitty"
  keymaps = {
    left  = "<C-Left>",
    down  = "<C-Down>",
    up    = "<C-Up>",
    right = "<C-Right>",
  },
  enable_when = function()
    return vim.env.TERM == "xterm-kitty"
  end,
  on_command = function(cmdline)
    -- vim.notify("kitty: " .. cmdline)
  end,
  on_success = function(direction)
    -- vim.notify("Focused kitty neighbor: " .. direction)
  end,
  on_error = function(err, code)
    -- vim.notify((code and ("["..code.."] ") or "") .. err, vim.log.levels.WARN)
  end,
})
```
### How Navigation Works
1. Normalize direction (up→top, down→bottom).
2. Attempt local :wincmd (h/j/k/l).
3. If the window changed → stop.
4. Otherwise invoke:
   `kitten @ focus-window --match neighbor:<direction>`
5. On success call on_success(direction).

No timers, no polling—single async process call.

