--- Todos scratch view controller (M7.3): renders tasks.scan() output into a
--- single reused read-only `filetype=logseq-todos` buffer, grouped by file.
--- Layout groups scan output by file in first-seen order; rows keep scan
--- order (open first, DONE-group last). Buffer state lives in
--- `b:logseq_todos` ({root=, map=}: buffer lnum -> {path=, lnum=} file
--- location — string keys: b: vars round-trip through VimL).
--- Root resolution, scanning, and empty-graph messaging stay in the facade;
--- this module owns buffer state only (audit ARCH-01).
local M = {}

--- First window displaying buf, or nil (audit API-02).
---@param buf integer
---@return integer|nil winid
local function win_of(buf)
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    return win
  end
  return nil
end

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

--- Render scan output into buf and move the cursor (of the window
--- displaying buf) to the first task row (audit API-02: never the current
--- window's cursor when another buffer is displayed there).
---@param buf integer
---@param root string absolute graph root
---@param found LogseqTask[]
local function todos_render(buf, root, found)
  local lines, map = todos_lines(found, root)
  vim.api.nvim_buf_set_var(buf, 'logseq_todos', { root = root, map = map })
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win = win_of(buf)
  if win ~= nil then
    for i = 1, #lines do
      if map[tostring(i)] ~= nil then
        pcall(vim.api.nvim_win_set_cursor, win, { i, 0 })
        break
      end
    end
  end
end

--- Open the task under the cursor via `:edit +lnum path` (jump-only v1).
--- Stays put with a warning when the cursor is not on a task row.
--- API-02: the cursor is read from the window displaying buf; an explicit
--- lnum works even when buf is hidden.
---@param buf integer|nil (default current buffer)
---@param lnum integer|nil (default cursor line)
function M.jump(buf, lnum)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = todos_state(buf)
  assert(st ~= nil, 'todos_view.jump: not a logseq-todos buffer')
  if lnum == nil then
    local win = win_of(buf)
    if win == nil then
      vim.notify('logseq.nvim: no window displays the todos view', vim.log.levels.WARN)
      return
    end
    lnum = vim.api.nvim_win_get_cursor(win)[1]
  end
  local loc = st.map[tostring(lnum)]
  if loc == nil then
    vim.notify('logseq.nvim: no task under cursor', vim.log.levels.WARN)
    return
  end
  vim.cmd(('edit +%d %s'):format(loc.lnum, vim.fn.fnameescape(loc.path)))
end

--- Close the todos-view buffer.
---@param buf integer|nil (default current buffer)
function M.close(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

---@param buf integer
local function todos_keys(buf)
  vim.keymap.set('n', '<CR>', function()
    M.jump(buf)
  end, { buffer = buf, silent = true, desc = 'Logseq: open task under cursor' })
  vim.keymap.set('n', 'q', function()
    M.close(buf)
  end, { buffer = buf, silent = true, desc = 'Logseq: close todos view' })
end

--- Create/reuse the single todos-view buffer and render root+found.
--- The facade resolved the root, ran the scan, and handled the
--- empty-graph warning; this owns the buffer lifecycle only.
---@param root string absolute graph root
---@param found LogseqTask[]
---@return integer bufnr
function M.open(root, found)
  local buf = todos_find()
  local fresh = buf == nil
  if fresh then
    buf = vim.api.nvim_create_buf(true, false)
  end
  assert(buf ~= nil, 'todos_view.open: no buffer')
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

return M
