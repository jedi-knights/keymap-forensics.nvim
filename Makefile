.PHONY: test lint format check lazyvim-smoke

# Run the plenary-busted test suite headlessly.
test:
	nvim --headless -u scripts/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'scripts/minimal_init.lua' }"

# Ship-criterion smoke: bootstrap an isolated LazyVim install and
# verify :WhyKey <leader>ff correctly attributes the stock binding.
# Manual gate — ~30s cold, reuses cache when KF_SMOKE_TMPDIR is
# exported. See scripts/lazyvim-smoke.sh for the mechanism.
lazyvim-smoke:
	scripts/lazyvim-smoke.sh

lint:
	@if ! command -v stylua > /dev/null; then \
		echo "install stylua: https://github.com/JohnnyMorganz/StyLua"; \
		exit 1; \
	fi
	stylua --check .

format:
	@if ! command -v stylua > /dev/null; then \
		echo "install stylua: https://github.com/JohnnyMorganz/StyLua"; \
		exit 1; \
	fi
	stylua .

check: lint test
