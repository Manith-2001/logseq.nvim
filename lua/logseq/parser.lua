--- Pure link parser (no vim.* calls so it stays maximally testable).
--- Supports [[wikilink]], #[[hash-wikilink]] and #hashtag, ordered by
--- position, with 1-based inclusive columns for link_under_cursor().
local M = {}

---@class LogseqLink
---@field text string link target text
---@field col_start integer 1-based start col of the match (at '[' or '#')
---@field col_end integer 1-based inclusive end col (at final ']' or tag end)
---@field kind string 'wikilink' | 'hash-wikilink' | 'hashtag'

--- Collect non-overlapping matches of one pattern. `taken` marks columns
--- already claimed by a higher-priority kind, so e.g. the [[..]] inside
--- #[[..]] (or a #tag inside [[..]]) is never double-reported.
---@param line string
---@param pat string Lua pattern with one capture (the target text)
---@param kind string
---@param taken table<integer, boolean>
---@param out LogseqLink[]
local function collect(line, pat, kind, taken, out)
  local init = 1
  while true do
    local s, e, text = line:find(pat, init)
    if not s then
      break
    end
    init = e + 1
    if not text:match('^%s*$') then
      local overlap = false
      for c = s, e do
        if taken[c] then
          overlap = true
          break
        end
      end
      if not overlap then
        for c = s, e do
          taken[c] = true
        end
        table.insert(out, { text = text, col_start = s, col_end = e, kind = kind })
      end
    end
  end
end

--- Return ordered links found in a single line. Non-string input yields {}.
---@param line string
---@return LogseqLink[]
function M.links_in_line(line)
  local links = {}
  if type(line) ~= 'string' then
    return links
  end
  local taken = {}
  collect(line, '#%[%[(.-)%]%]', 'hash-wikilink', taken, links)
  collect(line, '%[%[(.-)%]%]', 'wikilink', taken, links)
  collect(line, '#([%w_][%w_%-/]*)', 'hashtag', taken, links)
  table.sort(links, function(a, b)
    return a.col_start < b.col_start
  end)
  return links
end

--- Link containing 1-based byte col, or nil. Nil-safe on bad input.
--- Callers pass cursor col + 1 (nvim_win_get_cursor is 0-based).
---@param line string|nil
---@param col integer|nil
---@return LogseqLink|nil
function M.link_under_cursor(line, col)
  if type(line) ~= 'string' or type(col) ~= 'number' then
    return nil
  end
  for _, link in ipairs(M.links_in_line(line)) do
    if col >= link.col_start and col <= link.col_end then
      return link
    end
  end
  return nil
end

return M
