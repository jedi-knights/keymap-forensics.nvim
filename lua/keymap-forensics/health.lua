--- :checkhealth keymap-forensics entry point.

local M = {}

function M.check()
	vim.health.start("keymap-forensics")

	local detector = require("keymap-forensics.detector")
	if detector.should_load() then
		vim.health.ok("environment supports keymap-forensics")
	else
		vim.health.warn("keymap-forensics would not load in this environment (detector.should_load returned false)")
	end

	-- getscriptinfo is what turns a mapping's script id into a filename.
	-- Neovim 0.10+ ships it; on older versions :WhyKey still works but
	-- the source line falls back to "script id N" without a filename.
	if vim.fn.exists("*getscriptinfo") == 1 then
		vim.health.ok("getscriptinfo available — source paths will resolve")
	else
		vim.health.info("getscriptinfo not available (Neovim < 0.10) — source paths degrade to script id")
	end
end

return M
