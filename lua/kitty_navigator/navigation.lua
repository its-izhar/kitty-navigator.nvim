-- lua/kitty_navigator/navigation.lua
-- Core navigation logic, Kitty command execution, and lifecycle management
--
-- Design: Optimized for fast navigation with minimal overhead.
-- - All config values accessed via direct table lookup (no function calls)
-- - Base command array is pre-built at setup, shallow-copied per invocation
-- - Single callback handles all vim.system() results (errors printed to :messages)
-- - Direction mapping uses compile-time constant tables

local config = require("kitty_navigator.config")

local M = {}

-----------------------------------------------------------------------
-- Direction Mapping (Compile-time Constants)
-----------------------------------------------------------------------

-- Maps direction to Vim wincmd motion character.
-- Includes synonyms (up/down) to avoid normalization function call.
---@type table<string, string>
local WINCMD = {
	left = "h",
	right = "l",
	top = "k",
	bottom = "j",
	-- Synonyms: avoid normalize_direction() function call overhead
	up = "k",
	down = "j",
}

-- Maps direction synonyms to Kitty-compatible direction names.
-- Kitty uses "top"/"bottom", Vim users often say "up"/"down".
---@type table<string, string>
local TO_KITTY = {
	left = "left",
	right = "right",
	top = "top",
	bottom = "bottom",
	-- Normalize synonyms for Kitty
	up = "top",
	down = "bottom",
}

-----------------------------------------------------------------------
-- Result Handler
-----------------------------------------------------------------------

-- Single callback for all vim.system() invocations.
-- Prints errors to :messages (vim.notify with WARN level).
-- Non-zero exit codes indicate Kitty command failure (e.g., no neighbor pane).
---@param res {code: number, stdout: string, stderr: string}
local function on_result(res)
	if res.code ~= 0 then
		-- Prefer stderr, fall back to stdout
		local msg = (res.stderr ~= "" and res.stderr) or res.stdout
		if msg and msg ~= "" then
			-- Schedule to ensure we're on main loop (vim.system callback context)
			vim.schedule(function()
				vim.notify("kitty: " .. vim.trim(msg), vim.log.levels.WARN)
			end)
		end
		-- Note: Exit code 1 with empty output often means "no neighbor in that direction"
		-- This is normal at terminal edges and not worth logging.
	end
end

-----------------------------------------------------------------------
-- Navigation (Hot Path - Optimized)
-----------------------------------------------------------------------

---Navigate in the specified direction.
---First attempts local Neovim split movement, then falls back to Kitty pane.
---
---Hot path optimizations:
---  - Direct table lookups instead of function calls
---  - No string operations (direction mapping via tables)
---  - Pre-built base command (shallow copy + append)
---  - Single vim.api call to check window change
---
---@param direction Direction Direction to navigate ("left"|"right"|"up"|"down"|"top"|"bottom")
function M.navigate(direction)
	-- Fast lookup: direction -> wincmd character
	-- Returns nil for invalid directions (no error, just early return)
	local wcmd = WINCMD[direction]
	if not wcmd then
		return
	end

	-- Check if Kitty integration is enabled (cached boolean, no function call)
	-- If disabled, only do local Vim window movement
	if not config.enabled then
		vim.cmd.wincmd(wcmd)
		return
	end

	-- Attempt local Neovim window movement
	local start_win = vim.api.nvim_get_current_win()
	vim.cmd.wincmd(wcmd)

	-- If window changed, local movement succeeded - we're done
	-- This is the common case (navigating between Vim splits)
	if start_win ~= vim.api.nvim_get_current_win() then
		return
	end

	-- At edge of Vim splits - delegate to Kitty to focus neighbor pane
	-- Shallow copy the pre-built base command and append action args
	local base = config.base_cmd
	local n = #base
	local cmd = { unpack(base) }

	-- Append focus-window command with neighbor match
	-- TO_KITTY normalizes "up"/"down" to "top"/"bottom" for Kitty
	cmd[n + 1] = "focus-window"
	cmd[n + 2] = "--match"
	cmd[n + 3] = "neighbor:" .. TO_KITTY[direction]

	-- Execute asynchronously - never blocks Neovim's event loop
	vim.system(cmd, { text = true }, on_result)
end

-----------------------------------------------------------------------
-- Direction Shortcuts
-----------------------------------------------------------------------
-- Convenience functions for direct keymap binding.
-- Using explicit functions instead of table to ensure proper inlining.

function M.left()
	M.navigate("left")
end

function M.right()
	M.navigate("right")
end

function M.up()
	M.navigate("up")
end

function M.down()
	M.navigate("down")
end

-----------------------------------------------------------------------
-- Lifecycle Management
-----------------------------------------------------------------------

---Set editor state in Kitty via user variable.
---
---When active=true:  Sets <editor_var>=1 (e.g., "in_editor=1")
---When active=false: Unsets variable by sending just the name (e.g., "in_editor")
---
---The pass_keys.py kitten checks this variable to decide routing:
---  - If set: Forward keypresses to Neovim (we handle navigation)
---  - If unset: Kitty handles navigation directly (neighboring_window)
---
---@param active boolean Whether editor is active (true=entering, false=leaving)
---@param sync boolean Use synchronous execution (required for VimLeave)
local function set_editor_state(active, sync)
	-- Skip if Kitty integration is disabled
	if not config.enabled then
		return
	end

	-- Build command: shallow copy base + append set-user-vars
	local base = config.base_cmd
	local n = #base
	local cmd = { unpack(base) }

	cmd[n + 1] = "set-user-vars"
	-- active: "in_editor=1" (set to value)
	-- inactive: "in_editor" (unset - sends empty value)
	cmd[n + 2] = active and (config.editor_var .. "=1") or config.editor_var

	if sync then
		-- VimLeave: Must complete before Neovim exits
		-- vim.fn.system() blocks until command finishes
		vim.fn.system(cmd)
	else
		-- VimEnter/VimResume/VimSuspend: Async is fine
		vim.system(cmd, { text = true }, on_result)
	end
end

---Create lifecycle autocmds for editor state signaling.
---
---Events handled:
---  VimEnter   - Editor started, set in_editor=1 (async, 50ms delay)
---  VimResume  - Resumed from suspend (Ctrl-Z fg), set in_editor=1
---  VimSuspend - Suspending (Ctrl-Z), unset in_editor (async)
---  VimLeave   - Exiting, unset in_editor (sync - must complete before exit)
---
---The 50ms delay on VimEnter ensures Kitty has fully initialized the
---terminal window before we try to set user variables.
function M.create_autocmds()
	-- Editor entering/resuming: Set in_editor=1
	vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, {
		group = vim.api.nvim_create_augroup("KittyNavigatorEnter", { clear = true }),
		callback = function()
			-- Small delay to ensure Kitty terminal is ready
			vim.defer_fn(function()
				set_editor_state(true, false)
			end, 50)
		end,
	})

	-- Editor suspending (Ctrl-Z): Unset in_editor
	-- Async is fine - shell will handle navigation while suspended
	vim.api.nvim_create_autocmd("VimSuspend", {
		group = vim.api.nvim_create_augroup("KittyNavigatorSuspend", { clear = true }),
		callback = function()
			set_editor_state(false, false)
		end,
	})

	-- Editor leaving: Unset in_editor
	-- MUST be synchronous to ensure completion before Neovim exits
	vim.api.nvim_create_autocmd("VimLeave", {
		group = vim.api.nvim_create_augroup("KittyNavigatorLeave", { clear = true }),
		callback = function()
			set_editor_state(false, true)
		end,
	})
end

return M
