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

return M
