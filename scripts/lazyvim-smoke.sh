#!/usr/bin/env bash
# LazyVim smoke for the v0.1.0 ship criterion of keymap-forensics.nvim.
#
# Bootstraps a fully isolated LazyVim install (git clone starter +
# `Lazy! sync`) into a tempdir under $TMPDIR, then runs
# scripts/lazyvim-smoke.lua against it to verify :WhyKey correctly
# attributes stock LazyVim's `<leader>ff` binding.
#
# Isolation: every XDG dir is redirected under the tempdir so the
# user's real ~/.config/nvim and ~/.local/share/nvim are never touched.
# Re-runs reuse the tempdir if $KF_SMOKE_TMPDIR is exported; otherwise
# a fresh mktemp is used and the bootstrap runs from scratch (~30s).
#
# Usage:
#   scripts/lazyvim-smoke.sh
#   KF_SMOKE_TMPDIR=/tmp/kf-lazyvim.persist scripts/lazyvim-smoke.sh  # reuse
#
# Exit code: 0 on all checks passing, non-zero otherwise.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="${KF_SMOKE_TMPDIR:-$(mktemp -d "${TMPDIR:-/tmp}/kf-lazyvim-smoke.XXXXXX")}"

if [ ! -d "$tmpdir/config/nvim" ]; then
	echo ">>> Bootstrapping LazyVim starter in $tmpdir"
	mkdir -p "$tmpdir/config" "$tmpdir/data" "$tmpdir/state" "$tmpdir/cache"
	git clone --depth=1 https://github.com/LazyVim/starter "$tmpdir/config/nvim"

	echo ">>> Running Lazy! sync (headless, installs all plugins)"
	XDG_CONFIG_HOME="$tmpdir/config" \
		XDG_DATA_HOME="$tmpdir/data" \
		XDG_STATE_HOME="$tmpdir/state" \
		XDG_CACHE_HOME="$tmpdir/cache" \
		nvim --headless "+Lazy! sync" +qa
else
	echo ">>> Reusing existing LazyVim install at $tmpdir"
fi

echo ">>> Running :WhyKey <leader>ff smoke against LazyVim"
# -c "lua dofile(...)" runs AFTER lazy.nvim's VimEnter-driven plugin
# key-stub registration; -l runs pre-VimEnter and finds no mapping.
KEYMAP_FORENSICS_DIR="$repo_root" \
	XDG_CONFIG_HOME="$tmpdir/config" \
	XDG_DATA_HOME="$tmpdir/data" \
	XDG_STATE_HOME="$tmpdir/state" \
	XDG_CACHE_HOME="$tmpdir/cache" \
	nvim --headless -c "lua dofile('$repo_root/scripts/lazyvim-smoke.lua')"
