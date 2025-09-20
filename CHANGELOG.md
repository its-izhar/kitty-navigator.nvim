# Changelog

All notable changes to this project are documented here.

## [Unreleased]
### Added
- (placeholder) Future changes will be tracked here.

---

## [0.1.0] - 2025-09-20
Initial stable release of the minimal async Neovim ↔ Kitty navigator.

### Added
- Hybrid navigation: try Neovim window move first; if still at edge, call Kitty: `kitten @ focus-window --match neighbor:<dir>`.
- Direction helpers: `left`, `right`, `up` (`top`), `down` (`bottom`) plus `navigate(direction)`.
- Edge detection without timers: compares starting and ending window IDs.
- Default keymaps (normal mode): `<C-Left>`, `<C-Down>`, `<C-Up>`, `<C-Right>` with opt-out via `set_keymaps = false`.
- User commands: `:KittyNavigateLeft`, `:KittyNavigateRight`, `:KittyNavigateUp`, `:KittyNavigateDown`.
- Public Lua API: `setup(opts)`, `kitty_command(args, cb?)`, directional functions.
- Safe async spawning via `vim.system` (argv list, no shell quoting).
- Config options:
  - `set_keymaps`
  - `keymaps = { left, down, up, right }`
  - `to_socket_str` (adds `--to=<value>`)
  - `enable_when()` (default: `TERM == "xterm-kitty"`)
  - Hooks: `on_command`, `on_success`, `on_error`
- Graceful fallback: if `enable_when()` is false, only local Neovim movement occurs.
- Error propagation to `on_error` (stderr/stdout merged message).
- Callable module sugar: `require("kitty_navigator")(opts)` == `setup(opts)`.

### Included Kitty Kittens
- Original credit goes to https://github.com/knubie/vim-kitty-navigator
- `kitty/pass_keys.py`: Sends key sequence(s) to foreground processes matching a CSV list (`vim,nvim,ssh,zellij` by default); otherwise focuses neighbor window in given direction.
- `kitty/get_layout.py`: Returns current Kitty tab layout name.

### Implementation Notes
- Deep-copies defaults each `setup` call; no mutation leakage.
- Intentional omissions: no password relays, no stack logic, no timers, no globals.
- Command builder constructs argv array defensively (no shell interpolation).

### Rationale
Provide a lean, silent-by-default bridge between Neovim splits and Kitty window navigation with minimal moving parts.
