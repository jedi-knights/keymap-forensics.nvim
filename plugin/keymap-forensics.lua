-- keymap-forensics: Neovim plugin entry point.
-- Loaded on startup; keeps this file tiny and defers real work to the
-- lua/keymap-forensics/ module so :source and :Lazy reload behave.

if vim.g.loaded_keymap_forensics then
	return
end
vim.g.loaded_keymap_forensics = 1

-- Augroup is declared here and reused by lua/keymap-forensics/init.lua.
-- clear = true is required — a stale augroup from a previous :source
-- would fire autocmds twice.
vim.api.nvim_create_augroup("keymap_forensics", { clear = true })

-- Command registration is intentionally in plugin/ (not deferred into
-- setup()) so users get :WhyKey without any require() ceremony. The
-- lambda defers loading lua/keymap-forensics/init.lua until first
-- invocation, so startup cost is one nvim_create_user_command call.
vim.api.nvim_create_user_command("WhyKey", function(opts)
	-- fargs splits on whitespace: `:WhyKey <lhs>` or `:WhyKey <mode> <lhs>`.
	local mode, lhs
	if #opts.fargs == 1 then
		mode, lhs = "n", opts.fargs[1]
	elseif #opts.fargs == 2 then
		mode, lhs = opts.fargs[1], opts.fargs[2]
	else
		vim.notify("WhyKey: expected [<mode>] <lhs>", vim.log.levels.ERROR)
		return
	end
	require("keymap-forensics").why_key(lhs, mode)
end, {
	nargs = "+",
	desc = "Show which script bound a key: :WhyKey [<mode>] <lhs>",
})

vim.api.nvim_create_user_command("WhyKeyConflicts", function()
	require("keymap-forensics").why_key_conflicts()
end, {
	desc = "Report keymap prefix collisions across standard modes",
})

vim.api.nvim_create_user_command("WhyKeyTrace", function(opts)
	local mode, lhs
	if #opts.fargs == 1 then
		mode, lhs = "n", opts.fargs[1]
	elseif #opts.fargs == 2 then
		mode, lhs = opts.fargs[1], opts.fargs[2]
	else
		vim.notify("WhyKeyTrace: expected [<mode>] <lhs>", vim.log.levels.ERROR)
		return
	end
	require("keymap-forensics").why_key_trace(lhs, mode)
end, {
	nargs = "+",
	desc = "Print historical bindings for a key (requires require('keymap-forensics').track())",
})

vim.api.nvim_create_user_command("WhyKeyTraceReset", function()
	require("keymap-forensics").reset_trace()
end, {
	desc = "Clear the keymap-forensics trace event log",
})
