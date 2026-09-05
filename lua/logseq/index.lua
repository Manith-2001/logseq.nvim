--- Link index (M6.1): forward/back adjacency over pages + journals.
--- Built from graph.list_pages() + parser.links_in_line() per line.
--- Titles trim surrounding whitespace (like page.title_to_path) and keep
--- spaces/case verbatim. Namespace targets containing `/` are skipped:
--- the facade refuses them (init.check_no_namespace), so the index must
--- not advertise an edge that can never be followed. Self-loops are kept
--- in forward[] but excluded from back[] (a page is not its own backlink).
--- Dangling targets (no file) are kept as nodes with kind 'dangling'.
--- Missing dirs scan as empty (like list_pages), never an error.
local graph = require('logseq.graph')
local parser = require('logseq.parser')

local M = {}

---@class LogseqIndexNode
---@field title string page title
---@field kind string 'page' | 'journal' | 'dangling'
---@field path string|nil absolute file path (nil for dangling)
---@field exists boolean true when the file exists

---@class LogseqGraphIndex
---@field forward table<string, string[]> src title -> sorted dst titles
---@field back table<string, string[]> dst title -> sorted src titles
---@field nodes table<string, LogseqIndexNode> every known title
---@field stats table edge/node counts {pages, journals, dangling, edges}
---@field occurrences LogseqOccurrence[] per-link rows, no dedup, sorted by (src, lnum)

---@class LogseqOccurrence
---@field src string source page title holding the link
---@field dst string normalized link target title
---@field lnum integer 1-based line number in the source file
---@field line string raw source line text

--- Trim surrounding whitespace like Logseq page names. Returns nil for
--- non-string or blank input (blank links like `[[]]` are never edges).
---@param text any
---@return string|nil
function M.normalize(text)
  if type(text) ~= 'string' then
    return nil
  end
  local name = text:match('^%s*(.-)%s*$')
  if name == nil or name == '' then
    return nil
  end
  return name
end

---@param title string
---@return boolean true when the title is namespace-scoped (contains `/`)
local function is_namespace(title)
  return title:find('/', 1, true) ~= nil
end

---@param path string
---@return string[] lines, or {} when unreadable
local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then
    return {}
  end
  return lines
end

--- Build the full link index for root. opts passes through to
--- graph.list_pages() ({pages_dir=, journals_dir=} overrides, used by tests).
---@param root string absolute graph root
---@param opts table|nil
---@return LogseqGraphIndex
function M.build(root, opts)
  assert(type(root) == 'string' and root ~= '', 'index.build: root required')
  local items = graph.list_pages(root, opts)

  ---@type table<string, table<string, boolean>>
  local fwd_sets = {}
  ---@type table<string, LogseqIndexNode>
  local nodes = {}
  ---@type LogseqOccurrence[]
  local occurrences = {}
  local pages, journals = 0, 0

  for _, item in ipairs(items) do
    if nodes[item.title] == nil then
      nodes[item.title] = { title = item.title, kind = item.kind, path = item.path, exists = true }
      if item.kind == 'journal' then
        journals = journals + 1
      else
        pages = pages + 1
      end
    end
    if fwd_sets[item.title] == nil then
      fwd_sets[item.title] = {}
    end
    for lnum, line in ipairs(read_lines(item.path)) do
      for _, link in ipairs(parser.links_in_line(line)) do
        local target = M.normalize(link.text)
        if target ~= nil and not is_namespace(target) then
          fwd_sets[item.title][target] = true
          table.insert(occurrences, { src = item.title, dst = target, lnum = lnum, line = line })
        end
      end
    end
  end

  -- Dangling targets become nodes so the view can list them as new pages.
  for _, dsts in pairs(fwd_sets) do
    for dst, _ in pairs(dsts) do
      if nodes[dst] == nil then
        nodes[dst] = { title = dst, kind = 'dangling', path = nil, exists = false }
      end
    end
  end

  ---@type table<string, string[]>
  local forward = {}
  ---@type table<string, table<string, boolean>>
  local back_sets = {}
  for title, _ in pairs(nodes) do
    forward[title] = {}
    back_sets[title] = {}
  end

  local edges = 0
  for src, dsts in pairs(fwd_sets) do
    for dst, _ in pairs(dsts) do
      table.insert(forward[src], dst)
      edges = edges + 1
      if dst ~= src then
        back_sets[dst][src] = true
      end
    end
  end

  ---@type table<string, string[]>
  local back = {}
  for title, srcs in pairs(back_sets) do
    back[title] = {}
    for src, _ in pairs(srcs) do
      table.insert(back[title], src)
    end
    table.sort(back[title])
  end
  for _, dsts in pairs(forward) do
    table.sort(dsts)
  end

  local dangling = 0
  for _, node in pairs(nodes) do
    if node.kind == 'dangling' then
      dangling = dangling + 1
    end
  end

  table.sort(occurrences, function(a, b)
    if a.src ~= b.src then
      return a.src < b.src
    end
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    if a.dst ~= b.dst then
      return a.dst < b.dst
    end
    return a.line < b.line
  end)

  return {
    forward = forward,
    back = back,
    nodes = nodes,
    stats = { pages = pages, journals = journals, dangling = dangling, edges = edges },
    occurrences = occurrences,
  }
end

--- Sorted forward links of title, or {} when unknown. Returns a copy.
---@param index LogseqGraphIndex
---@param title string
---@return string[]
function M.forward(index, title)
  local dsts = index.forward[title]
  if type(dsts) ~= 'table' then
    return {}
  end
  local out = {}
  for i, dst in ipairs(dsts) do
    out[i] = dst
  end
  return out
end

--- Sorted backlinks of title, or {} when unknown. Returns a copy.
---@param index LogseqGraphIndex
---@param title string
---@return string[]
function M.back(index, title)
  local srcs = index.back[title]
  if type(srcs) ~= 'table' then
    return {}
  end
  local out = {}
  for i, src in ipairs(srcs) do
    out[i] = src
  end
  return out
end

--- Back-context occurrence rows for dst, sorted by (src, lnum).
--- Self-loops (src == dst) are excluded, mirroring back[]. The stored
--- list keeps them so a forward-context lookup still sees the edge;
--- only this accessor filters. Blank/namespace targets never reach the
--- stored list (same exclusion as forward[]). Unknown or non-string dst
--- yields {}. Returns copies so callers cannot mutate the index.
---@param index LogseqGraphIndex
---@param dst string
---@return LogseqOccurrence[]
function M.occurrences(index, dst)
  if type(dst) ~= 'string' then
    return {}
  end
  local stored = index.occurrences
  if type(stored) ~= 'table' then
    return {}
  end
  local out = {}
  for _, occ in ipairs(stored) do
    if occ.dst == dst and occ.src ~= dst then
      table.insert(out, { src = occ.src, dst = occ.dst, lnum = occ.lnum, line = occ.line })
    end
  end
  table.sort(out, function(a, b)
    if a.src ~= b.src then
      return a.src < b.src
    end
    return a.lnum < b.lnum
  end)
  return out
end

--- Sorted known titles (pages + journals + dangling).
---@param index LogseqGraphIndex
---@return string[]
function M.titles(index)
  local out = {}
  for title, _ in pairs(index.nodes) do
    table.insert(out, title)
  end
  table.sort(out)
  return out
end

--- BFS over the union of forward + back edges up to depth (default 1).
--- Returns sorted titles within depth, excluding the center title itself.
--- Unknown titles and depth < 1 yield {}.
---@param index LogseqGraphIndex
---@param title string
---@param depth integer|nil
---@return string[]
function M.neighbors(index, title, depth)
  depth = depth or 1
  if type(depth) ~= 'number' or depth < 1 then
    return {}
  end
  depth = math.floor(depth)
  if index.nodes[title] == nil then
    return {}
  end
  local seen = { [title] = true }
  local frontier = { title }
  for _ = 1, depth do
    local next_frontier = {}
    for _, cur in ipairs(frontier) do
      for _, nxt in ipairs(index.forward[cur] or {}) do
        if not seen[nxt] then
          seen[nxt] = true
          table.insert(next_frontier, nxt)
        end
      end
      for _, nxt in ipairs(index.back[cur] or {}) do
        if not seen[nxt] then
          seen[nxt] = true
          table.insert(next_frontier, nxt)
        end
      end
    end
    frontier = next_frontier
    if #frontier == 0 then
      break
    end
  end
  seen[title] = nil
  local out = {}
  for t, _ in pairs(seen) do
    table.insert(out, t)
  end
  table.sort(out)
  return out
end

return M
