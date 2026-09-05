# logseq.nvim

Logseq **file-graph** notes directly from Neovim. v0.1 MVP: find/open pages,
follow `[[links]]` under the cursor, open today's journal, create new pages —
with Logseq's dangling-ref semantics (a missing page opens as an empty buffer;
no file is created until you add content and `:w`).

Scope: file graphs (`pages/*.md`, `journals/*.md`) only. Logseq DB graphs
(`*.sqlite`), block refs, queries, and task management are out of scope.

Several file graphs are supported: point `graphs_dirs` at parent
directories and switch between the discovered graphs with
`:LogseqGraphs`. Opt-in — single-graph setups behave exactly as before.

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
| `:LogseqGraphs`      | Pick the active graph (multi-graph switching, see below)  |
| `:LogseqGraph [title]` | Explore a page's links (Outgoing + Incoming tree, block context) in a scratch buffer |
| `:LogseqGraphAll` | Overview of the whole graph (counts; `<CR>` drills into a page's local view) |

Only `<Plug>(LogseqFollow)` is provided — no keys are bound by default.
Suggested opt-in bind:

```lua
vim.keymap.set('n', 'gf', '<Plug>(LogseqFollow)')
```

Lua API mirrors the commands: `require('logseq').find_files()`,
`.follow_link()`, `.today()`, `.new_page(title)`, `.switch_graph()`,
`.graph_view(opts)` (`{title=, depth=1|2, root=}`), `.graph_view_all(opts)`
(`{root=}`).

## Configuration

```lua
{
  graph_path = nil,            -- absolute path (nil = auto-detect)
  pages_dir = 'pages',
  journals_dir = 'journals',
  journal_format = '%Y_%m_%d', -- os.date format for journal filenames
  picker = 'telescope',        -- vim.ui.select fallback is automatic
  graphs_dirs = {},            -- parent dirs scanned for graphs (multi-graph)
  graphs_depth = 2,            -- how deep to scan under each dir
  graph_depth = 1,             -- :LogseqGraph explorer depth (1 or 2 hops)
  graph_max_files = 2000,      -- max files indexed synchronously (else warns)
}
```

The explorer centers on the given title, the current `pages/*` /
`journals/*` buffer, or a prompt. `●` = the target file exists,
`○` = dangling (opens lazily, nothing written until content + `:w`).

`:LogseqGraph` renders the center page as a tree — outgoing links,
backlink sources with the exact blocks that link here, and (at depth
2) everything two hops away grouped by the page it hangs off:

```
# Machine Learning · notes_logseq (depth 1)

## Outgoing (2)
├─ ● Deep Learning
└─ ○ Future Topic

## Incoming (1)
└─ ● AI Overview
   ├─ "…uses [[Machine Learning]] for ranking…" → AI Overview:12
   └─ more=4
```

Long blocks are trimmed (~80 cols) and capped at 3 rows per source
(`more=N` covers the rest). Buffer keys: `<CR>` / `gf` open the entry
(a context row jumps to the exact `Source:lnum` line), `q` closes, `r`
refreshes, `1` / `2` set depth, `T` toggles dangling entries.

`:LogseqGraphAll` renders the whole graph instead: a stats header plus
`Pages` / `Journals` / `Dangling` sections with per-entry link counts
(`● A →1 ←1` = one out-link, one backlink; `○` dangling shows
backlinks only), so hubs, orphans, and dangling refs are visible at a
glance. Same keys, except `<CR>` / `gf` drill down into the entry's
local view (where its edges are visible) and `1` / `2` are replaced by
`P`, which picks a page (Telescope, `vim.ui.select` fallback) and
opens its local view.

Unknown keys are not errors; `:checkhealth logseq` reports them.

## Multiple graphs

```lua
vim.g.logseq = {
  graphs_dirs = { '~/dev', '~/notes' }, -- parent dirs scanned for graphs
  graphs_depth = 2,                      -- how deep to scan under each dir
}
```

Graphs are auto-discovered by scanning for `logseq/config.edn` or
`pages/`+`journals/` siblings (hidden dirs skipped, symlinks not followed,
missing dirs scan as empty). `:LogseqGraphs` picks the active graph — the
finder then lists only that graph's pages and journals resolve into it.
The `(auto)` entry clears the override. The choice persists across
restarts in `stdpath('data')/logseq.nvim/active`.

Root resolution order: explicit per-call `opts.root`, then the current
buffer's graph (a buffer inside a graph always wins, even over the
override), then the active graph, then `graph_path` (strict — a
configured-but-missing path resolves to nothing), then the working
directory. `:checkhealth logseq` shows the discovered graphs and which
step resolved the effective graph (`buffer:…` / `active:…` / `graph_path` /
`auto:…`), plus a warning when the stored choice went stale.

Switching never `:cd`s and never touches buffers outside the target graph.

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
