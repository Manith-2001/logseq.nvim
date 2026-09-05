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

---@class LogseqKnownGraph
---@field name string basename of the root dir (display only; matched by path)
---@field path string absolute root path

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

-- Active graph (M5.2): runtime override, NOT config. Persisted as a
-- single-line path in stdpath('data')/logseq.nvim/active, loaded lazily on
-- first get_active() and revalidated on every read (a graph deleted
-- mid-session simply stops resolving). Stale entries are ignored silently;
-- health (M5.4) surfaces them as a note.
local active_path = nil ---@type string|nil
local active_loaded = false
local state_file_override = nil ---@type string|nil test hook (hermetic specs)

---@return string path of the state file (override wins in specs)
local function state_file()
  if state_file_override then
    return state_file_override
  end
  return vim.fn.stdpath('data') .. '/logseq.nvim/active'
end

---@param dir any
---@return boolean true when dir is an existing, valid graph root
local function valid_active(dir)
  if type(dir) ~= 'string' or dir == '' then
    return false
  end
  local cfg = config.get()
  return vim.fn.isdirectory(dir) == 1 and is_root(dir, cfg.pages_dir, cfg.journals_dir)
end

---@param raw string|nil
---@return string|nil trimmed line, or nil when blank/missing
local function clean_line(raw)
  if type(raw) ~= 'string' then
    return nil
  end
  local line = raw:match('^%s*(.-)%s*$')
  return (line ~= '' and line or nil)
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

--- Scan cfg.graphs_dirs for graph roots (M5.1, multi-graph discovery).
--- Depth-limited downward walk: each scan dir is level 0, its children
--- level 1, up to cfg.graphs_depth. A dir matching is_root()
--- (logseq/config.edn, or pages/ + journals/ siblings) is recorded and
--- NOT descended into (a graph nested inside another resolves to the
--- outer one). Hidden (dot-) dirs are skipped, symlinks are not followed,
--- and missing scan dirs scan as empty — never an error.
--- On-demand only: called by the switch picker and health, never at startup.
---@return LogseqKnownGraph[] sorted by name, then path
function M.discover_graphs()
  local cfg = config.get()
  local dirs = cfg.graphs_dirs
  if type(dirs) ~= 'table' then
    dirs = {}
  end
  local maxdepth = cfg.graphs_depth
  if type(maxdepth) ~= 'number' or maxdepth < 0 then
    maxdepth = 2
  else
    maxdepth = math.floor(maxdepth)
  end
  local found = {}
  local seen = {}
  local function record(dir)
    if not seen[dir] then
      seen[dir] = true
      table.insert(found, { name = vim.fn.fnamemodify(dir, ':t'), path = dir })
    end
  end
  local function scan(dir, level)
    if is_root(dir, cfg.pages_dir, cfg.journals_dir) then
      record(dir)
      return
    end
    if level >= maxdepth or vim.fn.isdirectory(dir) == 0 then
      return
    end
    for name, ftype in vim.fs.dir(dir) do
      -- NB: vim.fs.dir yields libuv dirent types ('directory', not 'dir').
      -- 'link' is deliberately excluded: symlinks are not followed.
      if ftype == 'directory' and name:sub(1, 1) ~= '.' then
        scan(dir .. '/' .. name, level + 1)
      end
    end
  end
  for _, dir in ipairs(dirs) do
    if type(dir) == 'string' and dir ~= '' then
      scan(normalize(dir), 0)
    end
  end
  table.sort(found, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.path < b.path
  end)
  return found
end

--- Set the active graph by path or by discovered name (M5.2). A path wins
--- when it is an existing directory; otherwise the input is matched against
--- discovered graph basenames (exactly one match required). The choice is
--- validated (must be a live graph root) and persisted to the state file so
--- it survives restarts. Errors on blanks, non-roots, unknown names, and
--- ambiguous names — the switch picker (M5.3) only ever feeds valid paths.
---@param path_or_name string graph path or discovered basename
---@return string normalized absolute root path
function M.set_active(path_or_name)
  if type(path_or_name) ~= 'string' or clean_line(path_or_name) == nil then
    error('logseq.nvim: set_active needs a graph path or name', 0)
  end
  local input = clean_line(path_or_name) --[[@as string]]
  local path = nil ---@type string|nil
  if vim.fn.isdirectory(vim.fn.expand(input)) == 1 then
    path = normalize(input)
  else
    local matches = {}
    for _, known in ipairs(M.discover_graphs()) do
      if known.name == input then
        table.insert(matches, known.path)
      end
    end
    if #matches == 1 then
      path = matches[1]
    elseif #matches > 1 then
      error(
        ("logseq.nvim: ambiguous graph name '%s' matches: %s"):format(
          input,
          table.concat(matches, ', ')
        ),
        0
      )
    end
  end
  if not valid_active(path) then
    error(('logseq.nvim: not a graph: %s (see graphs_dirs)'):format(input), 0)
  end
  active_path = path --[[@as string]]
  active_loaded = true
  local file = state_file()
  vim.fn.mkdir(vim.fn.fnamemodify(file, ':h'), 'p')
  vim.fn.writefile({ active_path }, file)
  return active_path
end

--- Active graph root, or nil when none is set / the entry went stale
--- (missing dir, or no longer a root). Lazy-loads the state file on first
--- call; revalidates on every call. Never errors — stale entries are
--- ignored silently (health reports them, M5.4).
---@return string|nil absolute root path
function M.get_active()
  if not active_loaded then
    active_loaded = true
    local file = state_file()
    if vim.fn.filereadable(file) == 1 then
      active_path = clean_line(vim.fn.readfile(file)[1])
    end
  end
  if not valid_active(active_path) then
    active_path = nil
  end
  return active_path
end

--- Forget the active graph (memory + state file). No-op when unset.
function M.clear_active()
  active_path = nil
  active_loaded = true
  local file = state_file()
  if vim.fn.filereadable(file) == 1 or vim.fn.isdirectory(file) == 1 then
    vim.fn.delete(file)
  end
end

--- Test hook: redirect the state file so specs stay hermetic (never touch
--- the real stdpath). Resets in-memory state, like a fresh session.
--- Pass nil to restore the default location.
---@param path string|nil
function M._set_state_file(path)
  state_file_override = path
  active_path = nil
  active_loaded = false
end

--- Test hook: drop in-memory state while keeping the state file, so the
--- next get_active() re-reads from disk (simulates a restart).
function M._reset_active()
  active_path = nil
  active_loaded = false
end

return M
