--- Task scan (M7): collect `- <STATUS> text` blocks across a graph.
--- Markers are uppercase-only (Logseq file graphs require capitals):
--- TODO, DOING, NOW, LATER, WAIT, WAITING, IN-PROGRESS, DONE,
--- CANCELLED, CANCELED. Bullets `-` and `*` are accepted; numbered
--- lists are not tasks. Priorities (`[#A]`) and SCHEDULED:/DEADLINE:
--- lines stay plain text inside `text` (out of scope for v1).
--- M7.1 core: parse_line() + scan().
local M = {}

---@class LogseqTask
---@field status string task marker, e.g. 'TODO'
---@field text string remainder of the block after the marker
---@field path string absolute file path
---@field lnum integer 1-based line number
---@field title string page title (filename stem)
---@field kind string 'page' | 'journal'

local OPEN = {
  TODO = true,
  NOW = true,
  LATER = true,
  DOING = true,
  ['IN-PROGRESS'] = true,
  WAIT = true,
  WAITING = true,
}

local DONE_GROUP = {
  DONE = true,
  CANCELLED = true,
  CANCELED = true,
}

--- Parse one line into (status, text). Non-task lines and non-string
--- input yield nil. Blank text after the marker is not a task.
---@param line string
---@return string|nil status
---@return string|nil text
function M.parse_line(line)
  if type(line) ~= 'string' then
    return nil, nil
  end
  -- ^%s*[-*]%s+(MARKER)%s+(.*)$ : bullets `-`/`*`, tabs or spaces,
  -- uppercase markers only; numbered lists never match the bullet.
  local marker, rest = line:match('^%s*[-*]%s+(%S+)%s+(.*)$')
  if marker == nil or rest == nil then
    return nil, nil
  end
  if not OPEN[marker] and not DONE_GROUP[marker] then
    return nil, nil
  end
  local text = rest:match('^%s*(.-)%s*$')
  if text == nil or text == '' then
    return nil, nil
  end
  return marker, text
end

--- Scan root for tasks via graph.list_pages() + per-file readfile
--- (same shape as index.build). Missing dirs scan as empty, never an
--- error. Sorted: open statuses first (file-then-line), DONE-group last.
---@param root string absolute graph root
---@param opts table|nil {pages_dir=, journals_dir=} overrides, used by tests
---@return LogseqTask[]
function M.scan(root, opts)
  assert(type(root) == 'string' and root ~= '', 'tasks.scan: root required')
  local graph = require('logseq.graph')
  local ok, items = pcall(graph.list_pages, root, opts)
  if not ok or type(items) ~= 'table' then
    return {}
  end
  local open = {}
  local done = {}
  for _, item in ipairs(items) do
    local ok_read, lines = pcall(vim.fn.readfile, item.path)
    if ok_read and type(lines) == 'table' then
      for lnum, line in ipairs(lines) do
        local status, text = M.parse_line(line)
        if status ~= nil then
          local task = {
            status = status,
            text = text --[[@as string]],
            path = item.path,
            lnum = lnum,
            title = item.title,
            kind = item.kind,
          }
          if DONE_GROUP[status] then
            table.insert(done, task)
          else
            table.insert(open, task)
          end
        end
      end
    end
  end
  -- Open first in file-then-line order, DONE-group last in file-then-line
  -- order. Both groups already accumulate in (file_idx, lnum) order, so a
  -- plain concat preserves it without re-sorting.
  local out = {}
  for _, task in ipairs(open) do
    table.insert(out, task)
  end
  for _, task in ipairs(done) do
    table.insert(out, task)
  end
  return out
end

return M
