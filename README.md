# keymap-forensics.nvim

Runtime diagnosis for `:map` chaos. `:WhyKey <lhs>` answers "who bound
this key?" — including which script and line, and (for `<Plug>` chains)
what the mapping actually does under the hood.

Complements [`plug-audit`](https://github.com/jedi-knights/plug-audit):
plug-audit checks plugin repos statically; keymap-forensics checks the
running editor dynamically.

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

## License

MIT. See [LICENSE](./LICENSE).
