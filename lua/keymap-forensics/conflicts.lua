--- Detect keymap prefix collisions across standard Vim modes.
---
--- A "conflict" here is a mapping whose lhs is a strict prefix of one
--- or more other mappings in the same mode. Pressing the prefix
--- triggers it immediately (or after `timeoutlen`), blocking the
--- longer sequences. Namespace-style prefixes that are themselves
--- unbound (Vim's `g` group, for example) do NOT count and are not
--- reported — only entries the user has actually bound.
---
--- The module is pure: `nvim_get_keymap` and the script-name resolver
--- are injectable via `deps`, so tests never touch a real editor.

local M = {}

-- Standard set from :h map-modes. `s` and `l` are subsets covered by
-- entries already reported under other modes; not worth double-report.
local MODES = { "n", "i", "v", "x", "o", "c", "t" }

--- Bound on entries per mode. LazyVim-scale users see ~40 per mode
--- (well under 1000 total). The naive O(N²) scan below is only
--- economically fine while N stays small; a 10k-mapping mode would be
--- a review conversation, not a silent slowdown.
local MAX_ENTRIES_PER_MODE = 5000

local function starts_with(s, prefix)
	return #s > #prefix and s:sub(1, #prefix) == prefix
end

--- Default script-id → filename resolver. Mirrors attribution.lua's
--- default rather than depending on it — cross-module coupling for
--- one utility function isn't worth the import chain.
local function default_resolve_script_name(sid)
	if not sid or sid <= 0 then
		return nil
	end
	if vim.fn.exists("*getscriptinfo") ~= 1 then
		return nil
	end
	local info = vim.fn.getscriptinfo({ sid = sid })
	if type(info) == "table" and info[1] and type(info[1].name) == "string" then
		return info[1].name
	end
	return nil
end

--- Reduce a raw nvim_get_keymap entry to the minimal record the
--- report needs. Fields the renderer never displays (silent, expr,
--- noremap, buffer) are dropped to keep the report data-only.
local function shape_entry(raw, resolver)
	local record = {
		lhs = raw.lhs,
		rhs = raw.rhs, -- nil for callback-backed mappings
		callback = raw.callback ~= nil,
		desc = raw.desc,
	}
	if raw.sid and raw.sid > 0 then
		record.source = {
			sid = raw.sid,
			line = raw.lnum,
			name = resolver(raw.sid),
		}
	end
	return record
end

--- Find (prefix, shadowed) pairs in a pre-sorted list of entries.
--- O(N²) — bounded by MAX_ENTRIES_PER_MODE above.
local function find_mode_collisions(entries)
	assert(
		#entries <= MAX_ENTRIES_PER_MODE,
		string.format("conflicts: mode has %d entries, over guard bound %d", #entries, MAX_ENTRIES_PER_MODE)
	)
	local out = {}
	for _, prefix in ipairs(entries) do
		local shadowed = {}
		for _, candidate in ipairs(entries) do
			if starts_with(candidate.lhs, prefix.lhs) then
				table.insert(shadowed, candidate)
			end
		end
		if #shadowed > 0 then
			table.insert(out, { prefix = prefix, shadowed = shadowed })
		end
	end
	return out
end

--- Scan mappings across all standard modes and return a report.
--- @param deps table? { get_keymap: fun(mode: string): table[],
---                       resolve_script_name: fun(sid: integer): string? }
--- @return table report — { scanned = integer, modes = list of { mode, collisions } }
function M.find(deps)
	deps = deps or {}
	local get_keymap = deps.get_keymap or vim.api.nvim_get_keymap
	local resolver = deps.resolve_script_name or default_resolve_script_name

	local report = { scanned = 0, modes = {} }

	for _, mode in ipairs(MODES) do
		local raw_entries = get_keymap(mode) or {}
		local shaped = {}
		for _, raw in ipairs(raw_entries) do
			if type(raw.lhs) == "string" and #raw.lhs > 0 then
				table.insert(shaped, shape_entry(raw, resolver))
			end
		end
		table.sort(shaped, function(a, b)
			return a.lhs < b.lhs
		end)
		report.scanned = report.scanned + #shaped
		table.insert(report.modes, { mode = mode, collisions = find_mode_collisions(shaped) })
	end

	return report
end

return M
