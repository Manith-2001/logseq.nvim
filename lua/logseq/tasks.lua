--- Task scan (M7): collect `- <STATUS> text` blocks across a graph.
--- Markers are uppercase-only (Logseq file graphs require capitals):
--- TODO, DOING, NOW, LATER, WAIT, WAITING, IN-PROGRESS, DONE,
--- CANCELLED, CANCELED. Bullets `-` and `*` are accepted; numbered
--- lists are not tasks. Priorities (`[#A]`) and SCHEDULED:/DEADLINE:
--- lines stay plain text inside `text` (out of scope for v1).
--- M7.1 core: parse_line() + scan().
--- M8.2 core: cycle_status() + cycle_line() (pure, chains as params).
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

--- Cycle one marker through chains (M8): the first chain containing the
--- status wins; a chain's last element wraps to its first, so DONE wraps
--- to TODO and cycling never strips the marker. Malformed chains
--- (non-table, empty, non-string entries) are skipped, never an error.
---@param status string current marker, e.g. 'TODO'
---@param chains table|nil list of marker chains
---@return string|nil next marker, nil when status sits in no chain
function M.cycle_status(status, chains)
  if type(status) ~= 'string' or type(chains) ~= 'table' then
    return nil
  end
  for _, chain in ipairs(chains) do
    if type(chain) == 'table' and #chain > 0 then
      for i, marker in ipairs(chain) do
        if marker == status then
          local nxt = chain[i % #chain + 1]
          if type(nxt) == 'string' and nxt ~= '' then
            return nxt
          end
          return nil
        end
      end
    end
  end
  return nil
end

--- Cycle the marker on one line (M8): parse_line gates so only real task
--- lines change; indent, bullet, and trailing text survive byte-for-byte
--- (single gsub; function replacement dodges `%` in custom markers).
--- Nil for non-task lines and unmapped markers.
---@param line string
---@param chains table|nil list of marker chains
---@return string|nil newline
function M.cycle_line(line, chains)
  local status = M.parse_line(line)
  if status == nil then
    return nil
  end
  local nxt = M.cycle_status(status, chains)
  if nxt == nil then
    return nil
  end
  local newline, n = line:gsub('^(%s*[-*]%s+)%S+', function(pre)
    return pre .. nxt
  end, 1)
  if n == 0 then
    return nil
  end
  return newline
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
