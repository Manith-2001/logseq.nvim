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
local config = require('logseq.config')
local page = require('logseq.page')

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
---@field io table {unreadable = string[]} paths that could not be read

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

--- Read one file's lines. Unreadable files return nil + err instead of a
--- silent {} (audit IO-01); build collects them into idx.io.unreadable.
---@param path string
---@return string[]|nil lines
---@return string|nil err
local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then
    return nil, ('unreadable: %s'):format(path)
  end
  return lines, nil
end

--- Core builder over already-listed page items (shared by build and
--- build_guarded so the guarded path never lists the graph twice).
---@param items LogseqPageItem[]
---@return LogseqGraphIndex
local function build_from(items)
  ---@type table<string, table<string, boolean>>
  local fwd_sets = {}
  ---@type table<string, LogseqIndexNode>
  local nodes = {}
  local pages, journals = 0, 0
  local unreadable = {}

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
    -- CHANGED (IO-01): unreadable files are collected, not silently empty.
    local lines, err = read_lines(item.path)
    if lines == nil then
      table.insert(unreadable, item.path)
    else
      for _, line in ipairs(lines) do
        for _, link in ipairs(parser.links_in_line(line)) do
          local target = M.normalize(link.text)
          if target ~= nil and not page.is_namespace(target) then
            fwd_sets[item.title][target] = true
          end
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

  -- CHANGED: the IO report rides on the index value (single return, no
  -- churn at the many existing build() call sites).
  return {
    forward = forward,
    back = back,
    nodes = nodes,
    stats = { pages = pages, journals = journals, dangling = dangling, edges = edges },
    io = { unreadable = unreadable },
  }
end

--- Build the full link index for root. opts passes through to
--- graph.list_pages() ({pages_dir=, journals_dir=} overrides, used by tests).
--- Unreadable files are excluded from edges but listed in idx.io.unreadable
--- (audit IO-01) — callers decide whether to warn.
---@param root string absolute graph root
---@param opts table|nil
---@return LogseqGraphIndex
function M.build(root, opts)
  assert(type(root) == 'string' and root ~= '', 'index.build: root required')
  return build_from(graph.list_pages(root, opts))
end

--- Guarded build for EVERY interactive path (audit PERF-01): the size
--- policy lives at the index-construction boundary, not in selected
--- callers. Graphs over cfg.graph_max_files build nothing and return
--- nil + err; callers notify with M.too_large_message(). opts passes
--- through to graph.list_pages() like build().
---@param root string absolute graph root
---@param opts table|nil
---@return LogseqGraphIndex|nil idx nil when over the limit
---@return table|nil err { kind = 'too_large', count = integer, max = integer }
function M.build_guarded(root, opts)
  assert(type(root) == 'string' and root ~= '', 'index.build_guarded: root required')
  local items = graph.list_pages(root, opts)
  local max = config.get().graph_max_files
  if #items > max then
    return nil, { kind = 'too_large', count = #items, max = max }
  end
  return build_from(items), nil
end

--- Shared warning text for a too_large guard result: one policy message
--- used by the facade and the graph-view controller alike, so the guard
--- can never drift per-caller again.
---@param count integer
---@param max integer
---@return string
function M.too_large_message(count, max)
  return ('logseq.nvim: graph too large (%d files > %d graph_max_files); raise graph_max_files to explore it'):format(
    count,
    max
  )
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
