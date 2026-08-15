--- keymap-forensics: runtime diagnosis of `:map` chaos.
---
--- Public entry point for the :WhyKey command. The heavy lifting is
--- split into attribution.lua (pure parse of maparg's dict return) and
--- format.lua (pure render of an attribution record). This module is
--- a thin facade — the two seams above are the test surface.

local attribution = require("keymap-forensics.attribution")
local format = require("keymap-forensics.format")

local M = {}

--- Answer "who bound this key?" for a single lhs.
--- Prints the formatted attribution to :messages so :message-history
--- captures it. Returns the raw record so callers can pipe it further.
--- @param lhs string
--- @param mode string? Defaults to "n" (normal mode).
--- @param deps table? Injected for tests; production callers omit it.
--- @return table? record
function M.why_key(lhs, mode, deps)
	assert(type(lhs) == "string" and #lhs > 0, "why_key: lhs required")
	mode = mode or "n"
	local record = attribution.attribute(lhs, mode, deps)
	print(format.render(record))
	return record
end

--- Scan all standard modes for prefix collisions — mappings whose
--- lhs is a strict prefix of another mapping in the same mode.
--- Prints the formatted report to :messages and returns the raw
--- report so callers can pipe it further.
--- @param deps table? Injected for tests.
--- @return table report
function M.why_key_conflicts(deps)
	local report = require("keymap-forensics.conflicts").find(deps)
	print(format.render_conflicts(report))
	return report
end

--- Install the trace shim. Idempotent. Call this early in init.lua to
--- catch mappings registered by plugins that load after keymap-forensics.
--- Mappings set before install() runs are NOT captured — the shim can
--- only observe what passes through Lua-side vim.api after it's in place.
--- @param opts table? { max_events = integer }  0 means unbounded
function M.track(opts)
	opts = opts or {}
	require("keymap-forensics.trace").install({ max_events = opts.max_events })
end

--- Uninstall the trace shim. The event log is preserved so `:WhyKeyTrace`
--- keeps working against what was captured while tracking was on.
function M.untrack()
	require("keymap-forensics.trace").uninstall()
end

--- Clear the trace event log. Shim install state is unaffected.
function M.reset_trace()
	require("keymap-forensics.trace").reset()
end

--- Print the full binding history for a key.
--- @param lhs string
--- @param mode string? Defaults to "n".
--- @return table history — most-recent first.
function M.why_key_trace(lhs, mode)
	assert(type(lhs) == "string" and #lhs > 0, "why_key_trace: lhs required")
	mode = mode or "n"
	local history = require("keymap-forensics.trace").history(lhs, mode)
	print(format.render_trace(history, lhs, mode))
	return history
end

--- Optional setup for opts + DI parity with the scaffold. The plugin
--- registers commands at load time; users may skip setup entirely.
--- @param opts table?
--- @param deps table?
function M.setup(opts, deps)
	local detector = require("keymap-forensics.detector")
	if not detector.should_load() then
		return
	end
	M.config = require("keymap-forensics.config").merge(opts or {})
	M.deps = deps or {}
end

return M
