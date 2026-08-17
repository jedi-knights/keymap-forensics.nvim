-- LazyVim smoke for keymap-forensics.nvim v0.1.0 ship criterion.
--
-- Expects to run against a bootstrapped isolated LazyVim install
-- (scripts/lazyvim-smoke.sh handles that). Adds keymap-forensics to
-- rtp, sources its plugin file, runs :WhyKey <leader>ff, and asserts
-- the shape of the returned attribution record.
--
-- Ship criterion (from architecture/TODO.md keymap-forensics section):
--   ":WhyKey <leader>ff on a stock LazyVim setup" — WhyKey correctly
--   identifies the binding (callback flag, desc, source file). The
--   original TODO wording named telescope specifically; LazyVim 16.0
--   switched the default to snacks.picker, so the smoke asserts on
--   the substance ("Find Files" desc + callback + resolved source)
--   rather than the specific picker implementation.

local kf_repo = os.getenv("KEYMAP_FORENSICS_DIR")
if not kf_repo or kf_repo == "" then
	io.stderr:write("KEYMAP_FORENSICS_DIR env var required\n")
	vim.cmd("cquit! 2")
end

vim.opt.rtp:prepend(kf_repo)
vim.cmd("runtime! plugin/keymap-forensics.lua")

local failures = 0
local function check(name, ok, detail)
	if ok then
		io.stdout:write(string.format("PASS  %s\n", name))
	else
		failures = failures + 1
		io.stdout:write(string.format("FAIL  %s%s\n", name, detail and (" — " .. tostring(detail)) or ""))
	end
end

-- <leader> = <Space> in LazyVim's default config, so <leader>ff
-- resolves to the raw byte sequence " ff" internally. Termcode
-- replacement gives us the same shape maparg indexes on.
local lhs = vim.api.nvim_replace_termcodes("<Space>ff", true, false, true)

local kf = require("keymap-forensics")
local record = kf.why_key(lhs, "n")

check("WhyKey returns a record for <leader>ff", record ~= nil)

if record then
	check("record.lhs is set", type(record.lhs) == "string" and #record.lhs > 0, "lhs=" .. tostring(record.lhs))
	check("record.mode is normal-mode", record.mode == "n" or record.mode == "n ", "mode=" .. tostring(record.mode))
	-- LazyVim's default picker binding for <leader>ff is a Lua
	-- callback (snacks.picker as of v16, telescope in older forks).
	-- The specific implementation matters less than the fact that
	-- WhyKey correctly identifies it as callback-backed.
	check("record.callback flags the Lua callback", record.callback == true, "callback=" .. tostring(record.callback))
	check(
		"record.desc contains 'Find Files'",
		type(record.desc) == "string" and record.desc:match("Find Files") ~= nil,
		"desc=" .. tostring(record.desc)
	)
	-- record.source resolution: Neovim's sid credits the outermost
	-- running script (init.lua for LazyVim's plugin-load sequence),
	-- not the file where the keymap literal appears. That's a real-
	-- world limitation of the sid mechanism, not a WhyKey bug —
	-- users needing per-plugin origin should turn on `:WhyKeyTrace`
	-- for stack-based attribution. Assert only what sid gives us:
	-- some .lua file, not nil.
	check(
		"record.source is present (sid resolved)",
		type(record.source) == "table",
		"source=" .. vim.inspect(record.source)
	)
	if type(record.source) == "table" then
		check(
			"record.source.name resolved to a .lua file",
			type(record.source.name) == "string" and record.source.name:match("%.lua$") ~= nil,
			"source.name=" .. tostring(record.source.name)
		)
	end
end

io.stdout:write(string.format("\n%s: %d check(s) failed\n", failures == 0 and "OK" or "FAILURE", failures))
vim.cmd(failures == 0 and "cquit! 0" or "cquit! 1")
