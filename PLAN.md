# logseq.nvim — Plan (v0.1 MVP + M5 multi-graph)

> Status: v0.1 complete (M0–M4). File-graph find/open + follow [[links]] +
> journals/new-page with dangling-ref semantics; 60 headless specs green.
> Next: M5 done (`make ci` 97/97) — v0.1 MVP + multi-graph switching complete.
> M6 (link index/backlinks, `lua/logseq/index.lua`): in progress on `main` by
> a parallel agent — untouched by this branch.
> M7 (TODO view, dual picker + scratch buffer, jump-only v1): in progress on
> the `feat/todos-view` worktree (`../logseq.nvim-todos`), branched from `main`.
> M8 (configurable single-line TODO-state cycling): done on the
> `feat/todos-view` worktree (M8.1–M8.5 all checked; `make ci` green,
> manual on a scratch md verified, real graphs untouched).
> M9 (smart action + link navigation, obsidian.nvim parity): in progress
> on the `feat/todos-view` worktree (`../logseq.nvim-todos`).
> Goal: handle Logseq **file-graph** notes directly from Neovim.
> MVP scope (locked): **find/open pages + follow `[[links]]`** with Logseq's
> dangling-ref semantics (`[[test]]` creates no `test.md` until content is written).
> Stack (locked): **file graph + Telescope + plenary-busted**, Neovim 0.12, pure Lua/LuaJIT.

## 1. Background / context

- Dev machine: NVIM v0.12.5, LuaJIT, config at `~/.config/nvim/init.lua` using
  native `vim.pack.add` (no lazy.nvim). `telescope.nvim` + `plenary.nvim` already installed.
- Reference graph (file-based): `~/dev/notes_logseq/` with `pages/*.md`,
  `journals/*.md`, `logseq/config.edn`. Example: `pages/Machine Learning.md`.
- Live Logseq DB graphs live in `~/logseq/graphs/` (`*.sqlite`) — **out of scope for v0.1**.
- Observed Logseq markdown dialect (file graph):
  - Blocks are `- <content>` list items, children indented with tabs (sample uses `\t`).
  - Task prefixes: `TODO / DOING / NOW / LATER / DONE` after the `- `.
  - Links: `[[page]]`, `#[[page with spaces]]`, `#tag`.
  - Properties: `key:: value` lines.
  - Empty pages may exist as 1-byte files (e.g. `contents.md`); missing pages have no file at all.

## 2. Non-goals for v0.1

- DB-graph support (`~/logseq/graphs/*.sqlite`).
- Block refs `((uuid))`, block embeds, queries, whiteboards.
- Task state cycling (M8: single-line `:LogseqCycleTodo` only), scheduling, deadlines, priorities.
- Namespace UI, graph view, sync/conflict resolution, encryption.
- Auto-creating empty `.md` files on link-follow (explicitly forbidden by requirement).

## 3. Project scaffold (target tree, not yet created)

```
logseq.nvim/
  PLAN.md                    # this file
  README.md                  # (later) install + usage + repro steps
  plugin/logseq.lua          # ONLY user commands + <Plug> maps, defers require()
  lua/logseq/init.lua        # public facade: find_files(), follow_link(), today(), new_page()
  lua/logseq/config.lua      # defaults + vim.tbl_deep_extend + vim.validate
  lua/logseq/graph.lua       # find_root(), list_pages() via vim.fs / plenary.scandir
  lua/logseq/page.lua        # title<->path, exists(), open_lazy() (no eager write)
  lua/logseq/parser.lua      # pure fns: links_in_line(), link_under_cursor()
  lua/logseq/tasks.lua        # (M7) pure fns: parse_line(), scan() for `- TODO` blocks
  lua/logseq/telescope.lua   # pcall(require,'telescope'), fallback to vim.ui.select
  lua/logseq/health.lua      # :checkhealth logseq
  after/ftplugin/markdown.lua# buffer-local opts ONLY when inside graph
  doc/logseq.txt             # vimdoc + tags
  tests/minimal_init.lua     # rtp += plenary + repo, no user config
  tests/fixtures/graph/      # tiny fake graph for tests
  tests/parser_spec.lua
  tests/page_spec.lua
  tests/graph_spec.lua
  tests/tasks_spec.lua       # (M7) task parser + scanner contract
  Makefile                   # test, lint targets
```

Rationale (Neovim 0.12 best practice):

- `plugin/*.lua` stays tiny and never eagerly `require()`s the plugin body.
  Commands do `require('logseq').cmd(...)` inside the callback → ~0ms startup cost.
- No mandatory `setup()`. Plugin works out of the box; `setup(opts)` only merges
  config (`graph_path`, `journal_format`, `picker`). Documented alternative:
  `vim.g.logseq` table for Vimscript-compatible config.
- Every autocmd lives in one `augroup LogseqNvim` with `clear = true` (idempotent `:source`).
- Expose `<Plug>(LogseqFollow)` etc.; never steal `gf` / `<leader>` keys unconditionally.
- Optional deps (telescope) always via `pcall(require, ...)` + `health.warn` fallback.
- `health.lua` checks: graph path readable, `pages/`+`journals/` exist, nvim version,
  telescope present-or-fallback.

## 4. Dev setup loop (first-time plugin author flow)

1. Scaffold the tree above, `git init` in `~/dev/logseq.nvim`.
2. Load locally in real config (temporary, during dev):
   ```lua
   vim.pack.add({ { src = 'file:///Users/manithvazirani/dev/logseq.nvim' } })
   -- optional during dev:
   -- vim.g.logseq = { graph_path = '~/dev/notes_logseq' }
   ```
   `file://` packs need no reinstall after edits.
3. Iterate: edit file → `:restart` (builtin since 0.11) → `:LogseqFind`.
4. Isolated repro when something breaks (no user config interference):
   ```bash
   nvim --clean -u tests/minimal_init.lua ~/dev/notes_logseq/pages/contents.md
   ```
5. Tooling: `stylua` for formatting, `lua_ls` via existing mason setup for types
   (LuaCATS `---@class` annotations on config). No build step — pure Lua 5.1/LuaJIT API.

## 5. Testing strategy (plenary-busted)

Chosen because `plenary.nvim` is already installed — zero new dependencies.

- **Unit (pure, fast):** `parser.lua`
  - `[[a]]`, `[[a/b]]`, `[[Page With Spaces]]`, `#[[a b]]`, `#tag`,
    multiple links per line, links after `- TODO ` prefixes and tab indents.
  - `link_under_cursor(line, col)` → correct link when several exist on one line.
  - `page.title_to_filename(title)` escaping rules.
- **Integration (real buffers, no mocks):**
  - `open_lazy()` on a missing page asserts `filereadable() == 0` after open,
    file appears only after buffer gets content + `:w`.
  - `graph.list_pages()` on `tests/fixtures/graph/` returns the expected set
    (pages + journals, hidden files excluded).
- **Layout:** `*_spec.lua` files using `describe/it/before_each/after_each`,
  fixtures under `tests/fixtures/graph/` (e.g. `pages/A.md`, `journals/2026_08_27.md`).
- **Runner (`Makefile`):**
  ```make
  test:
  	nvim --headless --noplugin -u tests/minimal_init.lua \
  	  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua', sequential=true}"
  ```
  Exit code 0 = pass, non-zero = fail (CI-friendly).
- **Manual checklist per change:**
  - `:checkhealth logseq` shows OKs.
  - `:LogseqFind` lists `Machine Learning.md` from `~/dev/notes_logseq`.
  - `[[Missing Page]]` → follow → buffer opens, **no file on disk** → `:w` empty warns/refuses,
    adding a line + `:w` creates the file.
  - Reloading config twice does not duplicate autocmds/commands.

## 6. Module design (v0.1)

### `lua/logseq/config.lua`
- Defaults: `{ graph_path = nil (auto-detect), pages_dir='pages', journals_dir='journals',
  journal_format='%Y_%m_%d', picker='telescope' }`.
- `setup(opts)` = merge only, idempotent, callable 0..n times; `get()` accessor.
- `vim.validate` on merged config; unknown keys surface via health warning (not hard error).

### `lua/logseq/graph.lua`
- `find_root(startpath)`: walk up via `vim.fs.find({'logseq/config.edn'},
  {upward=true})` or detect `pages/`+`journals/` siblings; fall back to `config.graph_path`.
- `list_pages(root)`: scan `pages/*.md` + `journals/*.md` (non-recursive v0.1),
  return `{title, path, kind}` items. Use `vim.fs.dir` or `plenary.scandir` (already available).
- Reads `:file-name-format` from `logseq/config.edn` if present (see §8).

### `lua/logseq/page.lua`
- `title_to_path(root, title)`: single canonical place for escaping (spaces preserved,
  case preserved per observed graph; namespace `/` handling deferred — see §8).
- `exists(path)`: `vim.fn.filereadable`.
- `open_lazy(path)`: `edit + fnameescape(path)`, `bo.filetype='markdown'`; **never writes**.
  `new_page()` / `today()` delegate here.

### `lua/logseq/parser.lua` (pure — no `vim.*` calls, maximally tested)
- `links_in_line(line)`: ordered `{text, col_start, col_end, kind}` for
  `[[..]]`, `#[[..]]`, `#tag`.
- `link_under_cursor(line, col)`: which link the cursor sits on (nil-safe).

### `lua/logseq/telescope.lua` + `init.lua` facade
- `find_files()`: build items from `graph`, launch Telescope picker if
  `pcall(require,'telescope')` succeeds, else `vim.ui.select` fallback.
- `follow_link()`: `parser.link_under_cursor` on current line → `page.open_lazy`.
- `today()`: `journals/<os.date(journal_format)>.md` via `open_lazy`.
- `new_page(title)`: prompt if no arg, then `open_lazy`.

### `plugin/logseq.lua`
- Only: `nvim_create_user_command(:LogseqFind/:LogseqFollow/:LogseqToday/:LogseqNew, ...)`
  each deferring `require('logseq')`, plus `<Plug>(LogseqFollow)` map.
  Suggested user bind (in README, not forced): `vim.keymap.set('n','gf','<Plug>(LogseqFollow)')`
  scoped to graph buffers or global at user discretion.

## 7. Milestones (each independently verifiable)

### M0 — Scaffold
- **Scope:** project tree (§3), stub user commands, health check, test harness.
- **Files:**
  - `plugin/logseq.lua` (commands only, deferred `require`)
  - `lua/logseq/init.lua` (stub facade), `lua/logseq/config.lua` (defaults + `setup()`/`get()`), `lua/logseq/health.lua`
  - `tests/minimal_init.lua`, `tests/fixtures/graph/` (tiny fake graph), `tests/parser_spec.lua` (one passing case)
  - `Makefile` (`test` target per §5)
- **Tasks:**
  - [ ] Scaffold tree, `git init`
  - [ ] Stub `:LogseqFind` / `:LogseqFollow` / `:LogseqToday` / `:LogseqNew` + `<Plug>(LogseqFollow)`
  - [ ] `health.lua`: graph path, `pages/`+`journals/`, nvim version, telescope present-or-fallback
  - [ ] `minimal_init.lua` + fixture graph + single green `parser_spec`
  - [ ] `Makefile` test runner wired
- **Verify:** `make test` green headless; `:checkhealth logseq` listed with OKs.

### M1 — Graph + Find
- **Scope:** graph root detection, page listing, finder picker (§6: `graph.lua`, `page.lua`, `telescope.lua`).
- **Files:** `lua/logseq/graph.lua` (`find_root()`, `list_pages()`), `lua/logseq/page.lua` (`title_to_path()`, `exists()`), `lua/logseq/telescope.lua` (+ `vim.ui.select` fallback), `lua/logseq/init.lua` (`find_files()`), `tests/graph_spec.lua`, `tests/page_spec.lua`
- **Tasks:**
  - [x] `find_root()`: `vim.fs.find({'logseq/config.edn'}, {upward=true})`, `pages/`+`journals/` sibling detect, `config.graph_path` fallback
  - [x] `list_pages()`: scan `pages/*.md` + `journals/*.md` non-recursive, return `{title, path, kind}`, exclude hidden files
  - [x] `title_to_path()`: canonical escaping (spaces/case preserved; `/` deferred to §8.1)
  - [x] `find_files()`: Telescope via `pcall(require,'telescope')` + `vim.ui.select` fallback
  - [x] Discovery §8.1–§8.2: check `:file-name-format`, confirm journal `%Y_%m_%d`
  - [x] Bugfix: `config.get()` lazily merges live `vim.g.logseq` (defaults < `g:` < `setup(opts)`), so `setup()` stays optional — previously `g:` was ignored until something called `setup()`, and `:LogseqFind` outside the graph errored `graph root not found` (`tests/config_spec.lua`; `graph_spec`/`page_spec` now sanitize ambient `g:` per test)
- **Verify:** `:LogseqFind` against `~/dev/notes_logseq` lists `Machine Learning.md`; `graph_spec` on fixture graph passes; `:checkhealth` OKs.

### M2 — Follow `[[links]]`
- **Scope:** link parsing under cursor + lazy open with dangling-ref semantics (no eager write).
- **Files:** `lua/logseq/parser.lua` (`links_in_line()`, `link_under_cursor()`), `lua/logseq/page.lua` (`open_lazy()`), `lua/logseq/init.lua` (`follow_link()`), `tests/parser_spec.lua` (full), `tests/page_spec.lua` (lazy-open)
- **Tasks:**
  - [x] `links_in_line()`: ordered `{text, col_start, col_end, kind}` for `[[..]]`, `#[[..]]`, `#tag`; multiple per line; after `- TODO ` / tab indents (§8.4)
  - [x] `link_under_cursor(line, col)`: nil-safe, correct link when several per line
  - [x] `open_lazy(path)`: `edit + fnameescape`, `bo.filetype='markdown'`, **never writes** (+ `BufWritePre` guard refuses `:w` on empty dangling pages, `BufWritePost` clears the flag once the file exists)
  - [x] `follow_link()`: parser → `open_lazy` (+ `:LogseqFollow` / `<Plug>(LogseqFollow)` already wired in `plugin/logseq.lua`)
- **Verify:** `[[Missing Page]]` → buffer opens, `filereadable()==0` after open; file appears only after content + `:w`; `:w` on empty warns/refuses; parser unit tests green (incl. `[[a/b]]`, spaces, `#[[a b]]`, `#tag`).

### M3 — Journal / New + Docs
- **Scope:** daily notes, new-page creation, user docs.
- **Files:** `lua/logseq/init.lua` (`today()`, `new_page()`), `doc/logseq.txt`, `README.md`, `after/ftplugin/markdown.lua`
- **Tasks:**
  - [x] `today()`: `journals/<os.date(journal_format)>.md` via `open_lazy` (+ `opts.date` stem override for tests, custom `journal_format` honored)
  - [x] `new_page(title)`: prompt if no arg, then `open_lazy` (accepts `:LogseqNew` cmd_opts `{args=}`, blank title prompts, cancel aborts quietly; shared `resolve_root()` with `find_files`/`follow_link`)
  - [x] `doc/logseq.txt` vimdoc + tags (`:help logseq` works after `:helptags ALL`)
  - [x] `README.md`: install (`vim.pack.add`), usage, repro steps, suggested `gf` → `<Plug>(LogseqFollow)` bind (not forced)
  - [x] `after/ftplugin/markdown.lua`: buffer-local opts only inside graph (`b:logseq_root` + literal hard tabs, buffer-anchored `graph.find_root_from()` that ignores global `graph_path`)
- **Verify:** `:LogseqToday` / `:LogseqNew` lazy-open correctly; `:help logseq` works; README repro steps pass on clean config (`nvim --clean -u tests/minimal_init.lua`).

### M4 — Hardening
- **Scope:** lint, edge cases, idempotency, v0.1 done criteria (§9).
- **Files:** all touched as needed + CI config, `after/ftplugin/markdown.lua` polish
- **Tasks:**
  - [x] `stylua --check` clean + CI job (`make test` + stylua) — `.github/workflows/ci.yml` (stable nvim + plenary clone + StyLua binary), `make ci` target
  - [x] Namespace `/` escaping finalized per §8.1 finding: verbatim mapping kept (no `___`/legacy — zero evidence in-graph), `/` titles refused with WARN in `follow_link`/`new_page` (explicit + prompted); `title_to_filename` unit tests (mapping pins `a/b` → `pages/a/b.md`, facade pins the refusal)
  - [x] Idempotent `:source` / double `setup()`: write-guard group renamed to single `augroup LogseqNvim` + created once (no per-open churn); `tests/idempotency_spec.lua` proves double `setup()`, double `:source` (one of each command + `<Plug>` map), and 3× `open_lazy()` → exactly one autocmd pair
  - [x] `after/ftplugin` polish: unchanged code (already graph-scoped, buffer-local only, no keys) — covered by `ftplugin_spec`; user-visible command descs cleaned of milestone tags
  - [x] Full §5 manual checklist + §9 done criteria (headless proof 2026-09-04/05: health all-OK vs real graph; fallback picker lists 31 items incl. `Machine Learning.md`; dangling flow refuse-then-write on tmp graph; `[[a/b]]` refused; real graph untouched)
- **Verify:** `make test` passes headless; `stylua --check` clean; find + follow (`[[..]]`, `#[[..]]`, `#tag`) work on `~/dev/notes_logseq` with lazy-write semantics; `:checkhealth` all OK (or documented telescope-fallback warns).

### M5 — Multi-graph switching
- **Scope:** switch between several Logseq file graphs so the finder only
  lists the current graph's pages and journals resolve into their own graph.
  Opt-in: with `graphs_dirs` unset, behavior is exactly v0.1 (single graph).
- **Decisions (locked):**
  - Graphs are **auto-discovered** by scanning configured parent dirs
    (no explicit name→path list to maintain).
  - Switching UX is a **picker**: `:LogseqGraphs` (Telescope + `vim.ui.select`
    fallback, reusing `telescope.pick`).
  - **Buffer wins**: when the current buffer sits inside a graph, that graph
    is used regardless of the active selection.
  - The active graph **persists** across restarts (state file under
    `stdpath('data')`).
  - `graph_path` keeps working exactly as today (single-graph shorthand).
- **Config:**
  ```lua
  vim.g.logseq = {
    graphs_dirs = { '~/dev', '~/notes' }, -- parent dirs scanned for graphs
    graphs_depth = 2,                      -- how deep to scan under each dir
    -- graph_path still works exactly as before for single-graph setups
  }
  ```
- **Root resolution order** (`graph.find_root`, revised):
  1. Explicit per-call `opts.root` (unchanged — tests).
  2. Buffer walk-up hit — current buffer inside any graph root (NEW: applies
     even when `graph_path` is set; precedent: `after/ftplugin` already
     ignores `graph_path` via `find_root_from`).
  3. Active graph, if set and still a valid root (NEW).
  4. `graph_path`, strict as today (set-but-missing → `nil`, no silent fallback).
  5. `cwd` walk-up (unchanged).
- **Files:**
  - `lua/logseq/config.lua` (`graphs_dirs`, `graphs_depth` keys + validation)
  - `lua/logseq/graph.lua` (`discover_graphs()`, `list_known()`,
    `set_active()` / `get_active()` / `clear_active()` + state file)
  - `lua/logseq/init.lua` (`switch_graph()`; `find_files` picker title shows
    the graph name so scope is visible)
  - `plugin/logseq.lua` (`:LogseqGraphs`, idempotent like the rest)
  - `lua/logseq/health.lua` (discovered count + names, active graph + source,
    stale-state-file warning)
  - `doc/logseq.txt`, `README.md` (setup, switching, resolution table,
    state-file location)
  - Tests: extend `graph_spec` / `init_spec` / `idempotency_spec`,
    new `graphs_spec.lua` for active-state round-trips
- **Tasks:**
  - M5.1 — Discovery
    - [ ] `discover_graphs()`: depth-limited walk under each `graphs_dirs`
      entry, reusing `is_root()` (`logseq/config.edn` **or**
      `pages/`+`journals/`); skips hidden dirs; returns sorted
      `{ { name, path } }` (`name` = basename, matched internally by path so
      basename collisions stay distinguishable via `name — path` display)
    - [ ] On-demand only (picker open, health check) — never at startup, no
      cache to invalidate
  - M5.2 — Active graph + persistence
    - [ ] `set_active(path|name)` / `get_active()` / `clear_active()`
      (runtime state, not config)
    - [ ] State file `stdpath('data')/logseq.nvim/active` (single-line path);
      lazy load + validate (`isdirectory` + `is_root`); stale entries ignored
      silently (+ health note); test hook for an isolated state path so specs
      stay hermetic
  - M5.3 — Resolution + switching UX
    - [x] `find_root()` reordered per the table above
    - [x] `switch_graph()`: items = `graph_path` ∪ discovered (+ current
      active, so an override is always listed and clearable); `telescope.pick`
      with `(auto)` entry that clears the override; on choice → set, persist,
      `INFO` notify; empty discovery → `WARN` hinting at `graphs_dirs`
    - [x] `:LogseqGraphs` command (double-`:source` safe)
    - [x] `follow_link` / `today` / `new_page` need no logic changes
      (all funnel through `resolve_root`) — covered by order-matrix specs
  - M5.4 — Health + docs + verify
    - [x] Health: discovered graphs, active graph with source
      (`buffer:…` / `active:…` / `graph_path` / `auto`), stale-state warning
    - [x] `README.md` + `doc/logseq.txt` updated
    - [x] Non-goals: no auto-`:cd` on switch, no ftplugin changes
      (already buffer-anchored)
- **Verify:** `make ci` green (60 existing + new specs: discovery fixtures,
  `find_root` order matrix, active round-trip incl. simulated restart, stale
  path ignored, `switch_graph` via stubbed `vim.ui.select`, `:LogseqGraphs`
  idempotency); `stylua --check` clean; manual: two real graphs,
  `:LogseqGraphs` switches picker scope and `:LogseqToday` target,
  buffer-in-other-graph overrides active, choice survives `:restart`.

### M7 — TODO view (dual picker + scratch buffer)

- **Scope:** see all `- <STATUS> text` tasks of the active graph in one
  place, like Logseq desktop's TODO query — both as a fuzzy-find picker
  **and** as a see-all scratch buffer. v1 jumps to the task location;
  marking done comes later.
- **Decisions (locked with user, 2026-09-05):**
  - Dual UI: `:LogseqTodos` (Telescope picker + `vim.ui.select` fallback,
    reusing `telescope.pick`) **and** `:LogseqTodosView` (read-only
    `nofile` scratch buffer grouped by file). Both share one scanner.
  - All statuses shown, DONE last: open
    (`TODO,NOW,LATER,DOING,IN-PROGRESS,WAIT,WAITING`) first in
    file-then-line order, then `DONE,CANCELLED,CANCELED`.
  - Jump-only v1: `<CR>` opens `path:lnum` via `:edit`; `q` closes the
    view. No status toggling (touches task-cycling, a §2 non-goal).
  - Markers are uppercase-only (Logseq requires capitals — lowercase
    `todo` is plain text, not a task). Bullets `-` and `*` accepted;
    numbered lists (`1.`) rejected v1. Priorities (`[#A]`),
    `SCHEDULED:`/`DEADLINE:` stay out of scope (parsed as plain text).
  - No new config keys v1; no auto-`:cd`; root resolution reuses
    `init.resolve_root` (buffer → active → `graph_path` → cwd).
- **Files:**
  - `lua/logseq/tasks.lua` (`parse_line()`, `scan()` — pure except
    `graph.list_pages` + `readfile`, like `index.build`)
  - `lua/logseq/init.lua` (`todos()`, `todos_view()`)
  - `plugin/logseq.lua` (`:LogseqTodos`, `:LogseqTodosView`, idempotent)
  - `doc/logseq.txt`, `README.md` (usage rows for both commands)
  - Tests: `tests/tasks_spec.lua` (parser matrix + scanner contract),
    `init_spec` additions (picker prompt carries graph name, choice jumps
    to `path:lnum`; view buffer render + `<CR>`/`q` + single-buffer reuse)
- **Tasks:**
  - M7.0 — Worktree + baseline + plan (this branch)
    - [x] `git worktree add ../logseq.nvim-todos -b feat/todos-view main`
    - [x] Baseline `make ci` green in the worktree (140 specs, HEAD 920c0c0)
    - [x] M7 plan written here; `tasks.lua` + `tasks_spec.lua` skeletons
      (contract tests red by design — M7.1 turns them green)
  - M7.1 — Core `tasks.lua`
    - [x] `parse_line(line) -> status, text|nil`: `^%s*[-*]%s+(MARKER)%s+(.*)$`,
      blank text rejected, non-string input yields `nil`
    - [x] `scan(root, opts) -> LogseqTask[]`: `graph.list_pages(root)` +
      per-file `readfile`, records `{status, text, path, lnum, title, kind}`;
      missing dirs scan as empty; DONE-group sorts last
    - [x] `tasks_spec.lua` green (parser matrix incl. lowercase rejection,
      tab-indented/nested blocks, `[[links]]` kept as text; scanner on tmp
      graphs: line numbers, journal kind, DONE-last order, hermetic via
      tmpdirs — no fixture changes required)
  - M7.2 — Picker `:LogseqTodos`
    - [x] `todos(opts)`: `resolve_root` → `scan` → empty warns
      (`no tasks found under <root>`) instead of opening a picker →
      `telescope.pick` with `Logseq Todos — <graph>` title,
      `[STATUS] title: text` format, `on_choice` → `:edit +lnum path`
  - M7.3 — Scratch buffer `:LogseqTodosView`
    - [x] `todos_view(opts)`: same scan; `## title (kind)` groups with
      `- [STATUS] lnum: text` rows; `lnum→{path}` map in `b:`; `<CR>`
      jumps, `q` closes; re-running reuses the buffer (no duplicates)
    - [x] `follow_link` / `today` / `new_page` need no logic changes
      (all funnel through `resolve_root`)
  - M7.4 — Docs + verify
    - [x] `README.md` + `doc/logseq.txt` rows for both commands
    - [x] `make ci` green; `stylua --check` clean; manual on real graph:
      picker fuzzy-finds a known TODO and lands on its line, view buffer
      lists pages + journals with DONE last, `q` closes, second open
      reuses the buffer
- **Verify:** `make ci` green (140 existing + new specs); manual against
  `~/dev/notes_logseq` per M7.4; real graph untouched (reads only).
- **Non-goals (v1):** toggle/cycle `TODO→DONE` from the view (buffer-line
  cycling: M8; the view stays jump-only), priorities, scheduling/deadlines, date-grouped queries,
  `setup()` keys, write operations of any kind.
- **Merge note:** this branch also carries `main`'s uncommitted M0–M5
  PLAN.md checkoffs as its base (HEAD's copy was stale) so the plan doc
  merges cleanly; code changes are purely additive (`tasks.lua`,
  `tasks_spec.lua`, +2 commands, docs).

### M8 — Cycle TODO state (single line, configurable chains)

- **Scope:** rotate the task marker on the cursor's line like Logseq
  desktop's `Ctrl+Enter` (`:editor/cycle-todo`, "Rotate the TODO state"):
  `TODO → DOING → DONE → TODO`. First **write** operation in the plugin;
  buffer edit only, single undo step, cursor kept.
- **Decisions (locked with user, 2026-09-05):**
  - Full default chains: `{TODO,DOING,DONE}`, `{LATER,NOW,DONE}`,
    `{IN-PROGRESS,DONE}`, `{WAIT,TODO}`, `{WAITING,TODO}`,
    `{CANCELLED,TODO}`, `{CANCELED,TODO}`; each chain's last element wraps
    to its first, so `DONE → TODO` — cycling never strips the marker
    (Logseq parity; removing a marker is a separate, future action).
  - Chains are user-configurable via `todo_cycles` (precedence
    defaults < `vim.g.logseq` < `setup(opts)`, like all config); e.g.
    `{ { 'TODO', 'DONE' } }` skips DOING. Markers absent from every chain
    don't cycle (WARN, line untouched).
  - First-chain-wins precedence: `DONE → TODO` via chain 1 even though
    DONE also sits in later chains, so `LATER → NOW → DONE → TODO →
    DOING…` flows naturally. Overlap is legal, never an error.
  - Works on any `- <MARKER> text` line in any modifiable buffer (not
    restricted to graph files); silent on success, WARN off-task
    (`no task on current line`), refuse non-modifiable buffers.
  - No default keybinding (repo convention — plus most terminals send
    Ctrl+Enter as plain Enter): `:LogseqCycleTodo` command +
    `<Plug>(LogseqCycleTodo)` with the `hasmapto` guard; README suggests
    `<C-CR>` for GUI users, another key for terminal users.
  - Timestamps/LOGBOOK are desktop timetracking, not core cycling —
    out of scope.
- **Config:**
  ```lua
  vim.g.logseq = {
    todo_cycles = {
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
- **Files:**
  - `lua/logseq/config.lua` (`todo_cycles` default + `known_keys` +
    `vim.validate` type check; wholesale-replace in `get()` — same
    index-merge trap as `graphs_dirs`)
  - `lua/logseq/tasks.lua` (`cycle_status(status, chains)`,
    `cycle_line(line, chains)` — pure, chains passed as params)
  - `lua/logseq/init.lua` (`cycle_todo()`: cursor line → cycle →
    one `nvim_buf_set_lines`, col clamped)
  - `plugin/logseq.lua` (`:LogseqCycleTodo`, `<Plug>(LogseqCycleTodo)`,
    idempotent)
  - `lua/logseq/health.lua` (malformed-chains note; never a hard error,
    per the unknown-keys convention)
  - `doc/logseq.txt`, `README.md` (scope rewrite, usage row, suggested
    maps + terminal caveat, `todo_cycles` example, precedence rule)
  - Tests: extend `tasks_spec.lua`, `init_spec.lua`, `config_spec.lua`,
    `idempotency_spec.lua`
- **Tasks:**
  - M8.1 — Config
    - [x] `todo_cycles` default + `known_keys` + `vim.validate` (table);
      wholesale-replace in `get()` for both `vim.g.logseq` and
      `setup(opts)` layers
    - [x] Malformed entries (empty chains, non-string markers) skipped at
      cycle time + health warning; `config_spec` additions (defaults,
      `g:` override replaces wholesale, malformed → health note not error)
  - M8.2 — Pure core `tasks.lua`
    - [x] `cycle_status(status, chains) -> next|nil`: first-match map per
      call (chains are tiny; no cache, stays pure)
    - [x] `cycle_line(line, chains) -> newline|nil`: reuses the
      `parse_line` pattern, preserves indent + `-`/`*` bullets; nil for
      non-task lines
  - M8.3 — Facade + command + `<Plug>`
    - [x] `cycle_todo()`: current line → `cycle_line` with
      `config.get().todo_cycles` → single `nvim_buf_set_lines`;
      WARN when not on a task line / no next state; refuse when
      `&modifiable` is off
    - [x] `:LogseqCycleTodo` + `<Plug>(LogseqCycleTodo)` (`hasmapto`
      guard); `idempotency_spec` extended
  - M8.4 — Tests
    - [x] `tasks_spec` cycle matrix: every default chain, DONE→TODO wrap,
      custom chains (incl. skip-DOING), indent/bullet preservation,
      non-task → nil (done in M8.2)
    - [x] `init_spec` buffer behavior: advance, wrap, off-task WARN,
      unmodifiable refusal (+ silent success, cursor kept, custom `g:`
      chain, single-undo restore); `idempotency_spec` (done in M8.3)
  - M8.5 — Docs + verify
    - [x] README scope line rewritten (single-line cycling in, multi-line
      / timestamps out) + usage row + maps + `todo_cycles` example
    - [x] `doc/logseq.txt` section (chains, wrap, precedence, keys)
    - [x] `make ci` green; `stylua --check` clean; manual on a scratch md
      only (never real graphs — first write op): full rotation, custom
      chain, off-task WARN, `u` undoes one step
- **Verify:** `make ci` green (160 existing + new specs); manual per M8.5
  on a scratch file; real graphs untouched.
- **Non-goals (v1):** visual/multi-line cycling, LOGBOOK timestamps,
  cycling from `:LogseqTodosView` (view stays jump-only), auto
  keybinding, marker stripping.

### M9 — Smart action (`<CR>`) + link navigation (`[o` / `]o`)

- **Scope:** obsidian.nvim parity for context-aware `<CR>` plus
  next/prev-link jumps, adapted to Logseq semantics. Reference:
  obsidian.nvim `lua/obsidian/actions.lua` `smart_action` (~line 103:
  link → tag → heading/fold → checkbox → fallback `<CR>`) and
  `nav_link(direction)` (~line 65: first match strictly after/before
  the cursor, no wrap, silent at ends). M8's `cycle_todo` *is* the
  checkbox branch; `follow_link` already covers all three parser kinds
  (`[[..]]`, `#[[..]]`, `#tag` → opens `pages/<tag>.md`), so no new
  scanner and no tag picker are needed.
- **Decisions (locked with user, 2026-09-06):**
  - Dispatch order: link-first (obsidian parity — a `[[link]]` under the
    cursor wins even inside a `- TODO` line), then task line →
    `cycle_todo()`, else silent fallback to the default normal-mode
    `<CR>` motion (first non-blank, next line), fed noremap so it can't
    recurse. Fallback makes the auto-bound `<CR>` safe on plain prose.
  - Tag branch = follow (open the tag page, today's behavior). No tag
    picker v1.
  - No fold/heading handling at all — folding stays entirely the user's
    setup; smart_action never sends `za`.
  - Buffer-local `<CR>` in graph markdown files (deliberate, documented
    exception to the no-default-keys convention): `after/ftplugin/
    markdown.lua` maps `<CR>` → `<Plug>(LogseqSmartAction)`, `[o` /
    `]o` → prev/next link, each only when the buffer has no such map
    yet (`nvim_buf_get_keymap` guard — user maps are never clobbered).
    Non-graph markdown untouched (early return stays); `logseq-todos`
    / `logseq-graph` views keep their own buffer-local `<CR>`
    (different filetypes, no conflict).
  - `nav_link` parity: all `parser.links_in_line` matches count as
    stops (no namespace filtering); cursor lands on match start
    (1-based `col_start` → 0-based cursor col); no wrap-around, silent
    at buffer ends; invalid direction asserts.
- **Config:** none (no new keys v1).
- **Files:**
  - `lua/logseq/init.lua` (`M.smart_action()` dispatcher,
    `M.nav_link(direction)` + local `buffer_links(buf)` helper:
    `nvim_buf_get_lines` + `links_in_line` → `{lnum=, col=}` list)
  - `plugin/logseq.lua` (`:LogseqSmartAction`, `:LogseqNextLink`,
    `:LogseqPrevLink` + three `<Plug>` maps with `hasmapto` guards,
    idempotent)
  - `after/ftplugin/markdown.lua` (buffer-local `<CR>` / `[o` / `]o`
    with no-clobber guards)
  - `doc/logseq.txt`, `README.md` (branch order, link-wins example,
    fallback motion, bindings table + remove/override recipe)
  - Tests: extend `init_spec.lua`, `idempotency_spec.lua`, new
    ftplugin spec
- **Tasks:**
  - M9.1 — Facade (`init.lua`)
    - [x] `smart_action()`: link under cursor → `follow_link()`; else
      task line (`tasks.parse_line`) → `cycle_todo()`; else fallback
      feeds `<CR>` noremap (default motion, silent)
    - [x] `nav_link(direction)`: `buffer_links()` scan, strict
      after/before cursor compare (1-based col vs `col_start`, so a
      cursor *on* a link moves to the next one), set cursor on match
      start, silent no-op at ends; assert on bad direction
  - M9.2 — Commands + `<Plug>` + ftplugin
    - [x] `:LogseqSmartAction` / `:LogseqNextLink` / `:LogseqPrevLink`
      + `<Plug>(LogseqSmartAction)` / `<Plug>(LogseqNextLink)` /
      `<Plug>(LogseqPrevLink)` (`hasmapto` guards, idempotent)
    - [x] ftplugin buffer-local `<CR>` / `[o` / `]o` with no-clobber
      guards (skip when any map already exists; graph files only)
  - M9.3 — Tests (spec-first per §8)
    - [x] `init_spec`: dispatch (link line follows incl. link-inside-task
      priority proof, task line cycles, prose line falls back = cursor
      down, no notify); `nav_link` next/prev incl. same-line skip,
      multi-line, silent at ends, invalid-arg assert
    - [x] `idempotency_spec`: 3 commands + 3 `<Plug>` mapargs
    - [x] ftplugin spec: fixture-graph page gets buffer-local
      `<CR>`/`[o`/`]o` (+ functional follow/nav proofs, no-clobber
      proof); non-graph markdown file gets none (explicit `:runtime`)
  - M9.4 — Docs + verify
    - [x] README + `doc/logseq.txt` smart-action section (order,
      fallback, bindings, override recipe, no-folding note)
    - [x] `make ci` green; `stylua --check` clean; manual on a scratch
      graph only: `<CR>` on link / tag / task / prose lines, `[o`/`]o`
      across a page, pre-set buffer-local `<CR>` survives ftplugin
      (2026-09-06: all pass; note the `--noplugin` harness does NOT
      auto-fire `after/ftplugin` on `:edit` — specs and the manual
      script use explicit `:runtime`, real startup is unaffected)
- **Verify:** `make ci` green (existing + ~10 new specs); manual per
  M9.4 on a scratch file; real graphs untouched.
- **Non-goals (v1):** tag picker, any fold setup or `za`, wrap-around
  navigation, namespace filtering in `nav_link`, visual-mode support.

## 8. Open questions / discovery tasks (do during M0–M1, not now)

1. **Filename escaping:** confirm how `/` (namespaces), case, and special chars map to
   filenames in this graph version — inspect `logseq/config.edn :file-name-format`
   (`:triple-lowbar` vs legacy) and test with a scratch page containing `/`.
   → RESOLVED (M4): only `:file-name-format`-adjacent line in the graph's
   `config.edn` is a *commented* `:journal/file-name-format`; zero `___`
   files, zero subdirs under `pages/`+`journals/`, zero `[[a/b]]` links
   anywhere in the graph. Decision: keep verbatim mapping (no invented
   `___`/legacy translation — it would diverge from Logseq on this graph);
   `/` passes through in `title_to_path` but `follow_link`/`new_page`
   refuse such titles with a warning (namespaces out of scope, §2).
2. **Journal naming:** confirm `%Y_%m_%d` holds for all journals (only sample is `2026_08_27.md`).
3. **Front-matter/page properties:** does this graph use first-block `key::` or YAML?
   Affects future `page.create` template, not v0.1 navigation.
4. **Tabs vs spaces:** sample indents are tabs; parser must accept both.

## 9. Done criteria for v0.1

- `make test` passes headless; `stylua --check` clean.
- Against `~/dev/notes_logseq`: find opens pages/journals; follow works for
  `[[..]]`, `#[[..]]`, `#tag`; missing targets open lazily and write only on content.
- `:checkhealth logseq` all OK (or documented warns for missing optional telescope).
- `doc/logseq.txt` installed, `:help logseq` works after `:helptags ALL`.
