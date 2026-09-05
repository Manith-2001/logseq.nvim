---@class LogseqConfig
---@field graph_path string|nil absolute path to graph root (nil = auto-detect)
---@field pages_dir string default 'pages'
---@field journals_dir string default 'journals'
---@field journal_format string os.date format, default '%Y_%m_%d'
---@field picker string 'telescope' (with vim.ui.select fallback)
---@field graphs_dirs string[] parent dirs scanned for graphs (M5, default {})
---@field graphs_depth integer max levels below each scan dir (M5, default 2)
---@field graph_depth integer explorer depth for :LogseqGraph (M6.2, default 1)
---@field graph_max_files integer max files indexed synchronously (M6.2, default 2000)

local M = {}

---@type LogseqConfig
local defaults = {
  graph_path = nil,
  pages_dir = 'pages',
  journals_dir = 'journals',
  journal_format = '%Y_%m_%d',
  picker = 'telescope',
  graphs_dirs = {},
  graphs_depth = 2,
  graph_depth = 1,
  graph_max_files = 2000,
}

--- Explicit opts from setup() calls (highest precedence layer).
--- Stored separately from vim.g.logseq so get() can merge the live
--- g: value on every call; setup() is therefore optional, never required.
---@type table
local explicit_opts = {}

---@type string[] unknown keys seen across setup() calls (surfaced via health)
local unknown_keys = {}

-- NB: graph_path defaults to nil, and { k = nil } stores no key in Lua,
-- so key presence must come from this explicit set, not defaults[k].
local known_keys = {
  graph_path = true,
  pages_dir = true,
  journals_dir = true,
  journal_format = true,
  picker = true,
  graphs_dirs = true,
  graphs_depth = true,
  graph_depth = true,
  graph_max_files = true,
}

local function warn_unknown(opts)
  for k, _ in pairs(opts or {}) do
    if not known_keys[k] and not vim.tbl_contains(unknown_keys, k) then
      table.insert(unknown_keys, k)
    end
  end
end

--- Merge user opts over defaults (+ vim.g.logseq base). Idempotent, 0..n calls.
--- setup() is optional: get() already layers vim.g.logseq over defaults,
--- so a bare `vim.g.logseq = {...}` (or nothing at all) is a valid config.
---@param opts LogseqConfig|nil
function M.setup(opts)
  opts = opts or {}
  warn_unknown(opts)
  if type(vim.g.logseq) == 'table' then
    warn_unknown(vim.g.logseq)
  end
  explicit_opts = vim.deepcopy(opts)
  local current = M.get()
  pcall(vim.validate, {
    graph_path = { current.graph_path, { 'string', 'nil' } },
    pages_dir = { current.pages_dir, 'string' },
    journals_dir = { current.journals_dir, 'string' },
    journal_format = { current.journal_format, 'string' },
    picker = { current.picker, 'string' },
    graphs_dirs = { current.graphs_dirs, 'table' },
    graphs_depth = { current.graphs_depth, 'number' },
    graph_depth = { current.graph_depth, 'number' },
    graph_max_files = { current.graph_max_files, 'number' },
  })
  return current
end

--- Read-only snapshot of effective config, recomputed per call so a bare
--- vim.g.logseq (no setup() call) is honored. Precedence, low to high:
--- defaults < vim.g.logseq < setup(opts).
---@return LogseqConfig
function M.get()
  local merged = vim.deepcopy(defaults)
  local g = vim.g.logseq
  if type(g) == 'table' then
    merged = vim.tbl_deep_extend('force', merged, g)
  end
  merged = vim.tbl_deep_extend('force', merged, explicit_opts)
  -- List values replace wholesale: tbl_deep_extend merges arrays index-wise
  -- ({'a','b'} + {'c'} -> {'c','b'}), which is never the intent. The highest
  -- layer defining the key wins outright.
  if explicit_opts.graphs_dirs ~= nil then
    merged.graphs_dirs = vim.deepcopy(explicit_opts.graphs_dirs)
  elseif type(g) == 'table' and g.graphs_dirs ~= nil then
    merged.graphs_dirs = vim.deepcopy(g.graphs_dirs)
  end
  return merged
end

--- Unknown keys accumulated for health.lua to report (not a hard error).
---@return string[]
function M.unknown_keys()
  return vim.deepcopy(unknown_keys)
end

function M._defaults()
  return vim.deepcopy(defaults)
end

function M._reset()
  explicit_opts = {}
  unknown_keys = {}
end

return M
