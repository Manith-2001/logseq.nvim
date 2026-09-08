--- Public facade. M1: find_files(); M2: follow_link(); M3: today()/new_page();
--- M5.3: switch_graph(); M6.2: graph_view(); M6.3: graph_view_all().
--- View state lives in logseq.graph_view / logseq.todos_view; this module
--- keeps root resolution, scanning/guarding, and user messaging.
local config = require('logseq.config')

local M = {}

--- Merge opts (delegates to config). Optional; plugin works without it.
---@param opts table|nil
function M.setup(opts)
  return config.setup(opts)
end

--- Shared root resolution (M5.3 order): opts.root (explicit per call) →
--- buffer walk-up → active graph → graph_path (strict) → cwd walk-up.
--- Notifies + returns nil when no root is found.
---@param opts table
---@param prefer_active boolean|nil when true, the active graph beats the
--- current buffer (search pickers: Find/Todos/GraphAll). Contextual
--- commands (follow/today/new/local graph view) keep buffer-first.
---@return string|nil
local function resolve_root(opts, prefer_active)
  local graph = require('logseq.graph')
  if type(opts.root) == 'string' and opts.root ~= '' then
    return opts.root
  end
  if prefer_active then
    local active = graph.get_active()
    if active then
      return active
    end
  end
  local root = graph.find_root()
  if not root then
    vim.notify(
      'logseq.nvim: graph root not found (set graph_path, pick :LogseqSwitchGraph, or open a file inside the graph)',
      vim.log.levels.ERROR
    )
    return nil
  end
  return root
end

--- Namespace guard (M4, see §2 non-goals + §8.1 finding): titles containing
--- `/` map to subpaths that Logseq namespaces own. v0.1 refuses them with a
--- warning instead of opening a buffer that could never round-trip.
--- The predicate + notice text are owned by logseq.page (DRY-01).
---@param title string
---@return boolean true when the title is namespace-free
local function check_no_namespace(title)
  if require('logseq.page').is_namespace(title) then
    vim.notify(require('logseq.page').namespace_notice(title), vim.log.levels.WARN)
    return false
  end
  return true
end

--- Find/open pages + journals via Telescope (vim.ui.select fallback).
--- opts.root overrides root resolution (used by tests); otherwise
--- the active graph beats the current buffer (search scope follows
--- :LogseqSwitchGraph, so a buffer in another graph doesn't hijack results),
--- then buffer → graph_path → cwd.
--- The picker title shows the graph name so the scope is visible.
---@param opts table|nil
function M.find_files(opts)
  opts = opts or {}
  local root = resolve_root(opts, true)
  if not root then
    return
  end
  local items = require('logseq.graph').list_pages(root)
  if #items == 0 then
    vim.notify(('logseq.nvim: no pages found under %s'):format(root), vim.log.levels.WARN)
    return
  end
  require('logseq.telescope').pick(items, {
    prompt_title = ('Logseq Pages — %s'):format(vim.fn.fnamemodify(root, ':t')),
    on_choice = function(item)
      vim.cmd('edit ' .. vim.fn.fnameescape(item.path))
    end,
  })
end

--- Follow the [[link]] / #[[link]] / #tag under the cursor.
--- Opens lazily via page.open_lazy: missing pages open as empty buffers
--- and no file is created until content is written (dangling refs).
--- opts.root overrides root resolution (used by tests); otherwise
--- graph.find_root() applies (buffer → active → graph_path → cwd).
---@param opts table|nil
function M.follow_link(opts)
  opts = opts or {}
  local root = resolve_root(opts)
  if not root then
    return
  end
  local parser = require('logseq.parser')
  local page = require('logseq.page')
  local ok, line = pcall(vim.api.nvim_get_current_line)
  if not ok then
    return
  end
  -- nvim_win_get_cursor col is 0-based; the parser uses 1-based cols.
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local link = parser.link_under_cursor(line, col)
  if not link then
    vim.notify('logseq.nvim: no link under cursor', vim.log.levels.WARN)
    return
  end
  if not check_no_namespace(link.text) then
    return
  end
  page.open_lazy(page.title_to_path(root, link.text))
end

--- Open today's journal (`journals/<os.date(journal_format)>.md`) lazily:
--- a missing journal opens as an empty buffer, no file until content + `:w`.
--- opts.root overrides root resolution (used by tests); opts.date
--- (a filename stem like '2026_08_27') overrides os.date (used by tests).
---@param opts table|nil
function M.today(opts)
  opts = opts or {}
  local root = resolve_root(opts)
  if not root then
    return
  end
  local stem = opts.date
  if type(stem) ~= 'string' or stem == '' then
    stem = os.date(config.get().journal_format)
  end
  local page = require('logseq.page')
  page.open_lazy(page.journal_to_path(root, stem))
end

--- Open a (possibly new) page lazily via page.open_lazy.
--- title may be a string, or the cmd_opts table from :LogseqNew
--- (whose .args holds the title, '' when none was given). With no usable
--- title the user is prompted via vim.ui.input; cancelling aborts quietly.
---@param title string|table|nil
---@param opts table|nil ({root=} override, used by tests)
function M.new_page(title, opts)
  if type(title) == 'table' then
    if type(title.args) == 'string' and title.args ~= '' then
      title = title.args -- :LogseqNew cmd_opts: .args holds the title
    else
      opts, title = title, nil -- opts-style call new_page({root=...}): prompt
    end
  end
  opts = opts or {}
  if type(title) == 'string' and title:match('^%s*$') then
    title = nil -- blank behaves like no title: prompt instead of asserting
  end
  local root = resolve_root(opts)
  if not root then
    return
  end
  local page = require('logseq.page')
  if title ~= nil then
    if not check_no_namespace(title) then
      return
    end
    page.open_lazy(page.title_to_path(root, title))
    return
  end
  vim.ui.input({ prompt = 'Logseq new page: ' }, function(input)
    if input == nil or input:match('^%s*$') then
      vim.notify('logseq.nvim: new page cancelled', vim.log.levels.INFO)
      return
    end
    if not check_no_namespace(input) then
      return
    end
    page.open_lazy(page.title_to_path(root, input))
  end)
end

--- Derive the center title from the current buffer when it is a page or
--- journal directly under root (symlink-resolved on both sides, like the
--- M3 specs). Returns nil for unnamed buffers and files outside the graph.
---@param root string absolute graph root
---@return string|nil
local function title_from_buffer(root)
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then
    return nil
  end
  local resolved = vim.fn.resolve(name)
  local base = vim.fn.resolve(root)
  for _, sub in ipairs({ config.get().pages_dir, config.get().journals_dir }) do
    local prefix = base .. '/' .. sub .. '/'
    if resolved:sub(1, #prefix) == prefix and resolved:sub(-3) == '.md' then
      return resolved:sub(#prefix + 1, -4)
    end
  end
  return nil
end

--- Pick the active graph (M5.3, multi-graph switching) via Telescope
--- (vim.ui.select fallback). Items = graph_path ∪ discovered roots ∪ the
--- current active (so an override is listed — and clearable — even when it
--- came from outside the picker), shown as `name — path` so basename
--- collisions stay distinguishable; matched internally by path. The `(auto)`
--- entry clears the override back to plain resolution. Choosing sets +
--- persists (INFO notify); with nothing to offer, warns and hints at
--- graphs_dirs instead of opening a picker.
--- A stale graph_path stays listed and errors loudly on selection
--- (strictness: misconfiguration must not silently resolve elsewhere).
function M.switch_graph()
  local graph = require('logseq.graph')
  local cfg = config.get()
  local items = {}
  local seen = {}
  local function offer(name, path)
    local key = path or '(auto)'
    if not seen[key] then
      seen[key] = true
      table.insert(items, {
        title = path and ('%s — %s'):format(name, path) or '(auto) — resolve automatically',
        kind = path and 'graph' or 'auto',
        name = name,
        path = path,
      })
    end
  end
  if type(cfg.graph_path) == 'string' and cfg.graph_path ~= '' then
    local norm = require('logseq.graph').normalize_path(cfg.graph_path)
    offer(vim.fn.fnamemodify(norm, ':t'), norm)
  end
  for _, known in ipairs(graph.discover_graphs()) do
    offer(known.name, known.path)
  end
  local active = graph.get_active()
  if active then
    offer(vim.fn.fnamemodify(active, ':t'), active)
  end
  if #items == 0 then
    vim.notify(
      'logseq.nvim: no graphs found (set graphs_dirs to scan for graphs)',
      vim.log.levels.WARN
    )
    return
  end
  offer('(auto)', nil)
  require('logseq.telescope').pick(items, {
    prompt_title = 'Logseq Switch Graph',
    on_choice = function(choice)
      if choice.path == nil then
        graph.clear_active()
        vim.notify('logseq.nvim: active graph cleared (auto)', vim.log.levels.INFO)
        return
      end
      graph.set_active(choice.path)
      vim.notify(('logseq.nvim: active graph: %s'):format(choice.name), vim.log.levels.INFO)
    end,
  })
end

--- Open the local graph explorer (M6.2) for one page: Linked +
--- Backlinks (+ `2 hops` at depth 2) in a scratch `filetype=logseq-graph`
--- buffer. The center title comes from opts.title (or :LogseqGraph's
--- [title] arg), else the current pages/*/journals/* buffer, else a
--- prompt; cancelling aborts quietly. The index builds through
--- index.build_guarded (audit PERF-01: the size policy at the build
--- boundary) — over-limit graphs warn once and nothing opens. opts.root
--- overrides root resolution (used by tests).
---@param opts table|nil ({title=, depth=, root=}; :LogseqGraph cmd_opts tolerated)
---@return integer|nil explorer bufnr, or nil when aborted
function M.graph_view(opts)
  opts = opts or {}
  if
    type(opts.title) ~= 'string'
    and opts.root == nil
    and type(opts.args) == 'string'
    and opts.args ~= ''
  then
    opts = { title = opts.args } -- :LogseqGraph cmd_opts: .args holds the title
  end
  local root = resolve_root(opts)
  if not root then
    return nil
  end
  local cfg = config.get()
  local depth = (opts.depth == 2 or cfg.graph_depth == 2) and 2 or 1
  local index_mod = require('logseq.index')
  local idx, guard_err = index_mod.build_guarded(root)
  if idx == nil then
    vim.notify(index_mod.too_large_message(guard_err.count, guard_err.max), vim.log.levels.WARN)
    return nil
  end
  local title = opts.title
  if type(title) == 'string' and title:match('^%s*$') then
    title = nil -- blank behaves like no title: derive, then prompt
  end
  if title == nil then
    title = title_from_buffer(root)
  end
  if title ~= nil then
    if not check_no_namespace(title) then
      return nil
    end
    return require('logseq.graph_view').open({
      root = root,
      title = title,
      depth = depth,
      index = idx,
    })
  end
  local bufnr = nil
  vim.ui.input({ prompt = 'Logseq graph page: ' }, function(input)
    if input == nil or input:match('^%s*$') then
      vim.notify('logseq.nvim: graph view cancelled', vim.log.levels.INFO)
      return
    end
    if not check_no_namespace(input) then
      return
    end
    bufnr =
      require('logseq.graph_view').open({ root = root, title = input, depth = depth, index = idx })
  end)
  return bufnr
end

--- List all `- <STATUS> text` tasks of the graph in a picker (M7.2,
--- jump-only v1). Shares tasks.scan() with todos_view(). An empty graph
--- warns instead of opening a picker; unreadable files warn once about a
--- possibly incomplete list (audit IO-01) — the list still opens.
--- Rows show `[STATUS] title: text` under a `Logseq Todos — <graph>`
--- title; choosing jumps to `path:lnum` via `:edit`. opts.root overrides
--- root resolution (used by tests); otherwise active beats buffer (like
--- find_files).
---@param opts table|nil
function M.todos(opts)
  opts = opts or {}
  local root = resolve_root(opts, true)
  if not root then
    return
  end
  local found, report = require('logseq.tasks').scan(root)
  if report ~= nil then
    vim.notify(
      ('logseq.nvim: %d file(s) unreadable; task list may be incomplete'):format(#report.unreadable),
      vim.log.levels.WARN
    )
  end
  if #found == 0 then
    vim.notify(('logseq.nvim: no tasks found under %s'):format(root), vim.log.levels.WARN)
    return
  end
  require('logseq.telescope').pick(found, {
    prompt_title = ('Logseq Todos — %s'):format(vim.fn.fnamemodify(root, ':t')),
    format_item = function(task)
      return ('[%s] %s: %s'):format(task.status, task.title, task.text)
    end,
    ordinal = function(task)
      return ('%s %s %s'):format(task.status, task.title, task.text)
    end,
    on_choice = function(task)
      vim.cmd(('edit +%d %s'):format(task.lnum, vim.fn.fnameescape(task.path)))
    end,
  })
end

--- Todos scratch view (M7.3, jump-only v1): all tasks grouped by file in a
--- read-only `filetype=logseq-todos` buffer (`<CR>` jumps, `q` closes;
--- re-running reuses the single view buffer). Root resolution, the scan,
--- and empty/unreadable messaging live here; buffer state is owned by
--- logseq.todos_view (audit ARCH-01). opts.root overrides root resolution
--- (used by tests); otherwise active beats buffer (like find_files).
---@param opts table|nil
---@return integer|nil view bufnr, or nil when aborted
function M.todos_view(opts)
  opts = opts or {}
  local root = resolve_root(opts, true)
  if not root then
    return nil
  end
  local found, report = require('logseq.tasks').scan(root)
  if report ~= nil then
    vim.notify(
      ('logseq.nvim: %d file(s) unreadable; task list may be incomplete'):format(#report.unreadable),
      vim.log.levels.WARN
    )
  end
  if #found == 0 then
    vim.notify(('logseq.nvim: no tasks found under %s'):format(root), vim.log.levels.WARN)
    return nil
  end
  return require('logseq.todos_view').open(root, found)
end

--- Cycle the TODO marker on the cursor line (M8.3): rotates the marker
--- through config.todo_cycles and writes the line back with one
--- nvim_buf_set_lines (single undo step, cursor kept). Works in any
--- modifiable buffer, not just graph files. Silent on success; WARNs when
--- the buffer is not modifiable or the line is not a cyclable task.
function M.cycle_todo()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.bo[buf].modifiable then
    vim.notify('logseq.nvim: buffer is not modifiable', vim.log.levels.WARN)
    return
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local row, col = cur[1], cur[2]
  local lines = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)
  local newline =
    require('logseq.tasks').cycle_line(lines[1], require('logseq.config').get().todo_cycles)
  if newline == nil then
    vim.notify('logseq.nvim: no cyclable task on current line', vim.log.levels.WARN)
    return
  end
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { newline })
  pcall(vim.api.nvim_win_set_cursor, 0, { row, math.min(col, #newline) })
end

--- Collect every link in buffer buf as {lnum=, col=} stops (M9.1):
--- 1-based line number plus the 1-based col_start of each
--- parser.links_in_line() match, in buffer order.
---@param buf integer
---@return table[] {lnum: integer, col: integer}[]
local function buffer_links(buf)
  local parser = require('logseq.parser')
  local out = {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for lnum, line in ipairs(lines) do
    for _, link in ipairs(parser.links_in_line(line)) do
      table.insert(out, { lnum = lnum, col = link.col_start })
    end
  end
  return out
end

--- Context-aware action for `<CR>` (M9.1, obsidian.nvim smart_action
--- parity minus folding): link under cursor (any kind, even inside a
--- task line) → follow_link(); else task line → cycle_todo(); else
--- fall back to the default normal-mode `<CR>` motion (first non-blank
--- of the next line) via `normal!`, which ignores mappings and so can
--- never recurse into the caller's `<CR>` map. opts.root threads
--- through to follow_link (used by tests).
---@param opts table|nil ({root=} override)
function M.smart_action(opts)
  opts = opts or {}
  local parser = require('logseq.parser')
  local ok, line = pcall(vim.api.nvim_get_current_line)
  if not ok then
    return
  end
  -- nvim_win_get_cursor col is 0-based; the parser uses 1-based cols.
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  if parser.link_under_cursor(line, col) then
    M.follow_link(opts)
    return
  end
  if require('logseq.tasks').parse_line(line) then
    M.cycle_todo()
    return
  end
  -- Plain prose: behave exactly like unmapped <CR>. `+` is the same
  -- motion; silent! keeps the last line a quiet no-op.
  pcall(vim.cmd, 'silent! normal! +')
end

--- Jump to the next/previous link in the current buffer (M9.1,
--- obsidian.nvim nav_link parity): the first stop strictly after
--- ('next') or before ('prev') the cursor wins, so a cursor sitting on
--- a link moves on to the neighboring one. No wrap-around: a silent
--- no-op at the ends and in link-free buffers.
---@param direction string 'next' | 'prev'
function M.nav_link(direction)
  assert(direction == 'next' or direction == 'prev', 'nav_link: direction must be "next" or "prev"')
  local matches = buffer_links(vim.api.nvim_get_current_buf())
  if #matches == 0 then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local row, col = cur[1], cur[2] + 1 -- 1-based col, like the parser
  if direction == 'next' then
    for _, m in ipairs(matches) do
      if m.lnum > row or (m.lnum == row and col < m.col) then
        pcall(vim.api.nvim_win_set_cursor, 0, { m.lnum, m.col - 1 })
        return
      end
    end
    return
  end
  for i = #matches, 1, -1 do
    local m = matches[i]
    if m.lnum < row or (m.lnum == row and col > m.col) then
      pcall(vim.api.nvim_win_set_cursor, 0, { m.lnum, m.col - 1 })
      return
    end
  end
end

--- Open the global graph overview (M6.3): every page/journal/dangling
--- ref with per-entry link counts in a scratch `filetype=logseq-graph`
--- buffer. `<CR>`/`gf` jumps to the entry's page, `P` picks a page for
--- the local explorer, `T` toggles dangling, `r` refreshes, `q` closes.
--- The index builds through index.build_guarded (audit PERF-01).
--- opts.root overrides root resolution (used by tests); otherwise active
--- beats buffer (like find_files).
---@param opts table|nil ({root=}; no command args: :LogseqGraphAll takes none)
---@return integer|nil explorer bufnr, or nil when aborted
function M.graph_view_all(opts)
  opts = opts or {}
  local root = resolve_root(opts, true)
  if not root then
    return nil
  end
  local index_mod = require('logseq.index')
  local idx, guard_err = index_mod.build_guarded(root)
  if idx == nil then
    vim.notify(index_mod.too_large_message(guard_err.count, guard_err.max), vim.log.levels.WARN)
    return nil
  end
  return require('logseq.graph_view').open_all({ root = root, index = idx })
end

return M
