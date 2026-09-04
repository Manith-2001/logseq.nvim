# logseq.nvim

Logseq **file-graph** notes directly from Neovim. v0.1 MVP: find/open pages,
follow `[[links]]` under the cursor, open today's journal, create new pages —
with Logseq's dangling-ref semantics (a missing page opens as an empty buffer;
no file is created until you add content and `:w`).

Scope: file graphs (`pages/*.md`, `journals/*.md`) only. Logseq DB graphs
(`*.sqlite`), block refs, queries, and task management are out of scope.

## Requirements

- Neovim 0.12+
- Optional: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
  (otherwise a `vim.ui.select` fallback is used)
- A Logseq file graph, e.g. `~/dev/notes_logseq/`

## Install

With Neovim's built-in `vim.pack` (no plugin manager needed):

```lua
vim.pack.add({ { src = 'https://github.com/Manith-2001/logseq.nvim' } })

-- Where your graph lives (or skip it and open a file inside the graph;
-- the root is auto-detected by walking up to logseq/config.edn or
-- pages/+journals/):
vim.g.logseq = { graph_path = '~/dev/notes_logseq' }
```

No `setup()` call required. `require('logseq').setup(opts)` exists only to
merge options from Lua. Precedence: defaults < `vim.g.logseq` < `setup(opts)`.

Then `:helptags ALL` (once, so `:help logseq` works) and `:checkhealth logseq`.

## Usage

| Command              | What it does                                              |
| -------------------- | --------------------------------------------------------- |
| `:LogseqFind`        | Pick a page/journal via Telescope and open it             |
| `:LogseqFollow`      | Open the `[[link]]`, `#[[link]]`, or `#tag` under cursor  |
| `:LogseqToday`       | Open today's journal (`journals/YYYY_MM_DD.md`)           |
| `:LogseqNew [title]` | Open a page; prompts for the title when omitted           |

Only `<Plug>(LogseqFollow)` is provided — no keys are bound by default.
Suggested opt-in bind:

```lua
vim.keymap.set('n', 'gf', '<Plug>(LogseqFollow)')
```

Lua API mirrors the commands: `require('logseq').find_files()`,
`.follow_link()`, `.today()`, `.new_page(title)`.

## Configuration

```lua
{
  graph_path = nil,            -- absolute path (nil = auto-detect)
  pages_dir = 'pages',
  journals_dir = 'journals',
  journal_format = '%Y_%m_%d', -- os.date format for journal filenames
  picker = 'telescope',        -- vim.ui.select fallback is automatic
}
```

Unknown keys are not errors; `:checkhealth logseq` reports them.

Markdown buffers inside a graph get buffer-local treatment only
(`b:logseq_root`, hard tabs kept literal for Logseq-style block nesting).

## Semantics

- Titles map to filenames verbatim: `Machine Learning` ↔
  `pages/Machine Learning.md`. No `___`/legacy translation is applied: the
  reference graph sets no `:file-name-format` and contains no namespace
  pages, so inventing one would diverge from Logseq. Titles containing `/`
  are refused with a warning (namespaces are out of scope for v0.1).
- Lazy opens never create files. `:w` on a still-empty dangling page is
  refused with a warning; the file appears only after content + `:w`.

## Developing / repro steps

```bash
make test   # plenary-busted suite, headless (exit 0 = pass)
make lint   # stylua --check .
```

Isolated repro with no user config (uses the fixture graph):

```bash
nvim --clean -u tests/minimal_init.lua
```

then inside it `:checkhealth logseq`, `:LogseqToday` (opens the fixture's
journal for today as a dangling buffer — nothing is written), `:LogseqNew Demo`.

Layout: `plugin/logseq.lua` (commands only), `lua/logseq/` (facade + modules),
`after/ftplugin/markdown.lua` (graph-scoped buffer opts), `doc/logseq.txt`
(vimdoc), `tests/` (specs + fixture graph). See `PLAN.md` for milestones.
