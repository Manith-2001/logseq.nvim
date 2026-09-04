--- Public facade. M1: find_files() is real; follow lands in M2,
--- today()/new_page() in M3.
local config = require('logseq.config')

local M = {}

--- Merge opts (delegates to config). Optional; plugin works without it.
---@param opts table|nil
function M.setup(opts)
  return config.setup(opts)
end

local function not_yet(what)
  vim.notify(
    ('logseq.nvim: %s not yet implemented (see PLAN.md milestones)'):format(what),
    vim.log.levels.WARN
  )
end

--- Find/open pages + journals via Telescope (vim.ui.select fallback).
--- opts.root overrides root resolution (used by tests); otherwise
--- graph.find_root() applies (config.graph_path, else upward search).
---@param opts table|nil
function M.find_files(opts)
  opts = opts or {}
  local graph = require('logseq.graph')
  local root = (type(opts.root) == 'string' and opts.root ~= '') and opts.root or graph.find_root()
  if not root then
    vim.notify(
      'logseq.nvim: graph root not found (set graph_path or open a file inside the graph)',
      vim.log.levels.ERROR
    )
    return
  end
  local items = graph.list_pages(root)
  if #items == 0 then
    vim.notify(('logseq.nvim: no pages found under %s'):format(root), vim.log.levels.WARN)
    return
  end
  require('logseq.telescope').pick(items, {
    prompt_title = 'Logseq Pages',
    on_choice = function(item)
      vim.cmd('edit ' .. vim.fn.fnameescape(item.path))
    end,
  })
end

function M.follow_link(_opts)
  not_yet(':LogseqFollow (M2)')
end

function M.today(_opts)
  not_yet(':LogseqToday (M3)')
end

function M.new_page(_opts)
  not_yet(':LogseqNew (M3)')
end

return M
