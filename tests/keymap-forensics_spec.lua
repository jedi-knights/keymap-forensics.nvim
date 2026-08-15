describe("keymap-forensics", function()
	it("exposes a setup function", function()
		local mod = require("keymap-forensics")
		assert.is_function(mod.setup)
	end)

	it("merges opts over defaults", function()
		local mod = require("keymap-forensics")
		mod.setup({ enabled = false })
		assert.is_false(mod.config.enabled)
	end)

	it("accepts injected dependencies", function()
		local mod = require("keymap-forensics")
		local fake = { notify = function() end }
		mod.setup({}, { notifier = fake })
		-- assert.equals, not assert.are.equal — neospec's leaner
		-- luassert doesn't expose plenary.busted's `are` alias table.
		assert.equals(fake, mod.deps.notifier)
	end)

	describe("why_key", function()
		local mod

		before_each(function()
			package.loaded["keymap-forensics"] = nil
			mod = require("keymap-forensics")
		end)

		it("returns the attribution record and prints the formatted output", function()
			local deps = {
				maparg = function(lhs, _mode, _abbr, _dict)
					if lhs == "<leader>ff" then
						return {
							lhs = "<leader>ff",
							mode = "n",
							rhs = "<cmd>Telescope find_files<CR>",
							sid = 42,
							lnum = 100,
							desc = "Find files",
						}
					end
					return {}
				end,
				resolve_script_name = function(sid)
					if sid == 42 then
						return "lua/plugins/telescope.lua"
					end
				end,
			}

			local record = mod.why_key("<leader>ff", "n", deps)

			assert.equals("<leader>ff", record.lhs)
			assert.equals("<cmd>Telescope find_files<CR>", record.rhs)
			assert.equals("lua/plugins/telescope.lua", record.source.name)
		end)

		it("returns nil when the lhs has no mapping in the requested mode", function()
			local deps = {
				maparg = function()
					return {}
				end,
			}
			assert.is_nil(mod.why_key("<leader>never-bound", "n", deps))
		end)

		it("defaults to normal mode when mode is omitted", function()
			local seen_mode
			local deps = {
				maparg = function(_lhs, mode)
					seen_mode = mode
					return {}
				end,
			}
			mod.why_key("<leader>ff", nil, deps)
			assert.equals("n", seen_mode)
		end)

		it("rejects an empty lhs at the boundary", function()
			assert.has_error(function()
				mod.why_key("", "n")
			end)
		end)
	end)

	describe("why_key_conflicts", function()
		local mod

		before_each(function()
			package.loaded["keymap-forensics"] = nil
			package.loaded["keymap-forensics.conflicts"] = nil
			mod = require("keymap-forensics")
		end)

		it("returns the raw report and prints the formatted rendering", function()
			local deps = {
				get_keymap = function(mode)
					if mode == "n" then
						return {
							{ lhs = "<leader>f", rhs = ":Files<CR>", sid = 5, lnum = 12 },
							{ lhs = "<leader>ff", rhs = ":Telescope find_files<CR>", sid = 7, lnum = 42 },
						}
					end
					return {}
				end,
				resolve_script_name = function(sid)
					return ({ [5] = "config/keymaps.lua", [7] = "plugins/telescope.lua" })[sid]
				end,
			}

			local report = mod.why_key_conflicts(deps)

			assert.equals(2, report.scanned)
			assert.equals(7, #report.modes)
			-- The n-mode collision should surface at index 1 of that mode's list.
			local n_mode
			for _, m in ipairs(report.modes) do
				if m.mode == "n" then
					n_mode = m
				end
			end
			assert.equals(1, #n_mode.collisions)
			assert.equals("<leader>f", n_mode.collisions[1].prefix.lhs)
		end)
	end)

	describe("why_key_trace", function()
		local mod
		local trace

		before_each(function()
			package.loaded["keymap-forensics.trace"] = nil
			package.loaded["keymap-forensics"] = nil
			mod = require("keymap-forensics")
			trace = require("keymap-forensics.trace")
		end)

		it("returns the raw history and prints the formatted trace", function()
			-- Seed the trace log directly (bypasses install/uninstall so the
			-- facade behaviour is tested without touching vim.api).
			trace.record({ timestamp = 100, mode = "n", lhs = "<leader>x", rhs = "old" })
			trace.record({ timestamp = 200, mode = "n", lhs = "<leader>x", rhs = "new" })

			local history = mod.why_key_trace("<leader>x", "n")

			assert.equals(2, #history)
			-- Most-recent first.
			assert.equals("new", history[1].rhs)
			assert.equals("old", history[2].rhs)
		end)

		it("returns an empty list when the key has no recorded events", function()
			local history = mod.why_key_trace("<leader>never-set", "n")
			assert.equals(0, #history)
		end)

		it("defaults to normal mode when mode is omitted", function()
			trace.record({ timestamp = 1, mode = "n", lhs = "<leader>x", rhs = "a" })
			trace.record({ timestamp = 2, mode = "i", lhs = "<leader>x", rhs = "b" })
			local history = mod.why_key_trace("<leader>x")
			assert.equals(1, #history)
			assert.equals("a", history[1].rhs)
		end)

		it("rejects an empty lhs at the boundary", function()
			assert.has_error(function()
				mod.why_key_trace("", "n")
			end)
		end)
	end)
end)
