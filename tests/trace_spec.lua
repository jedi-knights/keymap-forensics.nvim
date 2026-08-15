describe("keymap-forensics.trace", function()
	local trace

	before_each(function()
		-- Fresh module each test so log + install state start empty.
		package.loaded["keymap-forensics.trace"] = nil
		trace = require("keymap-forensics.trace")
	end)

	describe("record + history", function()
		it("returns empty for a fresh log", function()
			assert.equals(0, trace.count())
			assert.equals(0, #trace.history("<leader>ff", "n"))
		end)

		it("stores appended events and yields history most-recent first", function()
			trace.record({ timestamp = 1, mode = "n", lhs = "<leader>ff", rhs = "a" })
			trace.record({ timestamp = 2, mode = "n", lhs = "<leader>ff", rhs = "b" })
			trace.record({ timestamp = 3, mode = "n", lhs = "<leader>ff", rhs = "c" })

			local h = trace.history("<leader>ff", "n")
			assert.equals(3, #h)
			assert.equals("c", h[1].rhs)
			assert.equals("b", h[2].rhs)
			assert.equals("a", h[3].rhs)
		end)

		it("filters history by lhs AND mode", function()
			trace.record({ timestamp = 1, mode = "n", lhs = "x", rhs = "n-x" })
			trace.record({ timestamp = 2, mode = "i", lhs = "x", rhs = "i-x" })
			trace.record({ timestamp = 3, mode = "n", lhs = "y", rhs = "n-y" })

			local n_x = trace.history("x", "n")
			assert.equals(1, #n_x)
			assert.equals("n-x", n_x[1].rhs)

			local i_x = trace.history("x", "i")
			assert.equals(1, #i_x)
			assert.equals("i-x", i_x[1].rhs)
		end)

		it("counts events across all keys and modes", function()
			trace.record({ mode = "n", lhs = "a" })
			trace.record({ mode = "i", lhs = "b" })
			assert.equals(2, trace.count())
		end)

		it("reset clears the log", function()
			trace.record({ mode = "n", lhs = "a" })
			trace.reset()
			assert.equals(0, trace.count())
		end)

		it("returns a defensive copy from all()", function()
			trace.record({ mode = "n", lhs = "a" })
			local snapshot = trace.all()
			table.insert(snapshot, { mode = "n", lhs = "b" })
			-- Internal log unaffected.
			assert.equals(1, trace.count())
		end)

		it("rejects a non-table event at the boundary", function()
			assert.has_error(function()
				trace.record("not a table")
			end)
		end)

		it("rejects empty lhs or mode at the history boundary", function()
			assert.has_error(function()
				trace.history("", "n")
			end)
			assert.has_error(function()
				trace.history("x", "")
			end)
		end)
	end)

	describe("install / uninstall", function()
		-- A fake api table that records each call and returns a sentinel so
		-- tests can verify the wrapper forwards args AND propagates return.
		local function fake_api()
			local calls = {}
			return {
				calls = calls,
				nvim_set_keymap = function(mode, lhs, rhs, opts)
					table.insert(calls, { fn = "set", mode = mode, lhs = lhs, rhs = rhs, opts = opts })
					return "orig-set"
				end,
				nvim_buf_set_keymap = function(buffer, mode, lhs, rhs, opts)
					table.insert(
						calls,
						{ fn = "buf_set", buffer = buffer, mode = mode, lhs = lhs, rhs = rhs, opts = opts }
					)
					return "orig-buf-set"
				end,
			}
		end

		it("returns false from installed() before install", function()
			assert.is_false(trace.installed())
		end)

		it("wraps nvim_set_keymap and forwards args + return value", function()
			local api = fake_api()
			trace.install({
				api = api,
				now = function()
					return 100
				end,
			})
			local ret = api.nvim_set_keymap("n", "<leader>x", ":echo 1<CR>", { silent = true })
			assert.equals("orig-set", ret)
			assert.equals(1, #api.calls)
			local c = api.calls[1]
			assert.equals("n", c.mode)
			assert.equals("<leader>x", c.lhs)
			assert.equals(":echo 1<CR>", c.rhs)
			assert.equals(true, c.opts.silent)
		end)

		it("records an event when the wrapper is invoked", function()
			local api = fake_api()
			trace.install({
				api = api,
				now = function()
					return 42
				end,
			})
			api.nvim_set_keymap("n", "<leader>x", ":echo 1<CR>", { desc = "test" })
			assert.equals(1, trace.count())
			local h = trace.history("<leader>x", "n")
			assert.equals(1, #h)
			assert.equals(42, h[1].timestamp)
			assert.equals(":echo 1<CR>", h[1].rhs)
			assert.equals("test", h[1].opts.desc)
			assert.is_false(h[1].buffer_local)
		end)

		it("wraps nvim_buf_set_keymap and marks buffer_local=true", function()
			local api = fake_api()
			trace.install({
				api = api,
				now = function()
					return 5
				end,
			})
			local ret = api.nvim_buf_set_keymap(3, "n", "<leader>y", "z", {})
			assert.equals("orig-buf-set", ret)
			local h = trace.history("<leader>y", "n")
			assert.equals(1, #h)
			assert.is_true(h[1].buffer_local)
		end)

		it("captures callback source via debug.getinfo when rhs is a function", function()
			local api = fake_api()
			trace.install({
				api = api,
				now = function()
					return 0
				end,
			})
			local cb = function()
				return "hello"
			end
			api.nvim_set_keymap("n", "<leader>x", cb, {})
			local h = trace.history("<leader>x", "n")
			assert.is_true(h[1].has_callback)
			assert.is_nil(h[1].rhs)
			assert.is_not_nil(h[1].callback_source)
			assert.is_string(h[1].callback_source.source)
		end)

		it("recognises the vim.keymap.set-style callback (rhs='' + opts.callback)", function()
			-- vim.keymap.set hoists a callable rhs into opts.callback and passes
			-- an empty string as the API-level rhs. The shim must treat this
			-- the same as a direct-function rhs.
			local api = fake_api()
			trace.install({
				api = api,
				now = function()
					return 0
				end,
			})
			local cb = function()
				return "cb"
			end
			api.nvim_set_keymap("n", "<leader>x", "", { callback = cb })
			local h = trace.history("<leader>x", "n")
			assert.is_true(h[1].has_callback)
			assert.is_nil(h[1].rhs) -- empty-string rhs normalises to nil
			assert.is_not_nil(h[1].callback_source)
		end)

		it("is idempotent — second install is a no-op", function()
			local api = fake_api()
			local original_set = api.nvim_set_keymap
			trace.install({ api = api })
			local wrapped_once = api.nvim_set_keymap
			trace.install({ api = api })
			-- The second install must NOT re-wrap over our own wrapper.
			assert.equals(wrapped_once, api.nvim_set_keymap)
			-- And the original is still what we captured.
			assert.not_equals(original_set, api.nvim_set_keymap)
		end)

		it("returns true from installed() after install", function()
			trace.install({ api = fake_api() })
			assert.is_true(trace.installed())
		end)

		it("uninstall restores originals", function()
			local api = fake_api()
			local original_set = api.nvim_set_keymap
			local original_buf_set = api.nvim_buf_set_keymap
			trace.install({ api = api })
			trace.uninstall()
			assert.equals(original_set, api.nvim_set_keymap)
			assert.equals(original_buf_set, api.nvim_buf_set_keymap)
			assert.is_false(trace.installed())
		end)

		it("uninstall preserves the trace log so :WhyKeyTrace still works", function()
			local api = fake_api()
			trace.install({
				api = api,
				now = function()
					return 1
				end,
			})
			api.nvim_set_keymap("n", "<leader>x", "a", {})
			trace.uninstall()
			assert.equals(1, trace.count())
			assert.equals(1, #trace.history("<leader>x", "n"))
		end)

		it("uninstall is idempotent — second uninstall is a no-op", function()
			trace.uninstall() -- never installed
			assert.is_false(trace.installed())
			local api = fake_api()
			trace.install({ api = api })
			trace.uninstall()
			trace.uninstall() -- extra call
			assert.is_false(trace.installed())
		end)

		it("caps the log at max_events via FIFO eviction", function()
			local api = fake_api()
			trace.install({
				api = api,
				max_events = 3,
				now = function()
					return 0
				end,
			})
			for i = 1, 5 do
				api.nvim_set_keymap("n", "k" .. i, "rhs", {})
			end
			assert.equals(3, trace.count())
			-- Oldest two ("k1", "k2") were evicted; the most-recent three remain.
			local all_lhs = {}
			for _, ev in ipairs(trace.all()) do
				table.insert(all_lhs, ev.lhs)
			end
			assert.same({ "k3", "k4", "k5" }, all_lhs)
		end)
	end)
end)
