--- Pure graph-explorer layout (M6.2 local, M6.3 global): link-index data
--- in, lines + a line->entry map out. No buffer, window, keymap, or picker
--- logic lives here (that is lua/logseq/graph_view.lua); specs can assert
--- layout without any editor state.
--- Rendered lines are OUTPUT ONLY (audit VIEW-01): navigation identity
--- always comes from the map, never from parsing the text back.
local index_mod = require('logseq.index')

local M = {}

local MARK_EXISTS = '●'
local MARK_DANGLING = '○'
local PLACEHOLDER = '(none)'

--- One graph-entry display protocol (audit DRY-05): existing nodes show
--- `● title →F ←B` (out-links then backlinks), dangling nodes (file-less,
--- so never out-links) show `○ title ←B`. Shared by the global overview
--- and the picker formatter so counts/markers cannot diverge.
---@param title string
---@param fwd integer out-link count
---@param back integer backlink count
---@param exists boolean
---@return string
function M.entry_display(title, fwd, back, exists)
  if exists then
    return ('%s %s →%d ←%d'):format(MARK_EXISTS, title, fwd, back)
  end
  return ('%s %s ←%d'):format(MARK_DANGLING, title, back)
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

--- Append one section; every rendered entry line is recorded in map under
--- its buffer line number (string keys: b: vars round-trip through VimL).
---@param out string[] rendered lines (appended in place)
---@param map table<string, table> lnum -> {title=, path=, exists=}
---@param heading string section heading without the count
---@param idx LogseqGraphIndex
---@param titles string[] already-sorted titles
---@param show_dangling boolean
local function section(out, map, heading, idx, titles, show_dangling)
  local vis = shown(idx, titles, show_dangling)
  table.insert(out, ('%s (%d)'):format(heading, #vis))
  if #vis == 0 then
    table.insert(out, PLACEHOLDER)
    return
  end
  for _, t in ipairs(vis) do
    local node = idx.nodes[t]
    local exists = node ~= nil and node.exists
    table.insert(out, ((exists and MARK_EXISTS) or MARK_DANGLING) .. ' ' .. t)
    map[tostring(#out)] = {
      title = t,
      path = node ~= nil and node.path or nil,
      exists = exists == true,
    }
  end
end

--- Pure layout with map (local view): header + Linked/Backlinks sections
--- (+ `2 hops` at depth 2, i.e. neighbors exactly two edges away). Unknown
--- titles render as empty sections, never an error (a dangling center page
--- still shows its backlinks when other pages link it).
---@param idx LogseqGraphIndex
---@param title string center page title
---@param depth integer 1 or 2 (anything else clamps to 1)
---@param opts table|nil {show_dangling= (default true), graph_name=}
---@return string[] lines
---@return table<string, table> map buffer lnum -> entry {title=, path=, exists=}
function M.lines_with_map(idx, title, depth, opts)
  opts = opts or {}
  local show_dangling = opts.show_dangling ~= false
  depth = (depth == 2) and 2 or 1
  local out = {
    ('# %s · %s (depth %d)'):format(title, opts.graph_name or 'graph', depth),
    '',
  }
  local map = {}
  local fwd = index_mod.forward(idx, title)
  local back = index_mod.back(idx, title)
  section(out, map, '## Linked', idx, fwd, show_dangling)
  table.insert(out, '')
  section(out, map, '## Backlinks', idx, back, show_dangling)
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
    section(out, map, '## 2 hops', idx, hops, show_dangling)
  end
  return out, map
end

--- Pure layout, lines only: the plain-data view of lines_with_map for
--- callers/tests that want just the text.
---@param idx LogseqGraphIndex
---@param title string center page title
---@param depth integer 1 or 2 (anything else clamps to 1)
---@param opts table|nil {show_dangling= (default true), graph_name=}
---@return string[] lines
function M.lines(idx, title, depth, opts)
  local lines = M.lines_with_map(idx, title, depth, opts)
  return lines
end

--- Pure layout with map (global overview): stats header + Pages /
--- Journals / Dangling sections with per-entry counts. Dangling entries
--- hide with show_dangling=false and the Dangling count follows (like the
--- local sections). An empty graph renders empty sections, never an error.
---@param idx LogseqGraphIndex
---@param opts table|nil {show_dangling= (default true), graph_name=}
---@return string[] lines
---@return table<string, table> map buffer lnum -> entry {title=, path=, exists=}
function M.all_lines_with_map(idx, opts)
  opts = opts or {}
  local show_dangling = opts.show_dangling ~= false
  local stats = idx.stats or { pages = 0, journals = 0, dangling = 0, edges = 0 }
  local out = {
    ('# %s · graph overview'):format(opts.graph_name or 'graph'),
    '',
    ('%d pages · %d journals · %d dangling · %d edges'):format(
      stats.pages,
      stats.journals,
      stats.dangling,
      stats.edges
    ),
    '',
  }
  local map = {}
  local pages, journals, dangling = {}, {}, {}
  for _, title in ipairs(index_mod.titles(idx)) do
    local node = idx.nodes[title]
    if node ~= nil and node.kind == 'journal' then
      table.insert(journals, title)
    elseif node ~= nil and node.exists then
      table.insert(pages, title)
    else
      table.insert(dangling, title)
    end
  end
  local function global_section(heading, titles, hideable)
    local vis = titles
    if hideable and not show_dangling then
      vis = {}
    end
    table.insert(out, ('%s (%d)'):format(heading, #vis))
    if #vis == 0 then
      table.insert(out, PLACEHOLDER)
      return
    end
    for _, t in ipairs(vis) do
      local node = idx.nodes[t]
      local exists = node ~= nil and node.exists
      table.insert(
        out,
        M.entry_display(t, #index_mod.forward(idx, t), #index_mod.back(idx, t), exists == true)
      )
      map[tostring(#out)] = {
        title = t,
        path = node ~= nil and node.path or nil,
        exists = exists == true,
      }
    end
  end
  global_section('## Pages', pages, false)
  table.insert(out, '')
  global_section('## Journals', journals, false)
  table.insert(out, '')
  global_section('## Dangling', dangling, true)
  return out, map
end

--- Pure layout (global overview), lines only: the plain-data view of
--- all_lines_with_map for callers/tests that want just the text.
---@param idx LogseqGraphIndex
---@param opts table|nil {show_dangling= (default true), graph_name=}
---@return string[] lines
function M.all_lines(idx, opts)
  local lines = M.all_lines_with_map(idx, opts)
  return lines
end

return M
