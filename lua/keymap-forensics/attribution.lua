--- Attribute a keymap to its source script.
---
--- Vim tracks the script id (SID) and line number of every mapping.
--- `maparg(lhs, mode, false, true)` returns that as a dict; this module
--- reshapes the dict into a stable record and resolves the SID to a
--- filename via getscriptinfo (Neovim 0.10+).
---
--- The module is pure — every IO seam is injected via `deps` so the
--- table-driven tests never touch a real editor.

local M = {}

--- Resolve a script filename from a script ID.
--- @param sid integer? Script id from maparg's dict return.
--- @return string? filename, or nil if unresolvable.
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

--- Chase a <Plug> RHS one hop to reveal the underlying command.
--- Multi-hop chains are deliberately not followed here — one hop is
--- enough to answer "what plugin owns this?" and multi-hop chasing
--- risks cycles that would need a visited-set guard.
--- @param lhs string
--- @param mode string
--- @param maparg fun(lhs: string, mode: string, abbr: boolean, dict: boolean): table
--- @return string? underlying rhs
local function resolve_plug_target(lhs, mode, maparg)
	local nested = maparg(lhs, mode, false, true)
	if type(nested) ~= "table" or vim.tbl_isempty(nested) then
		return nil
	end
	return nested.rhs
end

--- Attribute a keymap to its source.
--- @param lhs string The left-hand side, e.g. "<leader>ff".
--- @param mode string Vim mode character ("n", "i", "x", "v", "o", "c", "t").
--- @param deps table? { maparg: ..., resolve_script_name: ... }
--- @return table? record — nil when the lhs has no mapping in mode.
function M.attribute(lhs, mode, deps)
	assert(type(lhs) == "string" and #lhs > 0, "attribution.attribute: lhs must be a non-empty string")
	assert(type(mode) == "string" and #mode > 0, "attribution.attribute: mode must be a non-empty string")

	deps = deps or {}
	local maparg = deps.maparg or vim.fn.maparg
	local resolver = deps.resolve_script_name or default_resolve_script_name

	local d = maparg(lhs, mode, false, true)
	if type(d) ~= "table" or vim.tbl_isempty(d) then
		return nil
	end

	local record = {
		lhs = d.lhs or lhs,
		mode = d.mode or mode,
		rhs = d.rhs, -- nil for callback-backed mappings
		callback = d.callback ~= nil,
		expr = d.expr == 1,
		silent = d.silent == 1,
		buffer_local = d.buffer == 1,
		noremap = d.noremap == 1,
		desc = d.desc,
	}

	if d.sid and d.sid > 0 then
		record.source = {
			sid = d.sid,
			line = d.lnum,
			name = resolver(d.sid),
		}
	end

	if type(d.rhs) == "string" and d.rhs:match("^<Plug>") then
		record.plug_hop = d.rhs
		record.plug_target = resolve_plug_target(d.rhs, mode, maparg)
	end

	return record
end

return M
