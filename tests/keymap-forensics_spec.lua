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
end)
