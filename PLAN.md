# logseq.nvim — Plan (v0.1 MVP)

> Status: planning only, no implementation yet.
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
- Task state cycling, scheduling, deadlines, priorities.
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
  lua/logseq/telescope.lua   # pcall(require,'telescope'), fallback to vim.ui.select
  lua/logseq/health.lua      # :checkhealth logseq
  after/ftplugin/markdown.lua# buffer-local opts ONLY when inside graph
  doc/logseq.txt             # vimdoc + tags
  tests/minimal_init.lua     # rtp += plenary + repo, no user config
  tests/fixtures/graph/      # tiny fake graph for tests
  tests/parser_spec.lua
  tests/page_spec.lua
  tests/graph_spec.lua
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
  - [ ] `find_root()`: `vim.fs.find({'logseq/config.edn'}, {upward=true})`, `pages/`+`journals/` sibling detect, `config.graph_path` fallback
  - [ ] `list_pages()`: scan `pages/*.md` + `journals/*.md` non-recursive, return `{title, path, kind}`, exclude hidden files
  - [ ] `title_to_path()`: canonical escaping (spaces/case preserved; `/` deferred to §8.1)
  - [ ] `find_files()`: Telescope via `pcall(require,'telescope')` + `vim.ui.select` fallback
  - [ ] Discovery §8.1–§8.2: check `:file-name-format`, confirm journal `%Y_%m_%d`
- **Verify:** `:LogseqFind` against `~/dev/notes_logseq` lists `Machine Learning.md`; `graph_spec` on fixture graph passes; `:checkhealth` OKs.

### M2 — Follow `[[links]]`
- **Scope:** link parsing under cursor + lazy open with dangling-ref semantics (no eager write).
- **Files:** `lua/logseq/parser.lua` (`links_in_line()`, `link_under_cursor()`), `lua/logseq/page.lua` (`open_lazy()`), `lua/logseq/init.lua` (`follow_link()`), `tests/parser_spec.lua` (full), `tests/page_spec.lua` (lazy-open)
- **Tasks:**
  - [ ] `links_in_line()`: ordered `{text, col_start, col_end, kind}` for `[[..]]`, `#[[..]]`, `#tag`; multiple per line; after `- TODO ` / tab indents (§8.4)
  - [ ] `link_under_cursor(line, col)`: nil-safe, correct link when several per line
  - [ ] `open_lazy(path)`: `edit + fnameescape`, `bo.filetype='markdown'`, **never writes**
  - [ ] `follow_link()`: parser → `open_lazy`
- **Verify:** `[[Missing Page]]` → buffer opens, `filereadable()==0` after open; file appears only after content + `:w`; `:w` on empty warns/refuses; parser unit tests green (incl. `[[a/b]]`, spaces, `#[[a b]]`, `#tag`).

### M3 — Journal / New + Docs
- **Scope:** daily notes, new-page creation, user docs.
- **Files:** `lua/logseq/init.lua` (`today()`, `new_page()`), `doc/logseq.txt`, `README.md`, `after/ftplugin/markdown.lua`
- **Tasks:**
  - [ ] `today()`: `journals/<os.date(journal_format)>.md` via `open_lazy`
  - [ ] `new_page(title)`: prompt if no arg, then `open_lazy`
  - [ ] `doc/logseq.txt` vimdoc + tags (`:help logseq` works after `:helptags ALL`)
  - [ ] `README.md`: install (`vim.pack.add`), usage, repro steps, suggested `gf` → `<Plug>(LogseqFollow)` bind (not forced)
  - [ ] `after/ftplugin/markdown.lua`: buffer-local opts only inside graph
- **Verify:** `:LogseqToday` / `:LogseqNew` lazy-open correctly; `:help logseq` works; README repro steps pass on clean config (`nvim --clean -u tests/minimal_init.lua`).

### M4 — Hardening
- **Scope:** lint, edge cases, idempotency, v0.1 done criteria (§9).
- **Files:** all touched as needed + CI config, `after/ftplugin/markdown.lua` polish
- **Tasks:**
  - [ ] `stylua --check` clean + CI job (`make test` + stylua)
  - [ ] Namespace `/` escaping finalized per §8.1 finding; `title_to_filename` unit tests
  - [ ] Idempotent `:source` / double `setup()`: single `augroup LogseqNvim` (`clear=true`), no duplicate commands/autocmds
  - [ ] `after/ftplugin` polish (graph-scoped only, no global key theft)
  - [ ] Full §5 manual checklist + §9 done criteria
- **Verify:** `make test` passes headless; `stylua --check` clean; find + follow (`[[..]]`, `#[[..]]`, `#tag`) work on `~/dev/notes_logseq` with lazy-write semantics; `:checkhealth` all OK (or documented telescope-fallback warns).

## 8. Open questions / discovery tasks (do during M0–M1, not now)

1. **Filename escaping:** confirm how `/` (namespaces), case, and special chars map to
   filenames in this graph version — inspect `logseq/config.edn :file-name-format`
   (`:triple-lowbar` vs legacy) and test with a scratch page containing `/`.
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
