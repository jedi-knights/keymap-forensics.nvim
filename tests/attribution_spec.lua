describe("keymap-forensics.attribution", function()
	local attribution

	before_each(function()
		package.loaded["keymap-forensics.attribution"] = nil
		attribution = require("keymap-forensics.attribution")
	end)

	-- Build a deps table with a scripted maparg that returns `answers`
	-- keyed by `lhs`, plus a scripted script-name resolver.
	local function fake_deps(answers, sid_to_name)
		return {
			maparg = function(lhs, _mode, _abbr, _dict)
				return answers[lhs] or {}
			end,
			resolve_script_name = function(sid)
				return sid_to_name and sid_to_name[sid] or nil
			end,
		}
	end

	it("returns nil when the lhs has no mapping", function()
		local deps = fake_deps({})
		assert.is_nil(attribution.attribute("<leader>ff", "n", deps))
	end)

	it("returns nil when maparg returns a non-table", function()
		local deps = fake_deps({})
		deps.maparg = function()
			return ""
		end
		assert.is_nil(attribution.attribute("<leader>ff", "n", deps))
	end)

	it("shapes a maparg dict into a record with source resolution", function()
		local deps = fake_deps({
			["<leader>ff"] = {
				lhs = "<leader>ff",
				mode = "n",
				rhs = "<cmd>Telescope find_files<CR>",
				sid = 42,
				lnum = 100,
				silent = 1,
				noremap = 1,
				expr = 0,
				buffer = 0,
				desc = "Find files",
			},
		}, { [42] = "lua/plugins/telescope.lua" })

		local r = attribution.attribute("<leader>ff", "n", deps)

		assert.equals("<leader>ff", r.lhs)
		assert.equals("n", r.mode)
		assert.equals("<cmd>Telescope find_files<CR>", r.rhs)
		assert.is_true(r.silent)
		assert.is_true(r.noremap)
		assert.is_false(r.expr)
		assert.is_false(r.buffer_local)
		assert.equals("Find files", r.desc)
		assert.equals(42, r.source.sid)
		assert.equals(100, r.source.line)
		assert.equals("lua/plugins/telescope.lua", r.source.name)
	end)

	it("flags callback-backed mappings and leaves rhs nil", function()
		local deps = fake_deps({
			["<leader>x"] = {
				lhs = "<leader>x",
				mode = "n",
				rhs = nil,
				callback = function() end,
				sid = 5,
				lnum = 12,
			},
		})

		local r = attribution.attribute("<leader>x", "n", deps)

		assert.is_true(r.callback)
		assert.is_nil(r.rhs)
	end)

	it("chases <Plug> targets one hop", function()
		local deps = fake_deps({
			["<leader>ff"] = {
				lhs = "<leader>ff",
				mode = "n",
				rhs = "<Plug>(TelescopeFindFiles)",
				sid = 7,
				lnum = 3,
			},
			["<Plug>(TelescopeFindFiles)"] = {
				lhs = "<Plug>(TelescopeFindFiles)",
				mode = "n",
				rhs = "<cmd>Telescope find_files<CR>",
				sid = 20,
				lnum = 88,
			},
		})

		local r = attribution.attribute("<leader>ff", "n", deps)

		assert.equals("<Plug>(TelescopeFindFiles)", r.plug_hop)
		assert.equals("<cmd>Telescope find_files<CR>", r.plug_target)
	end)

	it("leaves plug_target nil when the <Plug> RHS has no nested mapping", function()
		local deps = fake_deps({
			["<leader>ff"] = { lhs = "<leader>ff", mode = "n", rhs = "<Plug>(Dangling)", sid = 3, lnum = 1 },
		})

		local r = attribution.attribute("<leader>ff", "n", deps)

		assert.equals("<Plug>(Dangling)", r.plug_hop)
		assert.is_nil(r.plug_target)
	end)

	it("omits source when sid is zero (built-in or command-line)", function()
		local deps = fake_deps({
			["<leader>ff"] = { lhs = "<leader>ff", mode = "n", rhs = ":echo 1<CR>", sid = 0, lnum = 0 },
		})

		local r = attribution.attribute("<leader>ff", "n", deps)

		assert.is_nil(r.source)
	end)

	it("rejects an empty lhs at the boundary", function()
		assert.has_error(function()
			attribution.attribute("", "n", fake_deps({}))
		end)
	end)

	it("rejects an empty mode at the boundary", function()
		assert.has_error(function()
			attribution.attribute("<leader>ff", "", fake_deps({}))
		end)
	end)
end)
