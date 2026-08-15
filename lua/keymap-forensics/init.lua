--- keymap-forensics: <one-line description here>

local config = require("keymap-forensics.config")
local detector = require("keymap-forensics.detector")

local M = {}

--- Set up the plugin. Safe to call multiple times; last call wins.
--- @param opts table? User-supplied config; merged over defaults.
--- @param deps table? Injected dependencies. Tests pass fakes here;
---                    production callers omit this and get real
---                    dependencies resolved from the runtime.
function M.setup(opts, deps)
	if not detector.should_load() then
		return
	end

	M.config = config.merge(opts or {})
	M.deps = deps or {}
end

return M
