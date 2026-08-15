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
end

return M
