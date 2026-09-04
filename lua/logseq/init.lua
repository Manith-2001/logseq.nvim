--- Public facade. M0: stubs only; real logic lands in M1 (find),
--- M2 (follow), M3 (today/new_page).
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

function M.find_files(_opts)
  not_yet(':LogseqFind (M1)')
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
