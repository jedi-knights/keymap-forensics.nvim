--- Render attribution records as human-readable text.
---
--- Kept separate from the attribution module so the shape of the
--- record (its fields) can evolve without churning display code, and
--- so both halves are testable in isolation.

local M = {}

--- Render an attribution record as a multi-line string.
--- Returns a stable, grep-friendly shape:
---
---   <lhs> (<mode> mode)
---     bound to: <rhs or callback>
---     source:   <file>:<line>
---     desc:     <desc>
---     scope:    buffer-local        (only when buffer-local)
---
--- @param record table? The result of attribution.attribute.
--- @return string
function M.render(record)
	if record == nil then
		return "no mapping"
	end
	assert(type(record) == "table", "format.render: record must be a table or nil")

	local lines = {
		string.format("%s (%s mode)", record.lhs, record.mode),
	}

	if record.callback then
		table.insert(lines, "  bound to: <lua callback>")
	elseif record.plug_target then
		table.insert(lines, string.format("  bound to: %s → %s", record.plug_hop, record.plug_target))
	elseif record.plug_hop then
		-- <Plug> RHS with no resolvable target — still useful to show the hop.
		table.insert(lines, string.format("  bound to: %s (unresolved <Plug>)", record.plug_hop))
	else
		table.insert(lines, string.format("  bound to: %s", record.rhs or "<nil>"))
	end

	if record.source then
		if record.source.name then
			table.insert(lines, string.format("  source:   %s:%d", record.source.name, record.source.line or 0))
		else
			table.insert(lines, string.format("  source:   script id %d", record.source.sid))
		end
	end

	if record.desc and record.desc ~= "" then
		table.insert(lines, string.format("  desc:     %s", record.desc))
	end

	if record.buffer_local then
		table.insert(lines, "  scope:    buffer-local")
	end

	return table.concat(lines, "\n")
end

--- Render a single shaped conflict entry as one indented line:
---   "    <lhs>   <rhs>   (<source>)"
--- Padding for the lhs column keeps the rhs aligned within a
--- collision group.
--- @param entry table Shape from conflicts.shape_entry.
--- @param lhs_width integer Width to pad the lhs column to.
--- @return string
local function render_conflict_entry(entry, lhs_width)
	local binding
	if entry.callback then
		binding = "<lua callback>"
	else
		binding = entry.rhs or "<nil>"
	end

	local source_suffix = ""
	if entry.source then
		if entry.source.name then
			source_suffix = string.format("  (%s:%d)", entry.source.name, entry.source.line or 0)
		else
			source_suffix = string.format("  (script id %d)", entry.source.sid)
		end
	end

	return string.format("    %-" .. lhs_width .. "s  %s%s", entry.lhs, binding, source_suffix)
end

--- Render a conflicts report (from `conflicts.find`) as a multi-line
--- string. Every scanned mode gets a header, whether or not it has
--- collisions — the "(no shadowing prefixes)" line proves the mode
--- was inspected and nothing was silently filtered.
--- @param report table? { scanned, modes = { {mode, collisions}, ... } }
--- @return string
function M.render_conflicts(report)
	if report == nil then
		return "no conflicts report"
	end
	assert(type(report) == "table", "format.render_conflicts: report must be a table or nil")

	local out = {}
	for _, mode_report in ipairs(report.modes or {}) do
		table.insert(out, string.format("Prefix conflicts (%s mode):", mode_report.mode))
		if #mode_report.collisions == 0 then
			table.insert(out, "  none")
		else
			for _, collision in ipairs(mode_report.collisions) do
				local n = #collision.shadowed
				table.insert(out, string.format("  %s  blocks %d longer sequence(s):", collision.prefix.lhs, n))
				local width = #collision.prefix.lhs
				for _, entry in ipairs(collision.shadowed) do
					if #entry.lhs > width then
						width = #entry.lhs
					end
				end
				table.insert(out, render_conflict_entry(collision.prefix, width))
				for _, entry in ipairs(collision.shadowed) do
					table.insert(out, render_conflict_entry(entry, width))
				end
			end
		end
		table.insert(out, "")
	end
	table.insert(out, string.format("Scanned %d mappings across %d modes.", report.scanned or 0, #(report.modes or {})))

	return table.concat(out, "\n")
end

--- Format a single trace event's timestamp. os.date-friendly, HH:MM:SS.
local function fmt_time(ts)
	if type(ts) ~= "number" then
		return "??:??:??"
	end
	return os.date("%H:%M:%S", ts)
end

--- Render one trace event as an indented multi-line block. Index is the
--- 1-based position in the history list (index=1 is the winner).
local function render_trace_event(event, index, total)
	local label = index == 1 and "winner" or "superseded"
	local lines = {
		string.format("  #%d  %-10s  %s", index, label, fmt_time(event.timestamp)),
	}

	if event.has_callback then
		local body = "<lua callback>"
		if event.callback_source then
			body =
				string.format("<lua callback @ %s:%d>", event.callback_source.source, event.callback_source.linedefined)
		end
		table.insert(lines, "      bound to:  " .. body)
	else
		table.insert(lines, "      bound to:  " .. (event.rhs or "<nil>"))
	end

	if event.caller and event.caller.source then
		table.insert(lines, string.format("      source:    %s:%d", event.caller.source, event.caller.line or 0))
	end

	if event.opts and event.opts.desc and event.opts.desc ~= "" then
		table.insert(lines, "      desc:      " .. event.opts.desc)
	end

	if event.buffer_local then
		table.insert(lines, "      scope:     buffer-local")
	end

	-- Suppress the trailing blank line on the last entry so callers can
	-- render_trace() straight into :messages without an ugly extra newline.
	if index < total then
		table.insert(lines, "")
	end

	return table.concat(lines, "\n")
end

--- Render a trace history (from `trace.history(lhs, mode)`) as a multi-line
--- string. Empty history returns an actionable message that names the fix.
--- @param history table[] Most-recent-first list of events.
--- @param lhs string
--- @param mode string
--- @return string
function M.render_trace(history, lhs, mode)
	assert(type(history) == "table", "format.render_trace: history must be a table")
	assert(type(lhs) == "string" and #lhs > 0, "format.render_trace: lhs required")
	assert(type(mode) == "string" and #mode > 0, "format.render_trace: mode required")

	if #history == 0 then
		return string.format(
			"no events recorded for %s (%s mode) — did require('keymap-forensics').track() run before the mapping was set?",
			lhs,
			mode
		)
	end

	local out = {
		string.format("%s (%s mode) — %d event(s) recorded", lhs, mode, #history),
		"",
	}
	for i, event in ipairs(history) do
		out[#out + 1] = render_trace_event(event, i, #history)
	end
	return table.concat(out, "\n")
end

return M
