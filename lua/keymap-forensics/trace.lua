--- Historical keymap-set tracker.
---
--- Opt-in via `install()` (or the facade `require("keymap-forensics").track()`).
--- Wraps `vim.api.nvim_set_keymap` and `vim.api.nvim_buf_set_keymap` so every
--- Lua-side mapping registration passes through a recorder before reaching the
--- original function. Vimscript `:map` calls are NOT observed — they take
--- C paths this module cannot see.
---
--- The record + history + reset core is pure and testable without touching
--- `vim.api`. The install path monkey-patches `deps.api` (or `vim.api`); tests
--- inject a fake `api` table so they never mutate the real editor.

local M = {}

-- Module-local state. All access goes through the exported functions so tests
-- can reset it deterministically by dropping the package.loaded cache entry.
local _log = {}
local _max_events = 50000 -- 0 means unbounded
local _installed = false
local _originals = {} -- { nvim_set_keymap, nvim_buf_set_keymap }
local _api_table = nil -- table we monkey-patched; kept so uninstall works

--- Append an event to the log; drop the oldest first when at capacity.
--- @param event table
function M.record(event)
	assert(type(event) == "table", "trace.record: event must be a table")
	_log[#_log + 1] = event
	if _max_events > 0 and #_log > _max_events then
		-- FIFO eviction. O(N) on overflow; only triggers past the (large) cap.
		table.remove(_log, 1)
	end
end

--- Return all events, chronological (index 1 = earliest).
--- Copy defensively so callers can't mutate internal state.
--- @return table[]
function M.all()
	return vim.deepcopy(_log)
end

--- Events for a specific (lhs, mode), most-recent first. The head entry is the
--- most-recent binding attempt — usually the current winner, but callers who
--- need real-time truth should still query `maparg`.
--- @param lhs string
--- @param mode string
--- @return table[]
function M.history(lhs, mode)
	assert(type(lhs) == "string" and #lhs > 0, "trace.history: lhs required")
	assert(type(mode) == "string" and #mode > 0, "trace.history: mode required")
	local out = {}
	for i = #_log, 1, -1 do
		local ev = _log[i]
		if ev.lhs == lhs and ev.mode == mode then
			out[#out + 1] = ev
		end
	end
	return out
end

--- Total events observed across every key and mode.
function M.count()
	return #_log
end

--- Clear the log. install / uninstall state is unaffected.
function M.reset()
	_log = {}
end

--- Whether the shim is currently in place.
function M.installed()
	return _installed
end

--- Walk the call stack from just above the wrapper looking for the first
--- caller that is NOT a Neovim runtime file or a C frame. This is the file
--- and line the user actually wrote — vim.keymap.set's internals are skipped.
--- Bounded at 20 frames to satisfy the algorithmic-complexity rule (any real
--- caller is 2-6 frames up; 20 is generous slack).
---
--- Neovim reports runtime files in two shapes: the short form (e.g.
--- `@vim/keymap.lua`) and the fully-qualified form (e.g. `@/opt/.../runtime/lua/vim/keymap.lua`).
--- Both are skipped so plain vim.keymap.set callers get their real caller reported.
local function find_user_caller()
	local level = 3 -- skip find_user_caller (1) and the wrapper (2)
	for _ = 1, 20 do
		local info = debug.getinfo(level, "Sl")
		if not info then
			return nil
		end
		local source = info.source or ""
		if source ~= "=[C]" and not source:match("/runtime/lua/vim/") and not source:match("^@vim/") then
			return { source = source, line = info.currentline }
		end
		level = level + 1
	end
	return nil
end

--- Build the event record from a mapping-set call's arguments.
---
--- Neovim exposes two callback conventions:
---   * caller passes rhs = <function>     — direct callback style
---   * caller passes rhs = "" + opts.callback = <function>
---     — the shape vim.keymap.set produces when handed a Lua callable
--- Both are recognised and normalised into the same has_callback / callback_source
--- record fields so downstream renderers don't need to know the difference.
local function shape_event(mode, lhs, rhs, opts, buffer_local, now, caller)
	local callback
	if type(rhs) == "function" then
		callback = rhs
	elseif type(opts) == "table" and type(opts.callback) == "function" then
		callback = opts.callback
	end

	local event = {
		timestamp = now(),
		mode = mode,
		lhs = lhs,
		rhs = (callback == nil) and (type(rhs) == "string" and rhs or nil) or nil,
		has_callback = callback ~= nil,
		buffer_local = buffer_local,
		opts = opts,
		caller = caller,
	}
	if callback then
		-- debug.getinfo on the function itself exposes where its body was
		-- defined. Not always the same file as the caller (factory-produced
		-- callbacks are common in plugin code).
		local info = debug.getinfo(callback, "S")
		if info then
			event.callback_source = { source = info.source, linedefined = info.linedefined }
		end
	end
	return event
end

--- Install the shim. Idempotent — a second install is a no-op.
--- @param deps table? { api: table, now: fun(): number, max_events: integer }
function M.install(deps)
	if _installed then
		return
	end

	deps = deps or {}
	local api = deps.api or vim.api
	local now = deps.now or os.time
	if deps.max_events then
		_max_events = deps.max_events
	end

	_api_table = api
	_originals.nvim_set_keymap = api.nvim_set_keymap
	_originals.nvim_buf_set_keymap = api.nvim_buf_set_keymap

	api.nvim_set_keymap = function(mode, lhs, rhs, opts)
		local caller = find_user_caller()
		-- Recording is best-effort. If shape_event or record throws (e.g. a
		-- weird stack we didn't anticipate), the underlying keymap MUST still
		-- get set — trace is a diagnostic; correctness of the actual mapping
		-- is not negotiable.
		pcall(function()
			M.record(shape_event(mode, lhs, rhs, opts or {}, false, now, caller))
		end)
		return _originals.nvim_set_keymap(mode, lhs, rhs, opts)
	end

	api.nvim_buf_set_keymap = function(buffer, mode, lhs, rhs, opts)
		local caller = find_user_caller()
		pcall(function()
			M.record(shape_event(mode, lhs, rhs, opts or {}, true, now, caller))
		end)
		return _originals.nvim_buf_set_keymap(buffer, mode, lhs, rhs, opts)
	end

	_installed = true
end

--- Uninstall the shim. The trace log is preserved so `:WhyKeyTrace` still
--- returns history the shim collected while it was active. Idempotent.
function M.uninstall()
	if not _installed then
		return
	end
	_api_table.nvim_set_keymap = _originals.nvim_set_keymap
	_api_table.nvim_buf_set_keymap = _originals.nvim_buf_set_keymap
	_originals = {}
	_api_table = nil
	_installed = false
end

return M
