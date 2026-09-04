--- Graph root detection + page listing (M1).
--- Discovery findings (§8.1–§8.2, reference graph ~/dev/notes_logseq):
--- - No active `:file-name-format` in logseq/config.edn (only commented
---   defaults) and no namespace (`___`) files on disk → titles keep
---   spaces/case verbatim. `/` (namespace) mapping deferred to M4 per PLAN.
--- - Journals use `%Y_%m_%d` (e.g. 2026_08_27.md), matching the commented
---   default `:journal/file-name-format "yyyy_MM_dd"`.
local config = require('logseq.config')

local M = {}

---@class LogseqPageItem
---@field title string page title (filename without .md)
---@field path string absolute file path
---@field kind string 'page' | 'journal'

--- Normalize to an absolute path without trailing slash. Expands `~`
--- so the documented `graph_path = '~/dev/notes_logseq'` style works.
---@param dir string
---@return string
local function normalize(dir)
  local abs = vim.fn.fnamemodify(vim.fn.expand(dir), ':p'):gsub('/+$', '')
  if abs == '' then
    return '/'
  end
  return abs
end

--- True when dir looks like a file-graph root: has logseq/config.edn,
--- or pages/ + journals/ siblings.
---@param dir string
---@param pages_dir string
---@param journals_dir string
---@return boolean
local function is_root(dir, pages_dir, journals_dir)
  if vim.fn.filereadable(dir .. '/logseq/config.edn') == 1 then
    return true
  end
  return vim.fn.isdirectory(dir .. '/' .. pages_dir) == 1
    and vim.fn.isdirectory(dir .. '/' .. journals_dir) == 1
end

--- Walk up from start (file or dir) to the nearest graph root.
---@param start string
---@param pages_dir string
---@param journals_dir string
---@return string|nil
local function walk_up(start, pages_dir, journals_dir)
  local dir = vim.fn.fnamemodify(vim.fn.expand(start), ':p')
  if vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  local prev = nil
  while dir ~= '' and dir ~= prev do
    local norm = dir:gsub('/+$', '')
    if norm == '' then
      norm = '/'
    end
    if is_root(norm, pages_dir, journals_dir) then
      return norm
    end
    prev = dir
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  return nil
end

--- Resolve the graph root. Order: explicit `config.graph_path` (strict —
--- a configured-but-missing path returns nil rather than silently using
--- some other graph) → upward search from startpath (default: current
--- buffer, else cwd). Returns nil when nothing is found.
---@param startpath string|nil file or dir to search upward from
---@return string|nil absolute root path
function M.find_root(startpath)
  local cfg = config.get()
  if type(cfg.graph_path) == 'string' and cfg.graph_path ~= '' then
    local norm = normalize(cfg.graph_path)
    if vim.fn.isdirectory(norm) == 1 then
      return norm
    end
    return nil
  end
  if startpath == nil or startpath == '' then
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname ~= '' then
      startpath = bufname
    else
      startpath = vim.fn.getcwd()
    end
  end
  return walk_up(startpath, cfg.pages_dir, cfg.journals_dir)
end

--- Nearest graph root at-or-above path, ignoring config.graph_path.
--- For buffer-scoped questions ("is THIS file in a graph?") where the
--- global override would give the wrong answer — e.g. after/ftplugin
--- must not treat an unrelated markdown file as a graph page just
--- because graph_path is set. Returns nil for '' / missing paths.
---@param path string|nil file or dir
---@return string|nil absolute root path
function M.find_root_from(path)
  if type(path) ~= 'string' or path == '' then
    return nil
  end
  local cfg = config.get()
  return walk_up(path, cfg.pages_dir, cfg.journals_dir)
end

--- List pages + journals (non-recursive, v0.1), sorted by title.
--- Excludes hidden (dot-) files. Missing dirs scan as empty, not an error.
---@param root string absolute graph root
---@param opts table|nil {pages_dir=, journals_dir=} overrides
---@return LogseqPageItem[]
function M.list_pages(root, opts)
  opts = opts or {}
  local cfg = config.get()
  local items = {}
  local function scan(sub, kind)
    local dir = root .. '/' .. sub
    if vim.fn.isdirectory(dir) == 0 then
      return
    end
    for name, ftype in vim.fs.dir(dir) do
      if ftype == 'file' and name:sub(-3) == '.md' and name:sub(1, 1) ~= '.' then
        table.insert(items, {
          title = name:sub(1, -4),
          path = dir .. '/' .. name,
          kind = kind,
        })
      end
    end
  end
  scan(opts.pages_dir or cfg.pages_dir, 'page')
  scan(opts.journals_dir or cfg.journals_dir, 'journal')
  table.sort(items, function(a, b)
    return a.title < b.title
  end)
  return items
end

return M
