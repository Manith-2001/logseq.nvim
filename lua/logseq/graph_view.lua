--- Graph explorer controller (M6.2 local, M6.3 global): owns the scratch
--- `filetype=logseq-graph` buffers — state, keys, render, refresh, picker,
--- navigation. Pure layout lives in logseq.view; this module never calls
--- back into the public facade (audit ARCH-02: no view -> init cycle).
--- State lives in `b:logseq_graph` ({root=, kind='local'|'all', title=
--- (local), depth= (local), show_dangling=, line_map=}).
--- Navigation identity comes from line_map — rendered lines are output
--- only (audit VIEW-01) — and every index build goes through
--- index.build_guarded (audit PERF-01: the size policy at the mechanism
--- boundary, not at selected callers).
local view = require('logseq.view')
local index_mod = require('logseq.index')
local page = require('logseq.page')
local config = require('logseq.config')

local M = {}

--- First window displaying buf, or nil (audit API-02: explicit-buffer
--- operations must not touch the current window's cursor when another
--- buffer is displayed there).
---@param buf integer
---@return integer|nil winid
local function win_of(buf)
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    return win
  end
  return nil
end

---@param buf integer
---@return table|nil {root=, kind=, title=, depth=, show_dangling=, line_map=}
local function get_state(buf)
  local ok, st = pcall(vim.api.nvim_buf_get_var, buf, 'logseq_graph')
  if not ok or type(st) ~= 'table' then
    return nil
  end
  return st
end

---@param buf integer
---@param st table
local function set_state(buf, st)
  vim.api.nvim_buf_set_var(buf, 'logseq_graph', st)
end

--- Render the buffer's state from idx (rebuilds nothing; see M.refresh for
--- the index-rebuilding variant). Local buffers render view.lines, global
--- ones view.all_lines; the fresh line_map is stored for navigation. The
--- cursor lands on the first entry line of the window displaying buf.
--- Warns (does not fail) when idx lists unreadable files (audit IO-01).
---@param buf integer
---@param idx LogseqGraphIndex
function M.render(buf, idx)
  local st = get_state(buf)
  assert(st ~= nil, 'graph_view.render: not a logseq-graph buffer')
  local name = vim.fn.fnamemodify(st.root, ':t')
  local rendered, map
  if st.kind == 'all' then
    rendered, map = view.all_lines_with_map(idx, {
      show_dangling = st.show_dangling,
      graph_name = name,
    })
  else
    rendered, map = view.lines_with_map(idx, st.title, st.depth, {
      show_dangling = st.show_dangling,
      graph_name = name,
    })
  end
  st.line_map = map
  set_state(buf, st)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered)
  vim.bo[buf].modifiable = false
  local win = win_of(buf)
  if win ~= nil then
    for i = 1, #rendered do
      if map[tostring(i)] ~= nil then
        pcall(vim.api.nvim_win_set_cursor, win, { i, 0 })
        break
      end
    end
  end
  if idx.io ~= nil and #idx.io.unreadable > 0 then
    vim.notify(
      ('logseq.nvim: %d file(s) unreadable; view may be incomplete'):format(#idx.io.unreadable),
      vim.log.levels.WARN
    )
  end
end

--- Rebuild the index for the buffer's root and re-render. Guarded by
--- graph_max_files (audit PERF-01: refresh is an interactive index build,
--- so a graph that grew past the limit warns instead of stalling). Silent
--- on success: the buffer visibly updates, which is the feedback.
---@param buf integer|nil (default current buffer)
function M.refresh(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = get_state(buf)
  assert(st ~= nil, 'graph_view.refresh: not a logseq-graph buffer')
  local idx, err = index_mod.build_guarded(st.root)
  if idx == nil then
    vim.notify(index_mod.too_large_message(err.count, err.max), vim.log.levels.WARN)
    return
  end
  M.render(buf, idx)
end

--- Set explorer depth (1 or 2) and re-render. Local buffers only: on a
--- global buffer warns and does nothing (depth is meaningless there, and
--- the `1`/`2` keys are not bound).
---@param buf integer|nil (default current buffer)
---@param depth integer
function M.set_depth(buf, depth)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = get_state(buf)
  assert(st ~= nil, 'graph_view.set_depth: not a logseq-graph buffer')
  if st.kind == 'all' then
    vim.notify('logseq.nvim: depth applies to the local explorer only', vim.log.levels.WARN)
    return
  end
  st.depth = (depth == 2) and 2 or 1
  set_state(buf, st)
  M.refresh(buf)
end

--- Toggle dangling (`○`) entries and re-render. Returns the new flag.
---@param buf integer|nil (default current buffer)
---@return boolean show_dangling
function M.toggle_dangling(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = get_state(buf)
  assert(st ~= nil, 'graph_view.toggle_dangling: not a logseq-graph buffer')
  st.show_dangling = not st.show_dangling
  set_state(buf, st)
  M.refresh(buf)
  return st.show_dangling
end

--- Close the explorer buffer.
---@param buf integer|nil (default current buffer)
function M.close(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

---@param buf integer
---@param kind string 'local'|'all'
local function set_keys(buf, kind)
  local function map(lhs, rhs, desc)
    vim.keymap.set('n', lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end
  map('<CR>', function()
    M.jump(buf)
  end, 'Logseq: open graph entry')
  map('gf', function()
    M.jump(buf)
  end, 'Logseq: open graph entry')
  map('q', function()
    M.close(buf)
  end, 'Logseq: close graph explorer')
  map('r', function()
    M.refresh(buf)
  end, 'Logseq: refresh graph explorer')
  map('T', function()
    M.toggle_dangling(buf)
  end, 'Logseq: toggle dangling entries')
  if kind == 'all' then
    map('P', function()
      M.pick_page(buf)
    end, 'Logseq: pick page for local view')
    return
  end
  map('1', function()
    M.set_depth(buf, 1)
  end, 'Logseq: graph depth 1')
  map('2', function()
    M.set_depth(buf, 2)
  end, 'Logseq: graph depth 2')
end

--- Shared scratch-buffer setup: state var, current window, nofile/wipe,
--- `filetype=logseq-graph`, named `logseq-graph:<name>`.
---@param name string buffer name suffix
---@param st table state for b:logseq_graph
---@return integer bufnr (current)
local function new_buffer(name, st)
  local buf = vim.api.nvim_create_buf(true, false)
  set_state(buf, st)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'logseq-graph'
  pcall(vim.api.nvim_buf_set_name, buf, 'logseq-graph:' .. name)
  return buf
end

--- Open the explorer for title under root. The index builds through
--- index.build_guarded unless one is given (audit PERF-01) — over-limit
--- graphs warn and open nothing. Returns the scratch bufnr.
---@param opts table {root=, title=, depth= (default 1), show_dangling= (default true), index=}
---@return integer|nil bufnr
function M.open(opts)
  assert(type(opts) == 'table', 'graph_view.open: opts required')
  assert(type(opts.root) == 'string' and opts.root ~= '', 'graph_view.open: root required')
  assert(type(opts.title) == 'string' and opts.title ~= '', 'graph_view.open: title required')
  local idx = opts.index
  if idx == nil then
    local err
    idx, err = index_mod.build_guarded(opts.root)
    if idx == nil then
      vim.notify(index_mod.too_large_message(err.count, err.max), vim.log.levels.WARN)
      return nil
    end
  end
  local buf = new_buffer(opts.title, {
    root = opts.root,
    kind = 'local',
    title = opts.title,
    depth = (opts.depth == 2) and 2 or 1,
    show_dangling = opts.show_dangling ~= false,
  })
  set_keys(buf, 'local')
  M.render(buf, idx)
  vim.bo[buf].modified = false
  return buf
end

--- Open the global overview for root. The index builds through
--- index.build_guarded unless one is given (audit PERF-01).
---@param opts table {root=, show_dangling= (default true), index=}
---@return integer|nil bufnr
function M.open_all(opts)
  assert(type(opts) == 'table', 'graph_view.open_all: opts required')
  assert(type(opts.root) == 'string' and opts.root ~= '', 'graph_view.open_all: root required')
  local idx = opts.index
  if idx == nil then
    local err
    idx, err = index_mod.build_guarded(opts.root)
    if idx == nil then
      vim.notify(index_mod.too_large_message(err.count, err.max), vim.log.levels.WARN)
      return nil
    end
  end
  local buf = new_buffer('all', {
    root = opts.root,
    kind = 'all',
    show_dangling = opts.show_dangling ~= false,
  })
  set_keys(buf, 'all')
  M.render(buf, idx)
  vim.bo[buf].modified = false
  return buf
end

--- Pick a page (Telescope, vim.ui.select fallback) and open its local
--- explorer. Items carry the global counts via view.entry_display (audit
--- DRY-05: one display protocol); choosing opens view.open DIRECTLY with
--- the guarded index the picker was built from — never the public facade
--- (audit ARCH-02: no view -> init cycle). Counts shown are counts used.
--- Dangling refs are listed unless the buffer hides them; with nothing
--- to offer, warns instead of opening a picker.
---@param buf integer|nil (default current buffer)
function M.pick_page(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = get_state(buf)
  assert(st ~= nil, 'graph_view.pick_page: not a logseq-graph buffer')
  local idx, err = index_mod.build_guarded(st.root)
  if idx == nil then
    vim.notify(index_mod.too_large_message(err.count, err.max), vim.log.levels.WARN)
    return
  end
  local items = {}
  for _, title in ipairs(index_mod.titles(idx)) do
    local node = idx.nodes[title]
    local exists = node ~= nil and node.exists
    if st.show_dangling or exists then
      table.insert(items, {
        title = title,
        kind = (node ~= nil and node.kind) or 'dangling',
        fwd = #index_mod.forward(idx, title),
        back = #index_mod.back(idx, title),
      })
    end
  end
  if #items == 0 then
    vim.notify('logseq.nvim: no pages found to pick from', vim.log.levels.WARN)
    return
  end
  -- Depth parity with the old facade round-trip: a local buffer keeps its
  -- own depth; a global pick falls back to the config default.
  local depth = (st.kind == 'local') and st.depth or ((config.get().graph_depth == 2) and 2 or 1)
  require('logseq.telescope').pick(items, {
    prompt_title = ('Logseq Graph — %s'):format(vim.fn.fnamemodify(st.root, ':t')),
    format_item = function(item)
      return view.entry_display(item.title, item.fwd, item.back, item.kind ~= 'dangling')
    end,
    on_choice = function(choice)
      M.open({ root = st.root, title = choice.title, depth = depth, index = idx })
    end,
  })
end

--- Open the entry under the cursor: existing pages/journals via :edit,
--- dangling refs lazily (no file until content + `:w`). Identity comes from
--- the render-time line_map (audit VIEW-01) — nothing is parsed from the
--- text and NO index is rebuilt (audit PERF-01). Stays put with a warning
--- when the cursor is not on an entry.
--- API-02: the cursor is read from the window displaying buf (not the
--- current window); an explicit lnum works even when buf is hidden.
---@param buf integer|nil (default current buffer)
---@param lnum integer|nil (default cursor line of buf's window)
function M.jump(buf, lnum)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = get_state(buf)
  assert(st ~= nil, 'graph_view.jump: not a logseq-graph buffer')
  if lnum == nil then
    local win = win_of(buf)
    if win == nil then
      vim.notify('logseq.nvim: no window displays the graph explorer', vim.log.levels.WARN)
      return
    end
    lnum = vim.api.nvim_win_get_cursor(win)[1]
  end
  local entry = st.line_map ~= nil and st.line_map[tostring(lnum)] or nil
  if entry == nil then
    vim.notify('logseq.nvim: no graph entry under cursor', vim.log.levels.WARN)
    return
  end
  if page.is_namespace(entry.title) then
    vim.notify(page.namespace_notice(entry.title), vim.log.levels.WARN)
    return
  end
  if entry.exists and entry.path ~= nil then
    vim.cmd('edit ' .. vim.fn.fnameescape(entry.path))
    return
  end
  page.open_lazy(page.title_to_path(st.root, entry.title))
end

return M
