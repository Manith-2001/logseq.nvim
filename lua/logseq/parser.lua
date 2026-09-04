--- Pure link parser (no vim.* calls so it stays maximally testable).
--- M0: minimal [[..]] support so the harness has one green case.
--- M2 expands this to #[[..]], #tag, multi-link lines, link_under_cursor.
local M = {}

---@class LogseqLink
---@field text string link target text
---@field col_start integer 1-based start col of the match (at '[' or '#')
---@field col_end integer 1-based inclusive end col (at final ']' or tag end)
---@field kind string 'wikilink' (M2 adds 'hash-wikilink', 'hashtag')

--- Return ordered links found in a single line (currently [[..]] only).
---@param line string
---@return LogseqLink[]
function M.links_in_line(line)
  local links = {}
  if type(line) ~= 'string' then
    return links
  end
  local init = 1
  while true do
    local s, e, text = line:find('%[%[(.-)%]%]', init)
    if not s then
      break
    end
    table.insert(links, { text = text, col_start = s, col_end = e, kind = 'wikilink' })
    init = e + 1
  end
  return links
end

return M
