describe("keymap-forensics.conflicts", function()
	local conflicts

	before_each(function()
		package.loaded["keymap-forensics.conflicts"] = nil
		conflicts = require("keymap-forensics.conflicts")
	end)

	--- Build a deps table where `entries_by_mode[mode]` is the raw list
	--- returned to `nvim_get_keymap(mode)`. Any mode not in the table
	--- returns an empty list.
	local function fake_deps(entries_by_mode, sid_to_name)
		return {
			get_keymap = function(mode)
				return entries_by_mode[mode] or {}
			end,
			resolve_script_name = function(sid)
				return sid_to_name and sid_to_name[sid] or nil
			end,
		}
	end

	--- Helper: pull the collisions for a specific mode out of a report.
	local function collisions_for(report, mode)
		for _, m in ipairs(report.modes) do
			if m.mode == mode then
				return m.collisions
			end
		end
		return nil
	end

	it("returns a fully-populated report for every standard mode", function()
		local report = conflicts.find(fake_deps({}))
		assert.equals(0, report.scanned)
		-- All 7 standard modes must appear so the renderer can print
		-- "(none)" per mode instead of silently skipping the header.
		assert.equals(7, #report.modes)
		local seen_modes = {}
		for _, m in ipairs(report.modes) do
			seen_modes[m.mode] = true
			assert.equals(0, #m.collisions)
		end
		for _, mode in ipairs({ "n", "i", "v", "x", "o", "c", "t" }) do
			assert.is_true(seen_modes[mode], "expected mode " .. mode .. " in report")
		end
	end)

	it("counts scanned entries across modes", function()
		local report = conflicts.find(fake_deps({
			n = { { lhs = "a" }, { lhs = "b" } },
			i = { { lhs = "jk" } },
		}))
		assert.equals(3, report.scanned)
	end)

	it("reports no collision when no lhs is a prefix of another", function()
		local report = conflicts.find(fake_deps({
			n = { { lhs = "foo" }, { lhs = "bar" }, { lhs = "baz" } },
		}))
		assert.equals(0, #collisions_for(report, "n"))
	end)

	it("reports a single shadowing prefix when one lhs is a prefix of another", function()
		local report = conflicts.find(fake_deps({
			n = {
				{ lhs = "<leader>f", rhs = ":Files<CR>", sid = 5, lnum = 12 },
				{ lhs = "<leader>ff", rhs = "<cmd>Telescope find_files<CR>", sid = 7, lnum = 42 },
			},
		}, { [5] = "config/keymaps.lua", [7] = "plugins/telescope.lua" }))

		local mode = collisions_for(report, "n")
		assert.equals(1, #mode)
		assert.equals("<leader>f", mode[1].prefix.lhs)
		assert.equals("config/keymaps.lua", mode[1].prefix.source.name)
		assert.equals(1, #mode[1].shadowed)
		assert.equals("<leader>ff", mode[1].shadowed[1].lhs)
	end)

	it("skips namespace prefixes that are themselves unbound", function()
		-- The `<leader>f` prefix is not in the entry list — only <leader>ff
		-- and <leader>fg are. This is Vim's `g<x>` namespace pattern
		-- (the prefix is a menu, not a binding) and MUST NOT be reported.
		local report = conflicts.find(fake_deps({
			n = {
				{ lhs = "<leader>ff", rhs = "1", sid = 1 },
				{ lhs = "<leader>fg", rhs = "2", sid = 1 },
			},
		}))
		assert.equals(0, #collisions_for(report, "n"))
	end)

	it("reports every prefix in a deep chain", function()
		-- a, ab, abc, abcd → a shadows 3, ab shadows 2, abc shadows 1,
		-- abcd shadows nothing (leaf). Three collision entries total.
		local report = conflicts.find(fake_deps({
			n = {
				{ lhs = "a", rhs = "1", sid = 1 },
				{ lhs = "ab", rhs = "2", sid = 1 },
				{ lhs = "abc", rhs = "3", sid = 1 },
				{ lhs = "abcd", rhs = "4", sid = 1 },
			},
		}))
		local mode = collisions_for(report, "n")
		assert.equals(3, #mode)
		-- Sorted by prefix.lhs (ascending); shortest first.
		assert.equals("a", mode[1].prefix.lhs)
		assert.equals(3, #mode[1].shadowed)
		assert.equals("ab", mode[2].prefix.lhs)
		assert.equals(2, #mode[2].shadowed)
		assert.equals("abc", mode[3].prefix.lhs)
		assert.equals(1, #mode[3].shadowed)
	end)

	it("reports collisions per-mode independently", function()
		local report = conflicts.find(fake_deps({
			n = { { lhs = "a", sid = 1 }, { lhs = "ab", sid = 1 } },
			i = { { lhs = "j", sid = 2 }, { lhs = "k", sid = 2 } },
		}))
		assert.equals(1, #collisions_for(report, "n"))
		assert.equals(0, #collisions_for(report, "i"))
	end)

	it("shapes callback-backed entries with rhs=nil and callback=true", function()
		local report = conflicts.find(fake_deps({
			n = {
				{ lhs = "x", callback = function() end, sid = 1 },
				{ lhs = "xy", rhs = "y", sid = 1 },
			},
		}))
		local shaped = collisions_for(report, "n")[1].prefix
		assert.is_true(shaped.callback)
		assert.is_nil(shaped.rhs)
	end)

	it("omits source when sid is zero (built-in or command-line)", function()
		local report = conflicts.find(fake_deps({
			n = {
				{ lhs = "x", rhs = "1", sid = 0 },
				{ lhs = "xy", rhs = "2", sid = 0 },
			},
		}))
		local prefix = collisions_for(report, "n")[1].prefix
		assert.is_nil(prefix.source)
	end)

	it("filters entries with missing or empty lhs before scanning", function()
		-- Real Neovim never returns these, but guarding is cheap and
		-- keeps the module honest against future API changes.
		local report = conflicts.find(fake_deps({
			n = {
				{ lhs = "foo", rhs = "1", sid = 1 },
				{ lhs = "", rhs = "2", sid = 1 },
				{ rhs = "3", sid = 1 }, -- no lhs
			},
		}))
		assert.equals(1, report.scanned)
	end)
end)
