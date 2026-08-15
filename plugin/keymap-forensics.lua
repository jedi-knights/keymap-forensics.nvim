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
