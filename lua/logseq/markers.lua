--- Canonical Logseq task-marker vocabulary (DRY-03): one owner for the
--- words parse_line() accepts, scan() groups by, and todo_cycles chains
--- are validated against. Uppercase-only, like Logseq file graphs.
--- Adding marker words is a DOMAIN change (new Logseq release), not a
--- config change; custom chains reorder/subset these, never extend them.
local M = {}

---@type table<string, boolean> open (actionable) markers
M.OPEN = {
  TODO = true,
  NOW = true,
  LATER = true,
  DOING = true,
  ['IN-PROGRESS'] = true,
  WAIT = true,
  WAITING = true,
}

---@type table<string, boolean> terminal markers (grouped last by scan)
M.DONE = {
  DONE = true,
  CANCELLED = true,
  CANCELED = true,
}

---@param marker any
---@return boolean true for any canonical marker
function M.is_canonical(marker)
  return (M.OPEN[marker] or M.DONE[marker]) == true
end

---@param marker any
---@return boolean true for an open (actionable) canonical marker
function M.is_open(marker)
  return M.OPEN[marker] == true
end

---@param marker any
---@return boolean true for a terminal canonical marker
function M.is_done(marker)
  return M.DONE[marker] == true
end

return M
