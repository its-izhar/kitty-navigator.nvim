# Nvim <-> Kitty Navigator (Even over SSH!)

Minimal async Neovim ↔ Kitty window navigator.

This plugin is a lua rewrite and port of [vim-kitty-navigator](https://github.com/knubie/vim-kitty-navigator) plugin with following enhancements:

- Supports navigation over SSH
- Zero noise by default (silent operation)
- Always tries Neovim split movement first; only talks to Kitty when at an edge
- Pure Lua, uses `vim.system` (Neovim >= 0.10) for async, no shell quoting issues
- Graceful fallback outside Kitty (acts like ordinary window navigation)
- Fast: runtime values cached at setup, no per-navigation overhead

## Requirements

- Neovim >= 0.10 (uses `vim.system` for async)
- Kitty >= 0.30.0 (for `focus-window --match neighbor:`)
- Kitty remote control enabled (see Setup → Kitty)

## Features

- Hybrid navigation (local and remote over SSH)
- Default keymaps: `<C-Left> <C-Down> <C-Up> <C-Right>`
- User commands: `:KittyNavigateLeft/Right/Up/Down`
- Flexible socket path: static string or dynamic function
- Configurable editor variable name for `pass_keys.py`
- Callable module sugar: `require("kitty_navigator")(opts)`
- Lightweight and fast

## Usage

This plugin provides the following mappings which allow you to move between
Vim panes and kitty splits seamlessly.

These are defaults but easily changeable.

- `<ctrl-left>` → Left
- `<ctrl-down>` → Down
- `<ctrl-up>` → Up
- `<ctrl-right>` → Right

If you want to use alternate key mappings, see the [configuration section below](#configuration-reference-neovim).


## Installation (Neovim)

> [!IMPORTANT]
> **Do not lazy-load this plugin.** Set `lazy = false` in your plugin manager.
>
> The plugin registers lifecycle autocmds (VimEnter/VimLeave) that must fire at
> startup to properly set Kitty's `in_editor` variable. Lazy loading breaks this
> timing and causes navigation to fail.
>
> Internal lazy loading is already implemented—config and navigation modules are
> only loaded on first use, so startup impact is minimal (~0.1-0.2ms).

### lazy.nvim
```lua
{
  "its-izhar/kitty-navigator.nvim",
  build = "cp ./kitty/* ~/.config/kitty/",
  lazy = false,  -- Required: autocmds must register at startup
  opts = {},
}
```

## Installation (Kitty)

To configure the kitty side of this customization there are three parts:

#### 1. Add `pass_keys.py` kitten

Move `pass_keys.py` kitten to the `~/.config/kitty/` directory.

This can be done manually or with a post-update hook in your package manager.

```lua
{
  "its-izhar/kitty-navigator.nvim",
  build = "cp ./kitty/* ~/.config/kitty/",
  lazy = false,  -- Required: autocmds must register at startup
  opts = {},
}
```

The `pass_keys.py` kitten intercepts keybindings and passes them through to Neovim when the `in_editor` user variable is set. Otherwise, it focuses the neighboring Kitty window directly.

#### 2. Add this snippet to kitty.conf

Add the following to your `~/.config/kitty/kitty.conf` file:

```conf
map ctrl+down  kitten pass_keys.py bottom ctrl+down   "in_editor"
map ctrl+up    kitten pass_keys.py top    ctrl+up     "in_editor"
map ctrl+left  kitten pass_keys.py left   ctrl+left   "in_editor"
map ctrl+right kitten pass_keys.py right  ctrl+right  "in_editor"
```

> [!NOTE]
> If you change `editor_var` in the Neovim config, update the kitty.conf mappings to match.

#### 3. Make kitty listen to control messages

Start kitty with the `listen-on` option so that vim can send commands to it.

```bash
# For local use only (Linux abstract socket):
kitty -o allow_remote_control=yes --single-instance --listen-on unix:@mykitty

# For SSH support (file-based socket - works on all Unix systems):
kitty -o allow_remote_control=yes --single-instance --listen-on unix:/tmp/kitty-$USER.sock
```

or add to your `kitty.conf` file:

```conf
# For local use only (Linux abstract socket):
allow_remote_control yes
listen_on unix:@mykitty

# For SSH support (file-based socket):
allow_remote_control yes
listen_on unix:/tmp/kitty-$USER.sock
```

> [!TIP]
> After updating kitty.conf, close kitty completely and restart. Kitty does not support enabling `allow_remote_control` on configuration reload.

## SSH Setup

To use kitty-navigator over SSH, you need to forward the Kitty socket to the remote machine.

### Understanding Socket Types

Kitty supports two types of Unix sockets:

| Type | Format | OS Support | SSH Forwardable |
|------|--------|------------|-----------------|
| **Abstract** | `unix:@name` | Linux only | ❌ No |
| **File-based** | `unix:/path/to/sock` | All Unix | ✅ Yes |

**Abstract sockets** (prefixed with `@`) exist only in the Linux kernel's abstract namespace - they have no filesystem path. SSH cannot forward them because there's nothing on the filesystem to connect to.

**File-based sockets** create an actual file on disk that SSH can forward using remote port forwarding (`-R`).

### Step 1: Configure Kitty with a File-Based Socket

On your **local machine**, configure Kitty to use a file-based socket:

```conf
# ~/.config/kitty/kitty.conf
allow_remote_control yes
listen_on unix:/tmp/kitty-$USER.sock
```

Restart Kitty after making this change.

### Step 2: Forward the Socket via SSH

When connecting to the remote machine, use SSH remote forwarding (`-R`) to make the local socket available on the remote:

```bash
ssh -R /tmp/kitty-remote.sock:/tmp/kitty-$USER.sock user@remote-host
```

This creates `/tmp/kitty-remote.sock` on the remote machine, which tunnels back to your local Kitty socket.

> [!TIP]
> Add this to your `~/.ssh/config` for convenience:
> ```
> Host myserver
>     HostName remote-host.example.com
>     User myuser
>     RemoteForward /tmp/kitty-remote.sock /tmp/kitty-%r.sock
> ```

### Step 3: Configure the Plugin on the Remote Machine

On the **remote machine**, configure the plugin to use the forwarded socket:

```lua
{
  "its-izhar/kitty-navigator.nvim",
  lazy = false,
  opts = {
    socket_path = "unix:/tmp/kitty-remote.sock",
  },
}
```

Or use a function if you have multiple remote hosts with different socket paths:

```lua
{
  "its-izhar/kitty-navigator.nvim",
  lazy = false,
  opts = {
    socket_path = function()
      -- Use environment variable you set in your remote shell config
      -- e.g., export KITTY_REMOTE_SOCK="/tmp/kitty-remote.sock"
      local sock = vim.env.KITTY_REMOTE_SOCK
      if sock and sock ~= "" then
        return "unix:" .. sock
      end
      return "unix:/tmp/kitty-remote.sock"
    end,
  },
}
```

### Socket Path Format

The `socket_path` config option must follow this format:

```
unix:<path>
```

Where `<path>` is either:
- An abstract socket name (Linux local only): `unix:@mykitty`
- A file path (required for SSH): `unix:/tmp/kitty-remote.sock`

**Examples:**

```lua
-- Abstract socket (local Linux only, NOT for SSH)
socket_path = "unix:@mykitty"

-- File-based socket (works everywhere, required for SSH)
socket_path = "unix:/tmp/kitty-remote.sock"

-- Using environment variable (set in your remote shell config)
socket_path = function()
  return "unix:" .. vim.env.KITTY_REMOTE_SOCK
end
```

### Verifying the Setup

Test that the forwarded socket works from the remote machine:

```bash
# On the remote machine, after SSH with socket forwarding:
kitten @ --to=unix:/tmp/kitty-remote.sock ls
```

If this returns your Kitty windows/tabs, the forwarding is working correctly.

## Configuration Reference (Neovim)

All options below go in `opts = {}` when using lazy.nvim.

```lua
require("kitty_navigator").setup({
  -- Install default <C-Arrow> keymaps
  set_keymaps = true,

  -- Socket path for Kitty remote control.
  -- Required for SSH sessions. Must be file-based socket for SSH (not abstract).
  -- Can be a string or a function returning a string.
  -- Format: "unix:<path>" where <path> is a filesystem path
  socket_path = nil,

  -- Example: static file-based socket (for SSH)
  -- socket_path = "unix:/tmp/kitty-remote.sock",

  -- Example: dynamic socket path from environment variable
  -- (set KITTY_REMOTE_SOCK in your remote shell config)
  -- socket_path = function()
  --   return "unix:" .. vim.env.KITTY_REMOTE_SOCK
  -- end,

  -- Kitty user variable name for editor state signaling.
  -- The pass_keys.py kitten checks this variable to decide routing.
  -- Must match the variable name in your kitty.conf mappings.
  editor_var = "in_editor",

  -- Keymaps configuration
  keymaps = {
    left  = "<C-Left>",
    down  = "<C-Down>",
    up    = "<C-Up>",
    right = "<C-Right>",
  },

  -- Enable Kitty integration when this returns true.
  -- Default checks TERM environment variable set by Kitty.
  enable_when = function()
    return vim.env.TERM == "xterm-kitty"
  end,

  -- Enable remote mode (--to= flag) when this returns true.
  -- When true, socket_path is required and must point to a valid socket.
  enable_remote_when = function()
    return vim.env.SSH_CLIENT ~= nil and vim.env.SSH_TTY ~= nil
  end,
})
```

### How Navigation Works

1. Direction lookup (`up`/`down` mapped to Kitty's `top`/`bottom`)
2. Attempt local `:wincmd` (`h`/`j`/`k`/`l`)
3. If the window changed → stop
4. Otherwise invoke: `kitten @ [--to=<socket>] focus-window --match neighbor:<direction>`

No timers, no polling—single async process call. All configuration is cached at setup time for fast navigation.

## Architecture

```
lua/kitty_navigator/
├── init.lua        # Public API, setup(), keymaps
├── config.lua      # Config schema, validation, runtime cache
└── navigation.lua  # Core navigation logic, lifecycle autocmds
```

### Performance

Runtime values are evaluated once at `setup()` and cached:
- `enable_when()` result → `config.enabled` (boolean)
- `enable_remote_when()` result → `config.remote` (boolean)
- `socket_path` resolution → `config.socket` (string)
- Base command → `config.base_cmd` (pre-built array)

Navigation hot path uses direct table lookups, no function calls.

## License

MIT
