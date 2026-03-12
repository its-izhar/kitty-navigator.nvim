-- lua/kitty_navigator/init.lua
-- Public API for kitty-navigator.nvim
--
-- Minimal async Neovim <-> Kitty window navigator (Neovim >= 0.10)
--
-- Behavior:
--   1. Attempt local Neovim split move (:wincmd)
--   2. If at edge, asynchronously instruct Kitty to focus neighbor pane
--
-- Public API:
--   setup(opts)           - Initialize with configuration
--   navigate(direction)   - Navigate in direction
--   left/right/up/down()  - Directional shortcuts

local config = require("kitty_navigator.config")
local navigation = require("kitty_navigator.navigation")

local M = {}

-----------------------------------------------------------------------
-- Public Navigation API
-----------------------------------------------------------------------

---Navigate in the specified direction
---@param direction Direction Direction to navigate ("left"|"right"|"up"|"down"|"top"|"bottom")
M.navigate = navigation.navigate

---Navigate left
M.left = navigation.left

---Navigate right
M.right = navigation.right

---Navigate up
M.up = navigation.up

---Navigate down
M.down = navigation.down

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
	-- Initialize configuration (evaluates predicates, builds base_cmd)
	config.setup(opts)

	-- Create user commands
	create_commands()

	-- Create lifecycle autocmds (VimEnter/Leave for editor state)
	navigation.create_autocmds()

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
