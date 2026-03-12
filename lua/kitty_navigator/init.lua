-- lua/kitty_navigator/init.lua
-- Public API for kitty-navigator.nvim
--
-- Minimal async Neovim <-> Kitty window navigator (Neovim >= 0.10)
--
-- IMPORTANT: Do not lazy-load this plugin externally (e.g., lazy.nvim keys/event).
-- The lifecycle autocmds must register at startup for proper Kitty integration.
-- Internal lazy loading is already implemented for config.lua and navigation.lua.
--
-- Behavior:
--   1. Attempt local Neovim split move (:wincmd)
--   2. If at edge, asynchronously instruct Kitty to focus neighbor pane
--
-- Public API:
--   setup(opts)           - Initialize with configuration
--   navigate(direction)   - Navigate in direction
--   left/right/up/down()  - Directional shortcuts
--
-- Performance: Modules are lazy-loaded until setup(), then navigation functions
-- are reassigned to direct references for zero-overhead hot path.

local M = {}

-----------------------------------------------------------------------
-- Lazy Module Loading
-----------------------------------------------------------------------
-- Defer require() of config.lua and navigation.lua until setup().
-- After setup(), navigation functions are reassigned to direct references
-- for zero-overhead hot path (no wrapper function calls).

local config, navigation

-----------------------------------------------------------------------
-- Public Navigation API (Stubs)
-----------------------------------------------------------------------
-- These stubs exist only until setup() is called. After setup(), they are
-- replaced with direct references to navigation module functions.

local function not_initialized()
	error("kitty-navigator: setup() must be called before using navigation functions", 2)
end

---Navigate in the specified direction
---@param direction Direction Direction to navigate ("left"|"right"|"up"|"down"|"top"|"bottom")
M.navigate = not_initialized

---Navigate left
M.left = not_initialized

---Navigate right
M.right = not_initialized

---Navigate up
M.up = not_initialized

---Navigate down
M.down = not_initialized

-----------------------------------------------------------------------
-- Keymaps
-----------------------------------------------------------------------

---Apply default keymaps from configuration
local function apply_keymaps()
	local km = config.keymaps

	local function map(lhs, fn, desc)
		vim.keymap.set("n", lhs, fn, { noremap = true, silent = true, desc = desc })
	end

	map(km.left, M.left, "Navigate left (Vim/Kitty)")
	map(km.down, M.down, "Navigate down (Vim/Kitty)")
	map(km.up, M.up, "Navigate up (Vim/Kitty)")
	map(km.right, M.right, "Navigate right (Vim/Kitty)")
end

-----------------------------------------------------------------------
-- User Commands
-----------------------------------------------------------------------

---Create user commands
local function create_commands()
	local create = vim.api.nvim_create_user_command
	create("KittyNavigateLeft", M.left, { desc = "Navigate to left Vim split or Kitty pane" })
	create("KittyNavigateRight", M.right, { desc = "Navigate to right Vim split or Kitty pane" })
	create("KittyNavigateUp", M.up, { desc = "Navigate to upper Vim split or Kitty pane" })
	create("KittyNavigateDown", M.down, { desc = "Navigate to lower Vim split or Kitty pane" })
end

-----------------------------------------------------------------------
-- Setup
-----------------------------------------------------------------------

---Initialize kitty-navigator with configuration.
---
---@param opts? NavigatorConfig Configuration options
---@see NavigatorConfig for available options
---
---Example:
---  require("kitty_navigator").setup({
---    socket_path = "unix:/tmp/kitty-remote.sock",  -- Required for SSH (must be file-based)
---    editor_var = "in_editor",                      -- Kitty user variable name
---  })
function M.setup(opts)
	-- Load modules on first setup
	if not config then
		config = require("kitty_navigator.config")
		navigation = require("kitty_navigator.navigation")
	end

	-- Initialize configuration (evaluates predicates, builds base_cmd)
	config.setup(opts)

	-- Create user commands
	create_commands()

	-- Create lifecycle autocmds (VimEnter/Leave for editor state)
	navigation.create_autocmds()

	-- Hot path optimization: replace stubs with direct references
	-- No wrapper overhead after setup() - direct function calls
	M.navigate = navigation.navigate
	M.left = navigation.left
	M.right = navigation.right
	M.up = navigation.up
	M.down = navigation.down

	-- Apply keymaps if enabled
	if config.set_keymaps then
		apply_keymaps()
	end
end

-- Allow calling module directly: require("kitty_navigator")(opts)
setmetatable(M, {
	__call = function(_, opts)
		M.setup(opts)
		return M
	end,
})

return M
