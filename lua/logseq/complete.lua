--- [[ ]] completion core (M10.0 skeleton): prefix -> ranked page titles.
--- Pure find_start()/rank() plus a thin complete()/omnifunc() edge.
--- M10.1 fills in the real detection, ranking, and data paths; this
--- revision only fixes the module shape so the M10.0 contract spec can
--- load it and fail red by design.
local M = {}

---@class LogseqCompleteMatch
---@field startcol integer 1-based col where the prefix starts
---@field prefix string text after [[ / #[[ / # (may be '')
---@field kind string 'wikilink' | 'hash-wikilink' | 'hashtag'

--- Detect an *open* completion context at the 1-based cursor col: an
--- unclosed `[[prefix`, `#[[prefix`, or `#prefix` before the cursor.
--- Closed `[[..]]` at the cursor and plain text yield nil. Nil-safe.
---@param line string|nil
---@param col integer|nil 1-based cursor col (next char would insert here)
---@return LogseqCompleteMatch|nil
function M.find_start(line, col)
  return nil
end

--- Rank titles against prefix (case-insensitive prefix > substring >
--- fuzzy-subsequence, alphabetical within tier). Returns a sorted copy;
--- never mutates the input.
---@param prefix string
---@param titles string[]
---@return string[] sorted copy
function M.rank(prefix, titles)
  return {}
end

--- Complete prefix against the graph: fresh list_pages() titles plus the
--- cached dangling titles from index.build() (existing before dangling).
--- opts.items injects items directly (used by tests). Nil-safe.
---@param prefix string
---@param opts table|nil ({root=, items=} overrides)
---@return table[] items {title=, kind=, path=|nil, exists=}
function M.complete(prefix, opts)
  return {}
end

--- Standard omnifunc wrapping find_start()/complete(): findstart=1
--- returns the prefix startcol (or -1 outside a context), findstart=0
--- returns the shaped popup items for base.
---@param findstart integer 1 when locating the start, 0 when completing
---@param base string prefix when completing
---@return integer|table[]
function M.omnifunc(findstart, base)
  if findstart == 1 then
    return -1
  end
  return {}
end

return M
