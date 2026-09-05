--- Public facade. M1: find_files(); M2: follow_link(); M3: today()/new_page();
--- M5.3: switch_graph(); M6.2: graph_view().
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
---@return string|nil
local function resolve_root(opts)
  local graph = require('logseq.graph')
  local root = (type(opts.root) == 'string' and opts.root ~= '') and opts.root or graph.find_root()
  if not root then
    vim.notify(
      'logseq.nvim: graph root not found (set graph_path, pick :LogseqGraphs, or open a file inside the graph)',
      vim.log.levels.ERROR
    )
    return nil
  end
  return root
end

--- Namespace guard (M4, see §2 non-goals + §8.1 finding): titles containing
--- `/` map to subpaths that Logseq namespaces own. v0.1 refuses them with a
--- warning instead of opening a buffer that could never round-trip.
---@param title string
---@return boolean true when the title is namespace-free
local function check_no_namespace(title)
  if title:find('/', 1, true) then
    vim.notify(
      ('logseq.nvim: namespace pages like [[%s]] are out of scope for v0.1'):format(title),
      vim.log.levels.WARN
    )
    return false
  end
  return true
end

--- Find/open pages + journals via Telescope (vim.ui.select fallback).
--- opts.root overrides root resolution (used by tests); otherwise
--- graph.find_root() applies (buffer → active → graph_path → cwd).
--- The picker title shows the graph name so the scope is visible.
---@param opts table|nil
function M.find_files(opts)
  opts = opts or {}
  local root = resolve_root(opts)
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
    local norm = vim.fn.fnamemodify(vim.fn.expand(cfg.graph_path), ':p'):gsub('/+$', '')
    if norm == '' then
      norm = '/'
    end
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
    prompt_title = 'Logseq Graphs',
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
--- prompt; cancelling aborts quietly. The index builds synchronously and
--- refuses graphs over graph_max_files with a warning (raise the key to
--- opt in). opts.root overrides root resolution (used by tests).
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
  local count = #require('logseq.graph').list_pages(root)
  if count > cfg.graph_max_files then
    vim.notify(
      ('logseq.nvim: graph too large (%d files > %d graph_max_files); raise graph_max_files to explore it'):format(
        count,
        cfg.graph_max_files
      ),
      vim.log.levels.WARN
    )
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
    return require('logseq.view').open({ root = root, title = title, depth = depth })
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
    bufnr = require('logseq.view').open({ root = root, title = input, depth = depth })
  end)
  return bufnr
end

--- Todos view helpers (M7.3). Layout groups scan output by file in
--- first-seen order; rows keep scan order (open first, DONE-group last).
---@param found LogseqTask[]
---@param root string absolute graph root
---@return string[] lines
---@return table<integer, table> map buffer lnum -> {path=, lnum=} location
local function todos_lines(found, root)
  local lines = {
    ('# Logseq Todos · %s (%d)'):format(vim.fn.fnamemodify(root, ':t'), #found),
    '',
  }
  local map = {}
  local order = {}
  local groups = {}
  for _, task in ipairs(found) do
    local g = groups[task.path]
    if g == nil then
      g = { title = task.title, kind = task.kind, rows = {} }
      groups[task.path] = g
      table.insert(order, task.path)
    end
    table.insert(g.rows, task)
  end
  for gi, path in ipairs(order) do
    local g = groups[path]
    table.insert(lines, ('## %s (%s)'):format(g.title, g.kind))
    for _, task in ipairs(g.rows) do
      table.insert(lines, ('- [%s] %d: %s'):format(task.status, task.lnum, task.text))
      -- String keys: b: vars round-trip through VimL, where dict keys are
      -- strings (sparse integer keys would not convert).
      map[tostring(#lines)] = { path = task.path, lnum = task.lnum }
    end
    if gi < #order then
      table.insert(lines, '')
    end
  end
  return lines, map
end

---@param buf integer
---@return table|nil {root=, map=} or nil when not a todos-view buffer
local function todos_state(buf)
  local ok, st = pcall(vim.api.nvim_buf_get_var, buf, 'logseq_todos')
  if not ok or type(st) ~= 'table' then
    return nil
  end
  return st
end

---@return integer|nil existing todos-view bufnr (single buffer, reused)
local function todos_find()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and todos_state(buf) ~= nil then
      return buf
    end
  end
  return nil
end

--- Render scan output into buf and move the cursor to the first task row.
---@param buf integer
---@param root string absolute graph root
---@param found LogseqTask[]
local function todos_render(buf, root, found)
  local lines, map = todos_lines(found, root)
  vim.api.nvim_buf_set_var(buf, 'logseq_todos', { root = root, map = map })
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for i = 1, #lines do
    if map[tostring(i)] ~= nil then
      pcall(vim.api.nvim_win_set_cursor, 0, { i, 0 })
      break
    end
  end
end

--- Open the task under the cursor via `:edit +lnum path` (jump-only v1).
--- Stays put with a warning when the cursor is not on a task row.
---@param buf integer|nil (default current buffer)
---@param lnum integer|nil (default cursor line)
local function todos_jump(buf, lnum)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = todos_state(buf)
  assert(st ~= nil, 'todos_jump: not a logseq-todos buffer')
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  local loc = st.map[tostring(lnum)]
  if loc == nil then
    vim.notify('logseq.nvim: no task under cursor', vim.log.levels.WARN)
    return
  end
  vim.cmd(('edit +%d %s'):format(loc.lnum, vim.fn.fnameescape(loc.path)))
end

--- Close the todos-view buffer.
---@param buf integer|nil (default current buffer)
local function todos_close(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

---@param buf integer
local function todos_keys(buf)
  vim.keymap.set('n', '<CR>', function()
    todos_jump(buf)
  end, { buffer = buf, silent = true, desc = 'Logseq: open task under cursor' })
  vim.keymap.set('n', 'q', function()
    todos_close(buf)
  end, { buffer = buf, silent = true, desc = 'Logseq: close todos view' })
end

--- List all `- <STATUS> text` tasks of the graph in a picker (M7.2,
--- jump-only v1). Shares tasks.scan() with todos_view(). An empty graph
--- warns instead of opening a picker. Rows show `[STATUS] title: text`
--- under a `Logseq Todos — <graph>` title; choosing jumps to `path:lnum`
--- via `:edit`. opts.root overrides root resolution (used by tests).
---@param opts table|nil
function M.todos(opts)
  opts = opts or {}
  local root = resolve_root(opts)
  if not root then
    return
  end
  local found = require('logseq.tasks').scan(root)
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

--- Todos scratch view (M7.3, jump-only v1): all tasks grouped by file as
--- `## title (kind)` sections with `- [STATUS] lnum: text` rows in a
--- read-only `filetype=logseq-todos` buffer. Buffer state lives in
--- `b:logseq_todos` ({root=, map=}: buffer lnum -> {path=, lnum=} file
--- location). `<CR>` jumps to the task location, `q` closes; re-running
--- reuses the single view buffer (no duplicates). Like todos(), an empty
--- graph warns and opens nothing. opts.root overrides root resolution
--- (used by tests).
---@param opts table|nil
---@return integer|nil view bufnr, or nil when aborted
function M.todos_view(opts)
  opts = opts or {}
  local root = resolve_root(opts)
  if not root then
    return nil
  end
  local found = require('logseq.tasks').scan(root)
  if #found == 0 then
    vim.notify(('logseq.nvim: no tasks found under %s'):format(root), vim.log.levels.WARN)
    return nil
  end
  local buf = todos_find()
  local fresh = buf == nil
  if fresh then
    buf = vim.api.nvim_create_buf(true, false)
  end
  assert(buf ~= nil, 'todos_view: no buffer')
  vim.api.nvim_set_current_buf(buf)
  if fresh then
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = 'logseq-todos'
    todos_keys(buf)
  end
  pcall(vim.api.nvim_buf_set_name, buf, 'logseq-todos:' .. vim.fn.fnamemodify(root, ':t'))
  todos_render(buf, root, found)
  vim.bo[buf].modified = false
  return buf
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

return M
