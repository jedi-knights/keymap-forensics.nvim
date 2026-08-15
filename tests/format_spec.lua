describe("keymap-forensics.format", function()
	local format

	before_each(function()
		package.loaded["keymap-forensics.format"] = nil
		format = require("keymap-forensics.format")
	end)

	it("returns 'no mapping' for nil input", function()
		assert.equals("no mapping", format.render(nil))
	end)

	it("renders a direct rhs mapping", function()
		local out = format.render({
			lhs = "<leader>x",
			mode = "n",
			rhs = ":echo 1<CR>",
		})
		assert.equals("<leader>x (n mode)\n  bound to: :echo 1<CR>", out)
	end)

	it("renders a callback-backed mapping", function()
		local out = format.render({
			lhs = "<leader>x",
			mode = "n",
			callback = true,
		})
		assert.equals("<leader>x (n mode)\n  bound to: <lua callback>", out)
	end)

	it("renders a resolved <Plug> hop as 'from → to'", function()
		local out = format.render({
			lhs = "<leader>ff",
			mode = "n",
			rhs = "<Plug>(TelescopeFindFiles)",
			plug_hop = "<Plug>(TelescopeFindFiles)",
			plug_target = "<cmd>Telescope find_files<CR>",
		})
		assert.is_truthy(out:match("bound to: <Plug>%(TelescopeFindFiles%) → <cmd>Telescope find_files<CR>"))
	end)

	it("renders an unresolved <Plug> hop with the (unresolved <Plug>) suffix", function()
		local out = format.render({
			lhs = "<leader>ff",
			mode = "n",
			rhs = "<Plug>(Dangling)",
			plug_hop = "<Plug>(Dangling)",
		})
		assert.is_truthy(out:match("bound to: <Plug>%(Dangling%) %(unresolved <Plug>%)"))
	end)

	it("includes a resolved source file and line", function()
		local out = format.render({
			lhs = "<leader>ff",
			mode = "n",
			rhs = "x",
			source = { sid = 42, line = 100, name = "lua/plugins/telescope.lua" },
		})
		assert.is_truthy(out:match("source:   lua/plugins/telescope.lua:100"))
	end)

	it("falls back to script id when the source name is unresolved", function()
		local out = format.render({
			lhs = "<leader>ff",
			mode = "n",
			rhs = "x",
			source = { sid = 99 },
		})
		assert.is_truthy(out:match("source:   script id 99"))
	end)

	it("appends desc line only when present", function()
		local out = format.render({
			lhs = "<leader>ff",
			mode = "n",
			rhs = "x",
			desc = "Find files",
		})
		assert.is_truthy(out:match("desc:     Find files"))
	end)

	it("does not append desc line for empty string", function()
		local out = format.render({ lhs = "<leader>ff", mode = "n", rhs = "x", desc = "" })
		assert.is_nil(out:match("desc:"))
	end)

	it("appends buffer-local scope when the mapping is buffer-local", function()
		local out = format.render({
			lhs = "<leader>ff",
			mode = "n",
			rhs = "x",
			buffer_local = true,
		})
		assert.is_truthy(out:match("scope:    buffer%-local"))
	end)

	it("does not append scope line for global mappings", function()
		local out = format.render({ lhs = "<leader>ff", mode = "n", rhs = "x", buffer_local = false })
		assert.is_nil(out:match("scope:"))
	end)

	it("rejects a non-nil, non-table record", function()
		assert.has_error(function()
			format.render("not a table")
		end)
	end)

	describe("render_conflicts", function()
		it("returns 'no conflicts report' for nil input", function()
			assert.equals("no conflicts report", format.render_conflicts(nil))
		end)

		it("rejects a non-nil, non-table report", function()
			assert.has_error(function()
				format.render_conflicts("not a table")
			end)
		end)

		it("emits a per-mode header even when a mode has no collisions", function()
			local out = format.render_conflicts({
				scanned = 0,
				modes = {
					{ mode = "n", collisions = {} },
					{ mode = "i", collisions = {} },
				},
			})
			-- Both headers must appear so the reader can see the mode
			-- was inspected. "(none)" body proves nothing was silently
			-- filtered out.
			assert.is_truthy(out:match("Prefix conflicts %(n mode%):"))
			assert.is_truthy(out:match("Prefix conflicts %(i mode%):"))
			assert.is_truthy(out:match("  none"))
		end)

		it("renders a collision with prefix line and shadowed lines", function()
			local out = format.render_conflicts({
				scanned = 2,
				modes = {
					{
						mode = "n",
						collisions = {
							{
								prefix = {
									lhs = "<leader>f",
									rhs = ":Files<CR>",
									callback = false,
									source = { name = "config/keymaps.lua", line = 12, sid = 5 },
								},
								shadowed = {
									{
										lhs = "<leader>ff",
										rhs = "<cmd>Telescope find_files<CR>",
										callback = false,
										source = { name = "plugins/telescope.lua", line = 42, sid = 7 },
									},
								},
							},
						},
					},
				},
			})

			assert.is_truthy(out:match("<leader>f  blocks 1 longer sequence%(s%):"))
			-- Prefix line rendered first, with source in parens.
			assert.is_truthy(out:match("<leader>f%s+:Files<CR>%s+%(config/keymaps%.lua:12%)"))
			-- Then the shadowed line.
			assert.is_truthy(out:match("<leader>ff%s+<cmd>Telescope find_files<CR>%s+%(plugins/telescope%.lua:42%)"))
		end)

		it("renders a callback-backed entry as <lua callback>", function()
			local out = format.render_conflicts({
				scanned = 2,
				modes = {
					{
						mode = "n",
						collisions = {
							{
								prefix = { lhs = "x", callback = true },
								shadowed = { { lhs = "xy", rhs = "y", callback = false } },
							},
						},
					},
				},
			})
			assert.is_truthy(out:match("x%s+<lua callback>"))
		end)

		it("falls back to 'script id N' when the source name is unresolved", function()
			local out = format.render_conflicts({
				scanned = 2,
				modes = {
					{
						mode = "n",
						collisions = {
							{
								prefix = { lhs = "x", rhs = "1", source = { sid = 99 } },
								shadowed = { { lhs = "xy", rhs = "2", source = { sid = 99 } } },
							},
						},
					},
				},
			})
			assert.is_truthy(out:match("%(script id 99%)"))
		end)

		it("closes with a scan summary line", function()
			local out = format.render_conflicts({
				scanned = 42,
				modes = { { mode = "n", collisions = {} } },
			})
			assert.is_truthy(out:match("Scanned 42 mappings across 1 modes%."))
		end)
	end)

	describe("render_trace", function()
		it("returns an actionable message when the history is empty", function()
			local out = format.render_trace({}, "<leader>ff", "n")
			assert.is_truthy(out:match("no events recorded"))
			assert.is_truthy(out:match("<leader>ff"))
			assert.is_truthy(out:match("track"))
		end)

		it("labels the head entry 'winner' and later entries 'superseded'", function()
			local history = {
				{ timestamp = 100, rhs = "new", caller = { source = "a.lua", line = 1 } },
				{ timestamp = 50, rhs = "old", caller = { source = "b.lua", line = 2 } },
			}
			local out = format.render_trace(history, "<leader>x", "n")
			assert.is_truthy(out:match("#1%s+winner"))
			assert.is_truthy(out:match("#2%s+superseded"))
		end)

		it("renders event count in the header", function()
			local history = {
				{ timestamp = 100, rhs = "a", caller = { source = "x", line = 1 } },
				{ timestamp = 90, rhs = "b", caller = { source = "y", line = 2 } },
				{ timestamp = 80, rhs = "c", caller = { source = "z", line = 3 } },
			}
			local out = format.render_trace(history, "<leader>x", "n")
			assert.is_truthy(out:match("<leader>x %(n mode%) — 3 event%(s%) recorded"))
		end)

		it("renders a callback-backed event with its defined-at location", function()
			local history = {
				{
					timestamp = 100,
					has_callback = true,
					callback_source = { source = "@plugins/telescope.lua", linedefined = 42 },
					caller = { source = "user.lua", line = 5 },
				},
			}
			local out = format.render_trace(history, "<leader>x", "n")
			assert.is_truthy(out:match("<lua callback @ @plugins/telescope%.lua:42>"))
		end)

		it("renders a direct rhs event with its source: line", function()
			local history = {
				{
					timestamp = 100,
					rhs = ":Files<CR>",
					caller = { source = "@config/keymaps.lua", line = 12 },
				},
			}
			local out = format.render_trace(history, "<leader>ff", "n")
			assert.is_truthy(out:match("bound to:  :Files<CR>"))
			assert.is_truthy(out:match("source:%s+@config/keymaps%.lua:12"))
		end)

		it("appends desc line only when opts.desc is present", function()
			local history = {
				{ timestamp = 100, rhs = "a", opts = { desc = "Find files" }, caller = { source = "x", line = 1 } },
				{ timestamp = 90, rhs = "b", opts = {}, caller = { source = "y", line = 2 } },
			}
			local out = format.render_trace(history, "<leader>x", "n")
			assert.equals(1, select(2, out:gsub("desc:", "")))
		end)

		it("appends buffer-local scope line only when buffer_local=true", function()
			local history = {
				{ timestamp = 100, rhs = "a", buffer_local = true, caller = { source = "x", line = 1 } },
				{ timestamp = 90, rhs = "b", buffer_local = false, caller = { source = "y", line = 2 } },
			}
			local out = format.render_trace(history, "<leader>x", "n")
			assert.equals(1, select(2, out:gsub("scope:%s+buffer%-local", "")))
		end)

		it("rejects a non-table history at the boundary", function()
			assert.has_error(function()
				format.render_trace("nope", "x", "n")
			end)
		end)

		it("rejects empty lhs or mode at the boundary", function()
			assert.has_error(function()
				format.render_trace({}, "", "n")
			end)
			assert.has_error(function()
				format.render_trace({}, "x", "")
			end)
		end)
	end)
end)
