--- [[ ]] completion core (M10.1): prefix -> ranked page titles.
--- Pure find_start()/rank() plus a thin complete()/omnifunc() edge.
--- list_pages() stays fresh per popup; the dangling titles from
--- index.build() are cached per root (M10.2) until invalidate() drops
--- them (BufWritePost *.md / DirChanged wiring in plugin/logseq.lua).
local graph = require('logseq.graph')
local index_mod = require('logseq.index')
local config = require('logseq.config')

local M = {}

---@class LogseqCompleteMatch
---@field startcol integer 1-based col where the prefix starts
---@field prefix string text after [[ / #[[ / # (may be '')
---@field kind string 'wikilink' | 'hash-wikilink' | 'hashtag'

---@class LogseqCompleteItem
---@field title string page title, verbatim
---@field kind string 'page' | 'journal' | 'dangling'
---@field path string|nil absolute file path (nil for dangling)
---@field exists boolean true when the file exists

--- Last plain occurrence of needle in s, or nil. Plain (non-pattern)
--- search: titles and lines may hold magic chars (`%`, `-`, ...).
---@param s string
---@param needle string
---@return integer|nil 1-based index of the last occurrence
local function last_find(s, needle)
  local last, from = nil, 1
  while true do
    local hit = s:find(needle, from, true)
    if hit == nil then
      return last
    end
    last = hit
    from = hit + 1
  end
end

--- True when tail cannot be a #tag prefix: tags end at whitespace or
--- brackets (so `[[a#b]]` and `#ml x` at the cursor are not contexts).
---@param tail string text after the `#`
---@return boolean
local function hashtag_closed(tail)
  return tail:find('[%s%[%]]') ~= nil
end

--- Detect an *open* completion context at the 1-based cursor col: an
--- unclosed `[[prefix`, `#[[prefix`, or `#prefix` before the cursor.
--- The last `[[` wins (so `[[A]] [[m` completes `m`); a `]]` between it
--- and the cursor means closed, and detection falls through to `#tag`.
--- A `#` only opens a tag after start-of-line or a non-word char, so
--- `C#` never completes. Closed `[[..]]` and plain text yield nil.
--- Nil-safe; byte cols, matching the cursor and omnifunc conventions.
---@param line string|nil
---@param col integer|nil 1-based cursor col (next char would insert here)
---@return LogseqCompleteMatch|nil
function M.find_start(line, col)
  if type(line) ~= 'string' or type(col) ~= 'number' then
    return nil
  end
  local before = line:sub(1, math.floor(col) - 1)
  local open = last_find(before, '[[')
  if open ~= nil and not before:sub(open + 2):find(']]', 1, true) then
    local kind = before:sub(open - 1, open - 1) == '#' and 'hash-wikilink' or 'wikilink'
    return { startcol = open + 2, prefix = before:sub(open + 2), kind = kind }
  end
  local hash = last_find(before, '#')
  if hash ~= nil then
    local tail = before:sub(hash + 1)
    local prev = before:sub(hash - 1, hash - 1)
    if not hashtag_closed(tail) and tail:sub(1, 2) ~= '[[' and prev:find('%w') == nil then
      return { startcol = hash + 1, prefix = tail, kind = 'hashtag' }
    end
  end
  return nil
end

--- True when every char of needle appears in hay in order
--- (case-folded by the caller). Empty needle always matches.
---@param hay string
---@param needle string
---@return boolean
local function fuzzy(hay, needle)
  local pos = 1
  for i = 1, #needle do
    local hit = hay:find(needle:sub(i, i), pos, true)
    if hit == nil then
      return false
    end
    pos = hit + 1
  end
  return true
end

--- Rank titles against prefix (case-insensitive prefix > substring >
--- fuzzy-subsequence, alphabetical within tier; non-matches dropped).
--- An empty prefix ranks every title tier-1 (empty `[[` offers all).
--- Returns a sorted copy; never mutates the input. Nil-safe.
---@param prefix string|nil
---@param titles string[]|nil
---@return string[] sorted copy
function M.rank(prefix, titles)
  if type(titles) ~= 'table' then
    return {}
  end
  local needle = (type(prefix) == 'string' and prefix or ''):lower()
  local scored = {}
  for _, title in ipairs(titles) do
    if type(title) == 'string' then
      local folded = title:lower()
      local tier = nil
      if folded:sub(1, #needle) == needle then
        tier = 1
      elseif folded:find(needle, 1, true) ~= nil then
        tier = 2
      elseif fuzzy(folded, needle) then
        tier = 3
      end
      if tier ~= nil then
        table.insert(scored, { title = title, tier = tier, key = folded })
      end
    end
  end
  table.sort(scored, function(a, b)
    if a.tier ~= b.tier then
      return a.tier < b.tier
    end
    if a.key ~= b.key then
      return a.key < b.key
    end
    return a.title < b.title
  end)
  local out = {}
  for i, entry in ipairs(scored) do
    out[i] = entry.title
  end
  return out
end

--- Rank one block of items (existing or dangling) and keep item shape.
---@param prefix string
---@param block LogseqCompleteItem[]
---@return LogseqCompleteItem[]
local function order_block(prefix, block)
  local titles, by_title = {}, {}
  for i, item in ipairs(block) do
    titles[i] = item.title
    by_title[item.title] = item
  end
  local out = {}
  for _, title in ipairs(M.rank(prefix, titles)) do
    table.insert(out, by_title[title])
  end
  return out
end

--- Per-root cache of dangling items (M10.2): index.build() is reused
--- until invalidate() drops it. Roots already warned as over
--- graph_max_files warn once per cache lifetime; invalidate() resets so
--- a shrunk graph warns afresh.
---@type table<string, LogseqCompleteItem[]>
local dangling_cache = {}
---@type table<string, boolean>
local warned_big = {}

--- Drop the completion cache: one root, or everything when root is nil.
--- Called by the BufWritePost/DirChanged wiring and safe anytime (lazy
--- rebuild on the next popup).
---@param root string|nil
function M.invalidate(root)
  if root == nil then
    dangling_cache = {}
    warned_big = {}
    return
  end
  dangling_cache[root] = nil
  warned_big[root] = nil
end

--- Split an item list into existing + dangling-shaped blocks,
--- skipping malformed entries. Injected opts.items take this path.
---@param list LogseqCompleteItem[]
---@return LogseqCompleteItem[], LogseqCompleteItem[]
local function split_items(list)
  local have, missing = {}, {}
  for _, item in ipairs(list) do
    if type(item) == 'table' and type(item.title) == 'string' then
      if item.exists then
        table.insert(have, item)
      else
        table.insert(missing, item)
      end
    end
  end
  return have, missing
end

--- Complete prefix against the graph: fresh list_pages() titles plus the
--- cached dangling titles from index.build(), existing ranked before
--- dangling. Graphs over graph_max_files fall back to pages only (one
--- WARN per root, like guard_size). opts.root overrides root resolution
--- (used by tests); opts.items injects items directly (used by tests);
--- opts.limit truncates after ranking (the config completion_limit
--- arrives this way). Nil-safe.
---@param prefix string|nil
---@param opts table|nil ({root=, items=, limit=} overrides)
---@return LogseqCompleteItem[]
function M.complete(prefix, opts)
  opts = opts or {}
  local have, missing
  if opts.items ~= nil then
    if type(opts.items) ~= 'table' then
      return {}
    end
    have, missing = split_items(opts.items)
  else
    local root = opts.root
    if type(root) ~= 'string' or root == '' then
      root = graph.find_root()
    end
    if type(root) ~= 'string' or root == '' then
      return {}
    end
    have, missing = {}, {}
    local seen = {}
    local pages = graph.list_pages(root)
    for _, page in ipairs(pages) do
      if type(page.title) == 'string' and not seen[page.title] then
        seen[page.title] = true
        table.insert(
          have,
          { title = page.title, kind = page.kind, path = page.path, exists = true }
        )
      end
    end
    if #pages > config.get().graph_max_files then
      if not warned_big[root] then
        warned_big[root] = true
        vim.notify(
          ('logseq.nvim: graph too large (%d files > %d graph_max_files); completion offers pages only, dangling refs hidden'):format(
            #pages,
            config.get().graph_max_files
          ),
          vim.log.levels.WARN
        )
      end
    else
      local cached = dangling_cache[root]
      if cached == nil then
        cached = {}
        local ok, idx = pcall(index_mod.build, root)
        if ok and idx ~= nil and type(idx.nodes) == 'table' then
          for title, node in pairs(idx.nodes) do
            if not seen[title] and type(node) == 'table' and node.exists == false then
              seen[title] = true
              table.insert(cached, { title = title, kind = 'dangling', path = nil, exists = false })
            end
          end
        end
        dangling_cache[root] = cached
      end
      for _, item in ipairs(cached) do
        table.insert(missing, item)
      end
    end
  end
  local needle = type(prefix) == 'string' and prefix or ''
  local out = order_block(needle, have)
  for _, item in ipairs(order_block(needle, missing)) do
    table.insert(out, item)
  end
  local limit = opts.limit
  if type(limit) == 'number' and limit >= 0 then
    while #out > math.floor(limit) do
      table.remove(out)
    end
  end
  return out
end

--- Popup menu text for an item: `● page` / `● journal` for files,
--- `○ new` for dangling titles (matches the M10 ranking note).
---@param item LogseqCompleteItem
---@return string
function M.menu(item)
  if item.exists then
    return '● ' .. item.kind
  end
  return '○ new'
end

--- Current buffer line + 1-based cursor col, or nil outside a buffer.
---@return string|nil, integer|nil
local function cursor_context()
  local ok_line, line = pcall(vim.api.nvim_get_current_line)
  local ok_cur, cur = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok_line or not ok_cur then
    return nil, nil
  end
  return line, cur[2] + 1
end

--- Shaped core items for the current buffer context, or {} outside one.
--- Shared by omnifunc() and the cmp/blink sources (M10.3) so manual,
--- auto, and framework paths complete identically.
---@return LogseqCompleteItem[]
function M.complete_at_cursor()
  local line, col = cursor_context()
  if line == nil or col == nil then
    return {}
  end
  local match = M.find_start(line, col)
  if match == nil then
    return {}
  end
  return M.complete(match.prefix, { limit = config.get().completion_limit })
end

--- Standard omnifunc wrapping find_start()/complete(): findstart=1
--- returns the 0-based prefix col (or -1 outside a context), findstart=0
--- returns `{word=, menu=}` popup dicts for the re-derived prefix (the
--- passed base is ignored so a stale base can never mistarget).
--- Insertion replaces startcol..cursor only and never appends `]]`, so a
--- trailing `]]` on the line cannot double up (no `]]]]`).
---@param findstart integer 1 when locating the start, 0 when completing
---@param base string prefix when completing (ignored, re-derived)
---@return integer|table[]
function M.omnifunc(findstart, base)
  local line, col = cursor_context()
  if line == nil or col == nil then
    return findstart == 1 and -1 or {}
  end
  local match = M.find_start(line, col)
  if match == nil then
    return findstart == 1 and -1 or {}
  end
  if findstart == 1 then
    return match.startcol - 1
  end
  local out = {}
  for _, item in ipairs(M.complete_at_cursor()) do
    table.insert(out, { word = item.title, menu = M.menu(item) })
  end
  return out
end

--- Feed <C-x><C-o> as typed keys (noremap): the auto-popup re-enters
--- through omnifunc(), so manual and auto share one path.
local function feed_omni()
  local keys = vim.api.nvim_replace_termcodes('<C-x><C-o>', true, false, true)
  vim.api.nvim_feedkeys(keys, 'n', false)
end

--- Fire one auto-popup when the cursor sits in an open `[[` / `#[[` /
--- `#` context (the InsertCharPre wiring + completion_auto gate live in
--- after/ftplugin/markdown.lua). Guards: a visible popup, non-insert
--- mode, and no context all decline. trigger is a test seam (default
--- feeds omni).
---@param trigger function|nil
---@return boolean true when a popup was triggered
function M.auto_popup(trigger)
  if vim.fn.pumvisible() ~= 0 then
    return false
  end
  if vim.fn.mode() ~= 'i' then
    return false
  end
  local line, col = cursor_context()
  if line == nil or col == nil then
    return false
  end
  if M.find_start(line, col) == nil then
    return false
  end
  local fire = trigger or feed_omni
  fire()
  return true
end

return M
