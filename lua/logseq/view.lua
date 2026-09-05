--- Local graph explorer (M6.2): a scratch `filetype=logseq-graph` buffer
--- rendering one page's Linked/Backlinks from the M6.1 link index.
--- `●` marks a target whose file exists, `○` a dangling ref (jump opens
--- it lazily via page.open_lazy: nothing is written until content + `:w`).
--- Layout is pure data (M.lines) so specs assert it without windows;
--- M.open/render/jump add the buffer behavior on top. State lives in
--- `b:logseq_graph` ({root=, title=, depth=, show_dangling=}).
local index_mod = require('logseq.index')

local M = {}

local MARK_EXISTS = '●'
local MARK_DANGLING = '○'
local PLACEHOLDER = '(none)'

--- Parse an entry line back to its title. Headers, blanks, and the
--- `(none)` placeholder yield nil.
---@param line string|nil
---@return string|nil
function M.entry_title(line)
  if type(line) ~= 'string' then
    return nil
  end
  local marker, rest = line:match('^(%S+)%s+(.*)$')
  if marker ~= MARK_EXISTS and marker ~= MARK_DANGLING then
    return nil
  end
  if rest == nil or rest == '' then
    return nil
  end
  return rest
end

---@param idx LogseqGraphIndex
---@param titles string[] already-sorted titles
---@param show_dangling boolean
---@return string[] visible titles (counts reflect this, so hiding dangling updates them)
local function shown(idx, titles, show_dangling)
  local out = {}
  for _, t in ipairs(titles) do
    local node = idx.nodes[t]
    if show_dangling or (node ~= nil and node.exists) then
      table.insert(out, t)
    end
  end
  return out
end

---@param out string[]
---@param heading string section heading without the count
---@param idx LogseqGraphIndex
---@param titles string[] already-sorted titles
---@param show_dangling boolean
local function section(out, heading, idx, titles, show_dangling)
  local vis = shown(idx, titles, show_dangling)
  table.insert(out, ('%s (%d)'):format(heading, #vis))
  if #vis == 0 then
    table.insert(out, PLACEHOLDER)
    return
  end
  for _, t in ipairs(vis) do
    local node = idx.nodes[t]
    local exists = node ~= nil and node.exists
    table.insert(out, (exists and MARK_EXISTS or MARK_DANGLING) .. ' ' .. t)
  end
end

--- Pure layout: header + Linked/Backlinks sections (+ `2 hops` at
--- depth 2, i.e. neighbors exactly two edges away). Unknown titles
--- render as empty sections, never an error (a dangling center page
--- still shows its backlinks when other pages link it).
---@param idx LogseqGraphIndex
---@param title string center page title
---@param depth integer 1 or 2 (anything else clamps to 1)
---@param opts table|nil {show_dangling= (default true), graph_name=}
---@return string[]
function M.lines(idx, title, depth, opts)
  opts = opts or {}
  local show_dangling = opts.show_dangling ~= false
  depth = (depth == 2) and 2 or 1
  local out = {
    ('# %s · %s (depth %d)'):format(title, opts.graph_name or 'graph', depth),
    '',
  }
  local fwd = index_mod.forward(idx, title)
  local back = index_mod.back(idx, title)
  section(out, '## Linked', idx, fwd, show_dangling)
  table.insert(out, '')
  section(out, '## Backlinks', idx, back, show_dangling)
  if depth == 2 then
    local near = {}
    for _, t in ipairs(fwd) do
      near[t] = true
    end
    for _, t in ipairs(back) do
      near[t] = true
    end
    local hops = {}
    for _, t in ipairs(index_mod.neighbors(idx, title, 2)) do
      if not near[t] then
        table.insert(hops, t)
      end
    end
    table.sort(hops)
    table.insert(out, '')
    section(out, '## 2 hops', idx, hops, show_dangling)
  end
  return out
end

---@param buf integer
---@return table|nil {root=, title=, depth=, show_dangling=} or nil
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

--- Render the buffer's state (rebuilds nothing; see M.refresh for the
--- index-rebuilding variant). Cursor lands on the first entry line.
---@param buf integer
---@param idx LogseqGraphIndex
function M.render(buf, idx)
  local st = get_state(buf)
  assert(st ~= nil, 'view.render: not a logseq-graph buffer')
  local rendered = M.lines(idx, st.title, st.depth, {
    show_dangling = st.show_dangling,
    graph_name = vim.fn.fnamemodify(st.root, ':t'),
  })
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered)
  vim.bo[buf].modifiable = false
  for i, line in ipairs(rendered) do
    if M.entry_title(line) ~= nil then
      pcall(vim.api.nvim_win_set_cursor, 0, { i, 0 })
      break
    end
  end
end

--- Rebuild the index for the buffer's root and re-render. Silent: the
--- buffer visibly updates, which is the feedback.
---@param buf integer|nil (default current buffer)
function M.refresh(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = get_state(buf)
  assert(st ~= nil, 'view.refresh: not a logseq-graph buffer')
  M.render(buf, index_mod.build(st.root))
end

--- Set explorer depth (1 or 2) and re-render.
---@param buf integer|nil (default current buffer)
---@param depth integer
function M.set_depth(buf, depth)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = get_state(buf)
  assert(st ~= nil, 'view.set_depth: not a logseq-graph buffer')
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
  assert(st ~= nil, 'view.toggle_dangling: not a logseq-graph buffer')
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
local function set_keys(buf)
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
  map('1', function()
    M.set_depth(buf, 1)
  end, 'Logseq: graph depth 1')
  map('2', function()
    M.set_depth(buf, 2)
  end, 'Logseq: graph depth 2')
  map('T', function()
    M.toggle_dangling(buf)
  end, 'Logseq: toggle dangling entries')
end

--- Open the explorer for title under root (builds the index unless one
--- is given). Returns the scratch bufnr and shows it in the window.
---@param opts table {root=, title=, depth= (default 1), show_dangling= (default true), index=}
---@return integer bufnr
function M.open(opts)
  assert(type(opts) == 'table', 'view.open: opts required')
  assert(type(opts.root) == 'string' and opts.root ~= '', 'view.open: root required')
  assert(type(opts.title) == 'string' and opts.title ~= '', 'view.open: title required')
  local idx = opts.index or index_mod.build(opts.root)
  local buf = vim.api.nvim_create_buf(true, false)
  set_state(buf, {
    root = opts.root,
    title = opts.title,
    depth = (opts.depth == 2) and 2 or 1,
    show_dangling = opts.show_dangling ~= false,
  })
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'logseq-graph'
  pcall(vim.api.nvim_buf_set_name, buf, 'logseq-graph:' .. opts.title)
  set_keys(buf)
  M.render(buf, idx)
  vim.bo[buf].modified = false
  return buf
end

--- Open the entry under the cursor: existing pages/journals via :edit,
--- dangling refs lazily (no file until content + `:w`). Stays put with
--- a warning when the cursor is not on an entry.
---@param buf integer|nil (default current buffer)
---@param lnum integer|nil (default cursor line)
function M.jump(buf, lnum)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = get_state(buf)
  assert(st ~= nil, 'view.jump: not a logseq-graph buffer')
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  local title = M.entry_title(vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1])
  if title == nil then
    vim.notify('logseq.nvim: no graph entry under cursor', vim.log.levels.WARN)
    return
  end
  if title:find('/', 1, true) then
    vim.notify(
      ('logseq.nvim: namespace pages like [[%s]] are out of scope for v0.1'):format(title),
      vim.log.levels.WARN
    )
    return
  end
  local idx = index_mod.build(st.root)
  local node = idx.nodes[title]
  if node ~= nil and node.exists and node.path ~= nil then
    vim.cmd('edit ' .. vim.fn.fnameescape(node.path))
    return
  end
  require('logseq.page').open_lazy(require('logseq.page').title_to_path(st.root, title))
end

return M
