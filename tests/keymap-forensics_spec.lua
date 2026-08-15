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
end)
