# logseq.nvim

Logseq **file-graph** notes directly from Neovim. v0.1 MVP: find/open pages,
follow `[[links]]` under the cursor, open today's journal, create new pages —
with Logseq's dangling-ref semantics (a missing page opens as an empty buffer;
no file is created until you add content and `:w`).

Scope: file graphs (`pages/*.md`, `journals/*.md`) only. Logseq DB graphs
(`*.sqlite`), block refs, and queries are out of scope. TODO lists are
read-only except single-line state cycling (`:LogseqCycleTodo`, one
line at a time — no multi-line cycling, no timestamps/LOGBOOK).

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
| `:LogseqGraph [title]` | Explore a page's links (Linked + Backlinks) in a scratch buffer |
| `:LogseqTodos`       | Pick a `- TODO` task via Telescope and jump to its line   |
| `:LogseqTodosView`   | See all tasks grouped by file (`<CR>` jumps, `q` closes)  |
| `:LogseqCycleTodo`   | Cycle the `- MARKER` on the cursor line to its next state |
| `:LogseqSmartAction` | Follow link, else cycle task, else `<CR>` motion          |
| `:LogseqNextLink`    | Jump to the next `[[link]]`/`#tag` after the cursor       |
| `:LogseqPrevLink`    | Jump to the previous `[[link]]`/`#tag` before the cursor  |

`<Plug>(LogseqFollow)`, `<Plug>(LogseqCycleTodo)`,
`<Plug>(LogseqSmartAction)`, `<Plug>(LogseqNextLink)`, and
`<Plug>(LogseqPrevLink)` are provided — nothing else is bound globally.
Markdown buffers inside a graph additionally get buffer-local `<CR>`
(smart action) and `[o` / `]o` (link navigation); existing maps are
never clobbered (each key is guarded independently, remove with
`:nunmap <buffer> <CR>`). Graph buffers also get `[[ ]]` completion:
an auto-popup while typing plus manual `<C-x><C-o>` (see Completion).
Suggested opt-in binds:
| `:LogseqGraphAll` | Overview of the whole graph (counts + picker to any page's local view) |

```lua
vim.keymap.set('n', 'gf', '<Plug>(LogseqFollow)')
-- GUI/kitty only: most terminals send Ctrl+Enter as plain Enter.
vim.keymap.set('n', '<C-CR>', '<Plug>(LogseqCycleTodo)')
```

Lua API mirrors the commands: `require('logseq').find_files()`,
`.follow_link()`, `.today()`, `.new_page(title)`, `.switch_graph()`,
`.graph_view(opts)` (`{title=, depth=1|2, root=}`), `.todos()`,
`.todos_view()` (`{root=}`), `.cycle_todo()`, `.smart_action(opts)`
(`{root=}`), `.nav_link('next' | 'prev')`.

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
  completion_auto = true,      -- auto-popup [[ ]] completion while typing
  completion_limit = 50,       -- max popup items
  todo_cycles = {              -- :LogseqCycleTodo marker rotation
    { 'TODO', 'DOING', 'DONE' },
    { 'LATER', 'NOW', 'DONE' },
    { 'IN-PROGRESS', 'DONE' },
    { 'WAIT', 'TODO' },
    { 'WAITING', 'TODO' },
    { 'CANCELLED', 'TODO' },
    { 'CANCELED', 'TODO' },
  },
}
```

The explorer centers on the given title, the current `pages/*` /
`journals/*` buffer, or a prompt. `●` = the target file exists,
`○` = dangling (opens lazily, nothing written until content + `:w`).
Buffer keys: `<CR>` / `gf` open the entry, `q` closes, `r` refreshes,
`1` / `2` set depth, `T` toggles dangling entries.

`:LogseqTodos` lists every `- TODO` / `- DOING` / `NOW` / `LATER` / …
block (uppercase markers only, `-`/`*` bullets) with `DONE` /
`CANCELLED` last; choosing jumps to the task's line. `:LogseqTodosView`
shows the same list grouped by file in a read-only scratch buffer
(`<CR>` jumps, `q` closes, re-running reuses the buffer). Both are
jump-only v1. `:LogseqCycleTodo` rotates the `- MARKER` on the cursor
line through `todo_cycles` (default `TODO → DOING → DONE`, wrapping
`DONE → TODO`; first chain wins, so `LATER → NOW → DONE` rejoins the
main chain at `DONE`). A marker in no chain warns and leaves the line
alone. It works in any modifiable buffer, edits in a single undo step,
and keeps the cursor. Custom chains replace the defaults wholesale
(same precedence as everything else: defaults < `vim.g.logseq` <
`setup(opts)`):

```lua
vim.g.logseq = { todo_cycles = { { 'TODO', 'DONE' } } } -- skip DOING
```

Malformed chains (empty, non-string entries) are skipped at cycle time
and reported by `:checkhealth logseq`, never hard errors.

`:LogseqSmartAction` (buffer-local `<CR>` in graph files) picks by line:
a `[[link]]` / `#[[link]]` / `#tag` under the cursor is followed
(link-first, so a link inside a `- TODO` line follows the link and tags
open their page directly), else a `- MARKER` task line is cycled, else
the cursor moves down one line (plain `<CR>` motion, silent at the last
line). `:LogseqNextLink` / `:LogseqPrevLink` (buffer-local `]o` / `[o`)
jump to the start of the next/previous link on or after/before the
cursor — strict, so a cursor sitting on a link moves on; silent no-ops
at the ends with no wrap-around. Unlike obsidian.nvim there is no
heading/fold handling (`za`) and no tag picker. To rebind, remove the
buffer-local key first (`:nunmap <buffer> <CR>` — a pre-existing map is
never clobbered by the ftplugin) and map the `<Plug>` targets yourself.

Unknown keys are not errors; `:checkhealth logseq` reports them.

## Completion

Inside a graph, typing `[[`, `#[[`, or `#tag` pops Logseq-desktop-like
page completion: existing pages/journals first (`● page` /
`● journal`), dangling refs after (`○ new` — accepting one only
inserts the title; no file is created). Ranking is prefix, then
substring, then fuzzy, alphabetical within each tier; an empty `[[`
offers everything (up to `completion_limit`). Manual completion always
works with `<C-x><C-o>`; set `completion_auto = false` to keep only
the manual trigger. The menu takes over `omnifunc` unless you set your
own (only a stock `htmlcomplete` value is replaced). The ftplugin also
appends `noselect,noinsert` to buffer-local `completeopt` in graph
buffers — without them Neovim writes the top match into your text the
moment the menu opens, which made typing inside `[[ ]]` impossible;
your other flags and the global value are untouched (countermand with
your own `FileType` autocmd running
`:setlocal completeopt-=noselect,completeopt-=noinsert` if you disagree).
For non-graph buffers the recommended popup behavior is:

```lua
vim.opt.completeopt = 'menuone,noselect,noinsert'
```

Dangling titles are cached per graph and invalidated automatically on
any `*.md` write or directory change. Graphs over `graph_max_files`
complete pages only, with one warning. Accepting a completion replaces
the prefix only and never appends `]]`, so a trailing `]]` cannot
double up; v1 never auto-inserts `]]`, expands snippets, or sorts by
recency.

nvim-cmp and blink.cmp are opt-in wrappers over the same core
(`lua/logseq/cmp.lua`, `lua/logseq/blink.lua`) — never
auto-registered; both auto-trigger on `[` and `#`:

```lua
-- nvim-cmp (after cmp loads):
require('cmp').register_source('logseq', require('logseq.cmp').new())
-- blink.cmp: expose the module as a custom source provider named
-- `logseq` (see blink.cmp `sources.providers` docs):
logseq = { module = 'logseq.blink' },
```

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
(`b:logseq_root`, hard tabs kept literal for Logseq-style block nesting,
`<CR>` / `[o` / `]o` for the smart action and link navigation).

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
