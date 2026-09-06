---@class LogseqConfig
---@field graph_path string|nil absolute path to graph root (nil = auto-detect)
---@field pages_dir string default 'pages'
---@field journals_dir string default 'journals'
---@field journal_format string os.date format, default '%Y_%m_%d'
---@field graphs_dirs string[] parent dirs scanned for graphs (M5, default {})
---@field graphs_depth integer max levels below each scan dir (M5, default 2)
---@field graph_depth integer explorer depth for :LogseqGraph (M6.2, default 1)
---@field graph_max_files integer max files indexed synchronously (M6.2, default 2000)
---@field completion_auto boolean auto-popup [[ ]] completion while typing (M10.2, default true)
---@field completion_limit integer max popup items (M10.2, default 50)
---@field todo_cycles string[][] marker chains for :LogseqCycleTodo, last wraps to first (M8)

local markers = require('logseq.markers')

local M = {}

--- One declarative row per option (audit DRY-02): default, type, optional
--- semantic range, and wholesale-list merge behavior all live HERE. Adding
--- an option = adding one row; known keys, defaults, and validation derive
--- from this table, so a key can no longer be defaulted but unknown,
--- validated but unused, or merged with the wrong list semantics.
---@class LogseqSchemaRow
---@field default any
---@field type string vim type name; a trailing '?' allows nil
---@field list boolean|nil true when array values replace wholesale across layers
---@field range fun(v:any): string|nil optional semantic check (nil = ok)
local schema = {
  graph_path = { default = nil, type = 'string?' },
  pages_dir = { default = 'pages', type = 'string' },
  journals_dir = { default = 'journals', type = 'string' },
  journal_format = { default = '%Y_%m_%d', type = 'string' },
  graphs_dirs = {
    default = {},
    type = 'table',
    list = true,
    range = function(v)
      for i, dir in ipairs(v) do
        if type(dir) ~= 'string' then
          return ('graphs_dirs entry %d must be a string'):format(i)
        end
      end
      return nil
    end,
  },
  graphs_depth = {
    default = 2,
    type = 'number',
    range = function(v)
      if v ~= math.floor(v) then
        return 'graphs_depth must be a whole number'
      end
      if v < 0 then
        return 'graphs_depth must be >= 0'
      end
      return nil
    end,
  },
  graph_depth = {
    default = 1,
    type = 'number',
    range = function(v)
      if v ~= 1 and v ~= 2 then
        return 'graph_depth must be 1 or 2'
      end
      return nil
    end,
  },
  graph_max_files = {
    default = 2000,
    type = 'number',
    range = function(v)
      if v ~= math.floor(v) then
        return 'graph_max_files must be a whole number'
      end
      if v < 1 then
        return 'graph_max_files must be >= 1'
      end
      return nil
    end,
  },
  completion_auto = { default = true, type = 'boolean' },
  completion_limit = {
    default = 50,
    type = 'number',
    range = function(v)
      if v ~= math.floor(v) then
        return 'completion_limit must be a whole number'
      end
      if v < 0 then
        return 'completion_limit must be >= 0'
      end
      return nil
    end,
  },
  todo_cycles = {
    -- M8: first chain containing a marker wins (DONE -> TODO via chain 1).
    default = {
      { 'TODO', 'DOING', 'DONE' },
      { 'LATER', 'NOW', 'DONE' },
      { 'IN-PROGRESS', 'DONE' },
      { 'WAIT', 'TODO' },
      { 'WAITING', 'TODO' },
      { 'CANCELLED', 'TODO' },
      { 'CANCELED', 'TODO' },
    },
    type = 'table',
    list = true,
  },
}

-- NB: graph_path defaults to nil, and { k = nil } stores no key in Lua,
-- so key presence must come from this explicit set, not defaults[k].
local known_keys = {}
for k in pairs(schema) do
  known_keys[k] = true
end

---@type table<string, any>
local defaults = {}
for k, row in pairs(schema) do
  defaults[k] = row.default
end

--- Explicit opts from setup() calls (highest precedence layer).
--- Stored separately from vim.g.logseq so get() can merge the live
--- g: value on every call; setup() is therefore optional, never required.
--- Since the audit (CFG-01) setup() MERGES key-by-key: a call replaces the
--- keys it names and leaves earlier keys alone; a zero-argument call is a
--- no-op. Keys cannot be unset from Lua ({ k = nil } stores no key).
---@type table
local explicit_opts = {}

--- Type/range problem for one value against its schema row, or nil.
---@param k string
---@param row LogseqSchemaRow
---@param v any
---@return string|nil
local function type_problem(k, row, v)
  local optional = row.type:sub(-1) == '?'
  local want = optional and row.type:sub(1, -2) or row.type
  if v == nil then
    if optional then
      return nil
    end
    return ('%s must not be nil'):format(k)
  end
  if type(v) ~= want then
    return ('%s must be a %s, got %s'):format(k, want, type(v))
  end
  if row.range ~= nil then
    return row.range(v)
  end
  return nil
end

--- Problems for the KNOWN keys present in opts (setup's own inputs).
--- Unknown keys are not errors (health reports them), so they are skipped.
---@param opts table
---@return string[] sorted problem strings ({} = ok)
function M.validate_opts(opts)
  local problems = {}
  for k, v in pairs(opts) do
    local row = schema[k]
    if row ~= nil then
      local p = type_problem(k, row, v)
      if p ~= nil then
        table.insert(problems, p)
      end
    end
  end
  table.sort(problems)
  return problems
end

--- Problems for a FULL effective config snapshot (health's read-only check).
--- Catches wrongly-typed values arriving via vim.g.logseq, which setup()
--- never sees. {} = ok.
---@param cfg table
---@return string[] sorted problem strings
function M.validate(cfg)
  local problems = {}
  for k, row in pairs(schema) do
    local p = type_problem(k, row, cfg[k])
    if p ~= nil then
      table.insert(problems, p)
    end
  end
  table.sort(problems)
  return problems
end

--- Merge user opts over defaults (+ vim.g.logseq base). 0..n calls:
--- keys present in opts merge into the explicit layer key-by-key (audit
--- CFG-01); a nil/empty opts call is a no-op. setup() is optional: get()
--- already layers vim.g.logseq over defaults, so a bare
--- `vim.g.logseq = {...}` (or nothing at all) is a valid config.
--- Fails fast on invalid values in opts (audit CFG-02): the previous
--- explicit layer is retained when validation fails.
---@param opts LogseqConfig|nil
---@return LogseqConfig effective config
function M.setup(opts)
  if opts == nil then
    return M.get()
  end
  if type(opts) ~= 'table' then
    error('logseq.nvim: setup(opts) expects a table, got ' .. type(opts), 0)
  end
  if next(opts) == nil then
    return M.get()
  end
  local problems = M.validate_opts(opts)
  if #problems > 0 then
    error('logseq.nvim: invalid setup option(s): ' .. table.concat(problems, '; '), 0)
  end
  for k, v in pairs(opts) do
    explicit_opts[k] = vim.deepcopy(v)
  end
  return M.get()
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
  -- List values replace wholesale (schema rows with list = true):
  -- tbl_deep_extend merges arrays index-wise ({'a','b'} + {'c'} ->
  -- {'c','b'}), which is never the intent. The highest layer defining
  -- the key wins outright.
  for k, row in pairs(schema) do
    if row.list then
      if explicit_opts[k] ~= nil then
        merged[k] = vim.deepcopy(explicit_opts[k])
      elseif type(g) == 'table' and g[k] ~= nil then
        merged[k] = vim.deepcopy(g[k])
      end
    end
  end
  return merged
end

--- Unknown keys across both live layers (explicit + vim.g.logseq),
--- computed on demand — never accumulated state (audit CFG-01: health
--- must be able to report without mutating anything).
---@return string[] sorted
function M.unknown_keys()
  local seen, out = {}, {}
  local function scan(t)
    if type(t) ~= 'table' then
      return
    end
    for k, _ in pairs(t) do
      if not known_keys[k] and not seen[k] then
        seen[k] = true
        table.insert(out, k)
      end
    end
  end
  scan(explicit_opts)
  scan(vim.g.logseq)
  table.sort(out)
  return out
end

--- Shape-check todo_cycles; returns problem strings ({} = ok). Malformed
--- entries are skipped by the cycler, never a hard error — surface via
--- health, like unknown keys. Since the audit (DRY-03) entries outside
--- the canonical Logseq marker vocabulary (see logseq.markers) are also
--- reported: parse_line() only recognizes canonical markers, so a chain
--- with a foreign marker would pass shape checks yet never cycle.
---@param chains any
---@return string[]
function M.check_cycles(chains)
  if type(chains) ~= 'table' then
    return { 'todo_cycles must be a list of chains' }
  end
  local problems = {}
  for i, chain in ipairs(chains) do
    if type(chain) ~= 'table' or #chain == 0 then
      table.insert(problems, ('chain %d is empty'):format(i))
    else
      for j, marker in ipairs(chain) do
        if type(marker) ~= 'string' or marker == '' then
          table.insert(problems, ('chain %d entry %d is not a marker string'):format(i, j))
        elseif not markers.is_canonical(marker) then
          table.insert(
            problems,
            ("chain %d entry %d is not a canonical Logseq marker: '%s'"):format(i, j, marker)
          )
        end
      end
    end
  end
  return problems
end

function M._defaults()
  return vim.deepcopy(defaults)
end

function M._reset()
  explicit_opts = {}
end

return M
