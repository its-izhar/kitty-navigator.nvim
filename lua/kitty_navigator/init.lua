-- lua/kitty_navigator/init.lua
-- Minimal async kitty navigator for Neovim (>= 0.10), silent unless hooks are uncommented.
--
-- Behavior:
--   1. Attempt local Neovim split move (:wincmd).
--   2. If still at the same window (edge), asynchronously instruct kitty to focus the neighbor.
--
-- Directions: left, right, top, bottom (synonyms: up -> top, down -> bottom).
--
-- Configuration (pass to setup):
--   set_keymaps (bool)          : Apply default keymaps on setup (default: true)
--   to_socket_str (string|nil)  : Value passed as --to=<to_socket_str> to kitty
--   keymaps (table)             : { left, down, up, right } default: <C-Arrow> keys
--   enable_when ():boolean      : Predicate gating kitty usage (default: TERM == xterm-kitty)
--   on_command(cmdline)         : Hook before spawning (empty; commented body shows debugging)
--   on_success(direction)       : Hook after successful kitty focus (empty; commented example)
--   on_error(err, code)         : Hook on non-zero exit / navigation error (commented example)
--
-- Public API:
--   setup(opts)
--   navigate(direction)
--   left/right/up/down/top/bottom()
--   kitty_command(args_str, cb?)
--
-- No legacy globals, no stack logic, no password option.

local M = {}

-----------------------------------------------------------------------
-- Defaults
-----------------------------------------------------------------------
local defaults = {
	set_keymaps = true,
	to_socket_str = nil,
	keymaps = {
		left = "<C-Left>",
		down = "<C-Down>", -- bottom
		up = "<C-Up>", -- top
		right = "<C-Right>",
	},
	enable_when = function()
		return vim.env.TERM == "xterm-kitty"
	end,
	on_command = function(_cmdline)
		-- Debug example (uncomment to use):
		-- vim.notify("kitty command: " .. _cmdline, vim.log.levels.INFO, { title = "kitty-navigator" })
	end,
	on_success = function(_direction)
		-- Debug example (uncomment to use):
		-- vim.notify("kitty focus success: " .. _direction, vim.log.levels.INFO, { title = "kitty-navigator" })
	end,
	on_error = function(err, code)
		-- Debug example (uncomment to use):
		-- vim.notify(
		--   ("kitty-navigator error%s: %s"):format(code and (" (exit " .. code .. ")") or "", err),
		--   vim.log.levels.WARN,
		--   { title = "kitty-navigator" }
		-- )
	end,
}

local config = vim.deepcopy(defaults)

-- kitty direction -> :wincmd motion
local kitty_to_wincmd = {
	left = "h",
	right = "l",
	top = "k",
	bottom = "j",
	up = "k",
	down = "j",
}

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------
local function build_cmd(args_str)
	-- Build argv vector for `vim.system`; no shell interpretation.
	local cmd = { "kitten", "@" }
	if config.to_socket_str and config.to_socket_str ~= "" then
		cmd[#cmd + 1] = "--to=" .. config.to_socket_str
	end
	for _, t in ipairs(vim.split(args_str, "%s+")) do
		if t ~= "" then
			cmd[#cmd + 1] = t
		end
	end
	return cmd
end

-----------------------------------------------------------------------
-- Async kitty invocation
-----------------------------------------------------------------------
-- M.kitty_command:
--   args_str: string containing subcommand + arguments (e.g., 'focus-window --match neighbor:left')
--   cb(err, code, stdout, stderr):
--       err   = nil on success; otherwise error text (stderr or stdout)
--       code  = process exit code
--       stdout/stderr aggregated textual output (because text=true)
-- Steps:
--   1. Construct argv safely (no shell quoting worries).
--   2. Invoke on_command hook (user instrumentation/logging).
--   3. Spawn asynchronously with vim.system.
--   4. On non-zero exit -> call on_error and pass err to cb.
--   5. On success -> cb(nil, ...).
function M.kitty_command(args_str, cb)
	cb = cb or function() end
	local cmdtbl = build_cmd(args_str)
	config.on_command(table.concat(cmdtbl, " "))
	vim.system(cmdtbl, { text = true }, function(res)
		if res.code ~= 0 then
			local msg = (res.stderr ~= "" and res.stderr) or res.stdout
			config.on_error(msg, res.code)
			cb(msg, res.code, res.stdout, res.stderr)
			return
		end
		cb(nil, res.code, res.stdout, res.stderr)
	end)
end

-----------------------------------------------------------------------
-- Navigation
-----------------------------------------------------------------------
-- M.navigate(direction):
--   1. Normalize synonyms (up->top, down->bottom).
--   2. Validate direction & compute wincmd motion.
--   3. If enable_when() false -> only do local Vim movement.
--   4. Attempt :wincmd; error -> still proceed with edge detection.
--   5. Edge detection: unchanged window handle means boundary.
--   6. If boundary -> build neighbor focus command and run asynchronously.
--   7. On success -> invoke on_success(direction).
function M.navigate(direction)
	if not direction then
		return
	end
	if direction == "down" then
		direction = "bottom"
	end
	if direction == "up" then
		direction = "top"
	end

	local wcmd = kitty_to_wincmd[direction]
	if not wcmd then
		config.on_error("Invalid direction: " .. tostring(direction))
		return
	end

	if not config.enable_when() then
		vim.cmd("wincmd " .. wcmd)
		return
	end

	local start_win = vim.api.nvim_get_current_win()
	local ok_vim, err = pcall(vim.cmd, "wincmd " .. wcmd)
	if not ok_vim then
		config.on_error("Window navigation error: " .. err)
	end

	if start_win ~= vim.api.nvim_get_current_win() then
		return -- local movement succeeded
	end

	-- Inline focus args (neighbor match)
	local focus_args = ("focus-window --match neighbor:%s"):format(direction)
	M.kitty_command(focus_args, function(err2)
		if not err2 then
			pcall(config.on_success, direction)
		end
	end)
end

-----------------------------------------------------------------------
-- Directional shortcuts
-----------------------------------------------------------------------
function M.left()
	M.navigate("left")
end
function M.right()
	M.navigate("right")
end
function M.up()
	M.navigate("top")
end
function M.down()
	M.navigate("bottom")
end
function M.top()
	M.navigate("top")
end
function M.bottom()
	M.navigate("bottom")
end

-----------------------------------------------------------------------
-- Keymaps & Commands
-----------------------------------------------------------------------
function M.apply_keymaps()
	local km = config.keymaps
	local map = function(lhs, fn, desc)
		vim.keymap.set("n", lhs, fn, { noremap = true, silent = true, desc = desc })
	end
	map(km.left, M.left, "KittyNavigateLeft")
	map(km.down, M.down, "KittyNavigateDown")
	map(km.up, M.up, "KittyNavigateUp")
	map(km.right, M.right, "KittyNavigateRight")
end

local function create_commands()
	local create = vim.api.nvim_create_user_command
	create("KittyNavigateLeft", M.left, {})
	create("KittyNavigateRight", M.right, {})
	create("KittyNavigateUp", M.up, {})
	create("KittyNavigateDown", M.down, {})
end

-----------------------------------------------------------------------
-- Setup
-----------------------------------------------------------------------
function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	create_commands()
	if config.set_keymaps then
		M.apply_keymaps()
	end
end

setmetatable(M, {
	__call = function(_, opts)
		M.setup(opts)
		return M
	end,
})

return M

