# keymap-forensics.nvim

[![CI](https://github.com/jedi-knights/keymap-forensics.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/jedi-knights/keymap-forensics.nvim/actions/workflows/ci.yml)

You pressed `<leader>ff` expecting Telescope. You got something you don't
recognize. Which of your 40 plugins bound this key — and what did the
previous binding do?

`keymap-forensics.nvim` answers those questions from a running Neovim.
`:WhyKey <lhs>` names the script and line that bound a key (chasing one
`<Plug>` hop to reveal what it actually does). `:WhyKeyConflicts` scans
every mode for shadowing-prefix collisions — the mappings whose lhs
blocks longer sequences and forces a `timeoutlen` wait. `:WhyKeyTrace`
opts in to a Lua-side shim that records every mapping-set event so you
can inspect the *full history* of who bound what, in what order.

**Requirements:** Neovim 0.10+. Source-path resolution uses `getscriptinfo()`; older Neovim still runs `:WhyKey`, it just degrades to a script id instead of a filename.

**Status:** pre-v0.1.0. Public API is expected to stabilize with the v0.1.0 tag; treat as experimental until then.

## Relationship to plug-audit

Sibling tool: [`plug-audit`](https://github.com/jedi-knights/plug-audit)
lints plugin *repositories* at rest (augroup hygiene, optional-peer
handling, health-check presence, keymap conventions, etc.).
`keymap-forensics` inspects the *running editor* — the state that
emerges after every plugin has loaded and every mapping has actually
been set. Same mental model, different time.

## Install

```lua
-- lazy.nvim
{ "jedi-knights/keymap-forensics.nvim" }
```

No `setup()` call required — the `:WhyKey` command is registered by
`plugin/keymap-forensics.lua` on startup.

## Usage

### `:WhyKey [<mode>] <lhs>`

Diagnose one key.

```
:WhyKey <lhs>              " default: normal mode
:WhyKey <mode> <lhs>       " explicit mode: n | i | v | x | o | c | t
```

Example output:

```
:WhyKey <leader>ff
<leader>ff (n mode)
  bound to: <Plug>(TelescopeFindFiles) → <cmd>Telescope find_files<CR>
  source:   lua/plugins/telescope.lua:42
  desc:     Find files
```

If the key has no mapping in the requested mode, `:WhyKey` prints
`no mapping`.

### `:WhyKeyConflicts`

Report every keymap prefix collision across standard modes. A "conflict"
is a mapping whose lhs is a strict prefix of another mapping in the
same mode — pressing the prefix triggers it immediately (or after
`timeoutlen`), blocking the longer sequences. Namespace-style prefixes
that are themselves unbound (Vim's `g` group, for example) are excluded.

Example output:

```
:WhyKeyConflicts
Prefix conflicts (n mode):
  <leader>f  blocks 2 longer sequence(s):
    <leader>f    :Files<CR>              (lua/config/keymaps.lua:12)
    <leader>ff   :Telescope find_files   (lua/plugins/telescope.lua:42)
    <leader>fg   :Telescope live_grep    (lua/plugins/telescope.lua:43)

Prefix conflicts (i mode):
  none

...

Scanned 187 mappings across 7 modes.
```

### `:WhyKeyTrace [<mode>] <lhs>` *(opt-in)*

Historical binding tracker. Answers "who bound this key first, and who
overrode them?" — the question `:WhyKey` cannot answer because the
loser is gone by the time you look.

Add `require("keymap-forensics").track()` to your init.lua **before**
any plugin whose keymaps you want to observe. The shim wraps
`vim.api.nvim_set_keymap` and `vim.api.nvim_buf_set_keymap` and records
every call. Mappings set before `track()` runs are not captured;
Vimscript `:map` calls are not observed either (they take C paths this
plugin cannot see).

```lua
-- init.lua, as early as possible:
require("keymap-forensics").track()
-- ...then load lazy.nvim / packer / plugins as usual
```

Example output:

```
:WhyKeyTrace <leader>ff
<leader>ff (n mode) — 3 event(s) recorded

  #1  winner      09:00:12
      bound to:  <cmd>Telescope find_files<CR>
      source:    lua/plugins/telescope.lua:42
      desc:      Find files

  #2  superseded  09:00:05
      bound to:  :Files<CR>
      source:    lua/config/keymaps.lua:12

  #3  superseded  09:00:01
      bound to:  <cmd>fzf-lua files<CR>
      source:    lua/plugins/fzf.lua:8
```

Commands:

```
:WhyKeyTrace [<mode>] <lhs>    " print binding history for a key
:WhyKeyTraceReset              " clear the trace log
```

Lua API:

```lua
require("keymap-forensics").track({ max_events = 50000 })  -- install shim
require("keymap-forensics").untrack()                       -- restore vim.api; log preserved
require("keymap-forensics").reset_trace()                   -- clear log
```

Default event cap is 50 000 (FIFO eviction past that). Pass
`max_events = 0` to disable the cap.

## What it shows

For any bound key:

- The RHS (or `<lua callback>` for callback-backed mappings)
- One-hop `<Plug>` resolution — the mapping under the `<Plug>`
- The source script filename and line number (Neovim 0.10+; older
  versions degrade to a script id)
- The mapping's `desc`, if set
- `scope: buffer-local` when the mapping is buffer-local

Run `:checkhealth keymap-forensics` to verify your Neovim supports
source-path resolution.

## Development

```sh
make lint            # stylua --check .
make test            # plenary-busted headless
make lazyvim-smoke   # bootstrap isolated LazyVim + :WhyKey <leader>ff
```

`make lazyvim-smoke` fulfills the v0.1.0 ship criterion: it clones
LazyVim starter into a redirected-XDG tempdir, runs `Lazy! sync` to
install all default plugins, then runs `:WhyKey <leader>ff` against
the stock keymap and asserts the attribution record is well-shaped.
Takes ~30s cold; set `KF_SMOKE_TMPDIR` to reuse a persistent bootstrap.

## License

MIT. See [LICENSE](./LICENSE).
