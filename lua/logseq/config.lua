---@class LogseqConfig
---@field graph_path string|nil absolute path to graph root (nil = auto-detect)
---@field pages_dir string default 'pages'
---@field journals_dir string default 'journals'
---@field journal_format string os.date format, default '%Y_%m_%d'
---@field picker string 'telescope' (with vim.ui.select fallback)

local M = {}

---@type LogseqConfig
local defaults = {
  graph_path = nil,
  pages_dir = 'pages',
  journals_dir = 'journals',
  journal_format = '%Y_%m_%d',
  picker = 'telescope',
}

---@type LogseqConfig
local current = vim.deepcopy(defaults)

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
}

local function warn_unknown(opts)
  for k, _ in pairs(opts or {}) do
    if not known_keys[k] and not vim.tbl_contains(unknown_keys, k) then
      table.insert(unknown_keys, k)
    end
  end
end

--- Merge user opts over defaults (+ vim.g.logseq base). Idempotent, 0..n calls.
---@param opts LogseqConfig|nil
function M.setup(opts)
  opts = opts or {}
  local g = vim.g.logseq
  local base = vim.deepcopy(defaults)
  if type(g) == 'table' then
    warn_unknown(g)
    base = vim.tbl_deep_extend('force', base, g)
  end
  warn_unknown(opts)
  current = vim.tbl_deep_extend('force', base, opts)
  pcall(vim.validate, {
    graph_path = { current.graph_path, { 'string', 'nil' } },
    pages_dir = { current.pages_dir, 'string' },
    journals_dir = { current.journals_dir, 'string' },
    journal_format = { current.journal_format, 'string' },
    picker = { current.picker, 'string' },
  })
  return current
end

--- Read-only snapshot of effective config.
---@return LogseqConfig
function M.get()
  return vim.deepcopy(current)
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
  current = vim.deepcopy(defaults)
  unknown_keys = {}
end

return M
