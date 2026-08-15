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
end)
