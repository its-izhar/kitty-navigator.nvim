-- lua/kitty_navigator/config.lua
-- Configuration schema, validation, and runtime cache for kitty-navigator.nvim
--
-- Design: All runtime values are evaluated ONCE at setup() and exposed directly
-- on the module table for fast access. Navigation hot path uses direct table
-- lookups (e.g., config.enabled) instead of function calls.
--
-- Socket Path Format:
--   "unix:<path>" where <path> is either:
--   - Abstract socket (Linux only, local): "unix:@mykitty"
--   - File-based socket (all Unix, SSH): "unix:/tmp/kitty.sock"
--
--   IMPORTANT: Abstract sockets (@name) cannot be forwarded over SSH.
--   For SSH support, you MUST use a file-based socket path.
--
-- Usage:
--   local config = require("kitty_navigator.config")
--   config.setup({ socket_path = "unix:/tmp/kitty-remote.sock" })
--   if config.enabled then ... end  -- Direct access, no function call

---@alias Direction "left"|"right"|"top"|"bottom"|"up"|"down"

---@class NavigatorKeymaps
---@field left string   Keymap for left navigation (default: "<C-Left>")
---@field down string   Keymap for down navigation (default: "<C-Down>")
---@field up string     Keymap for up navigation (default: "<C-Up>")
---@field right string  Keymap for right navigation (default: "<C-Right>")

---@class NavigatorConfig
---@field set_keymaps boolean                      Install default keymaps (default: true)
---@field socket_path? string|fun():string         Socket path for Kitty remote control
---@field editor_var string                        Kitty user variable name (default: "in_editor")
---@field keymaps NavigatorKeymaps                 Keymap configuration
---@field enable_when fun():boolean                Predicate for Kitty integration
---@field enable_remote_when fun():boolean         Predicate for --to= flag (SSH)

local M = {}

-----------------------------------------------------------------------
-- Runtime Cache
-----------------------------------------------------------------------
-- These values are set ONCE at setup() and accessed directly by navigation.lua.
-- This avoids function call overhead in the hot path (navigate()).

---@type boolean Cached result of enable_when() - true if running inside Kitty
M.enabled = false

---@type boolean Cached result of enable_remote_when() - true if SSH session
M.remote = false

---@type string|nil Resolved socket path (nil = no remote socket configured)
M.socket = nil

---@type string Kitty user variable name for editor state signaling
M.editor_var = "in_editor"

---@type string[] Pre-built base command: {"kitten", "@"} or {"kitten", "@", "--to=<socket>"}
-- Navigation appends action-specific args to a shallow copy of this array.
M.base_cmd = { "kitten", "@" }

---@type boolean Whether to install default keymaps
M.set_keymaps = true

---@type NavigatorKeymaps Cached keymap configuration
M.keymaps = {
	left = "<C-Left>",
	down = "<C-Down>",
	up = "<C-Up>",
	right = "<C-Right>",
}

-----------------------------------------------------------------------
-- Schema & Defaults
-----------------------------------------------------------------------

---@type NavigatorConfig
local config = {}

---@type NavigatorConfig
local defaults = {
	set_keymaps = true,

	-- Socket path for Kitty remote control.
	-- Required for SSH sessions (when enable_remote_when() returns true).
	-- Can be a string or a function returning a string.
	--
	-- Format: "unix:<path>"
	--   - Abstract (Linux local only): "unix:@mykitty"
	--   - File-based (SSH support):    "unix:/tmp/kitty-remote.sock"
	--
	-- IMPORTANT: For SSH, you MUST use a file-based socket path.
	-- Abstract sockets (@name) exist only in the kernel's abstract namespace
	-- and cannot be forwarded over SSH. See README.md for SSH setup guide.
	--
	-- Examples:
	--   socket_path = "unix:/tmp/kitty-remote.sock"
	--   socket_path = function() return "unix:" .. vim.env.KITTY_REMOTE_SOCK end
	socket_path = nil,

	-- Kitty user variable name for editor state signaling.
	-- The pass_keys.py kitten checks this variable to decide whether to
	-- forward keypresses to Neovim or handle them directly in Kitty.
	-- Change this if you use a different variable name in your kitty.conf.
	editor_var = "in_editor",

	keymaps = {
		left = "<C-Left>",
		down = "<C-Down>",
		up = "<C-Up>",
		right = "<C-Right>",
	},

	-- Predicate: Enable Kitty integration when this returns true.
	-- Default checks TERM environment variable set by Kitty.
	enable_when = function()
		return vim.env.TERM == "xterm-kitty"
	end,

	-- Predicate: Use --to=<socket> flag when this returns true.
	-- Required for SSH sessions where kitten @ needs explicit socket path.
	-- Default checks standard SSH environment variables.
	enable_remote_when = function()
		return vim.env.SSH_CLIENT ~= nil and vim.env.SSH_TTY ~= nil
	end,
}

-----------------------------------------------------------------------
-- Validation
-----------------------------------------------------------------------

---Validate user configuration (fail-fast on first error)
---@param opts table
---@return string|nil Error message or nil if valid
local function validate(opts)
	-- socket_path: must be string or function if provided
	if opts.socket_path ~= nil then
		local t = type(opts.socket_path)
		if t ~= "string" and t ~= "function" then
			return ("socket_path must be string or function, got %s"):format(t)
		end
	end

	-- editor_var: must be non-empty string if provided
	if opts.editor_var ~= nil then
		if type(opts.editor_var) ~= "string" then
			return ("editor_var must be string, got %s"):format(type(opts.editor_var))
		end
		if opts.editor_var == "" then
			return "editor_var cannot be empty"
		end
	end

	-- keymaps: must be table with string values
	if opts.keymaps ~= nil then
		if type(opts.keymaps) ~= "table" then
			return "keymaps must be a table"
		end
		for dir, key in pairs(opts.keymaps) do
			if type(key) ~= "string" then
				return ("keymaps.%s must be string, got %s"):format(dir, type(key))
			end
		end
	end

	-- enable_when / enable_remote_when: must be functions if provided
	if opts.enable_when ~= nil and type(opts.enable_when) ~= "function" then
		return "enable_when must be a function"
	end
	if opts.enable_remote_when ~= nil and type(opts.enable_remote_when) ~= "function" then
		return "enable_remote_when must be a function"
	end

	return nil
end

-----------------------------------------------------------------------
-- Setup
-----------------------------------------------------------------------

---Initialize configuration and populate runtime cache.
---All predicates are evaluated ONCE here. If config changes are needed,
---call setup() again to re-evaluate.
---@param opts? NavigatorConfig User configuration options
---@return NavigatorConfig Merged configuration
function M.setup(opts)
	opts = opts or {}

	-- Validate user options
	local err = validate(opts)
	if err then
		vim.notify("kitty-navigator: " .. err .. ". Using defaults.", vim.log.levels.ERROR)
		config = vim.deepcopy(defaults)
	else
		config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
	end

	---------------------------------------------------------------------------
	-- Evaluate predicates ONCE and cache results
	---------------------------------------------------------------------------

	-- Check if running inside Kitty terminal
	M.enabled = config.enable_when and config.enable_when() or false

	-- Check if this is an SSH session (needs --to= flag)
	M.remote = config.enable_remote_when and config.enable_remote_when() or false

	---------------------------------------------------------------------------
	-- Resolve socket path ONCE
	---------------------------------------------------------------------------
	-- Socket path is only needed for remote (SSH) sessions.
	-- If remote=true but socket=nil, Kitty commands will fail silently
	-- (kitten @ without --to= only works on local sessions).

	local sp = config.socket_path
	if sp ~= nil then
		if type(sp) == "function" then
			-- Call function to get dynamic socket path
			local result = sp()
			M.socket = (type(result) == "string" and result ~= "") and result or nil
		else
			M.socket = (sp ~= "") and sp or nil
		end
	else
		M.socket = nil
	end

	---------------------------------------------------------------------------
	-- Cache simple config values
	---------------------------------------------------------------------------

	M.editor_var = config.editor_var
	M.set_keymaps = config.set_keymaps
	M.keymaps = config.keymaps

	---------------------------------------------------------------------------
	-- Build base command ONCE
	---------------------------------------------------------------------------
	-- This array is shallow-copied by navigation.lua before appending
	-- action-specific arguments. Avoids rebuilding on every command.

	if M.remote and M.socket then
		-- SSH session with socket configured: include --to= flag
		M.base_cmd = { "kitten", "@", "--to=" .. M.socket }
	else
		-- Local session or no socket: simple command
		-- Note: If remote=true but socket=nil, commands will fail.
		-- This is intentional - user must configure socket_path for SSH.
		M.base_cmd = { "kitten", "@" }
	end

	return config
end

return M
