--- Finder picker (M1): Telescope when available, vim.ui.select fallback.
--- Telescope is optional: every require goes through pcall, and a picker
--- that errors (e.g. headless UI) degrades to the fallback instead of
--- raising. See health.lua for the availability report.
local M = {}

---@class LogseqPickOpts
---@field prompt_title string|nil
---@field format_item fun(item: table): string|nil
---@field ordinal fun(item: table): string|nil fuzzy-match text (default item.title)
---@field on_choice fun(item: table)|nil

local function default_format(item)
  return ('[%s] %s'):format(item.kind, item.title)
end

local function default_ordinal(item)
  return item.title
end

local function telescope_pick(items, prompt, on_choice, format_item, ordinal_of)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  pickers
    .new({}, {
      prompt_title = prompt,
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return { value = item, display = format_item(item), ordinal = ordinal_of(item) }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr, _)
        actions.select_default:replace(function()
          actions.close(bufnr)
          local entry = action_state.get_selected_entry()
          if entry and entry.value then
            on_choice(entry.value)
          end
        end)
        return true
      end,
    })
    :find()
end

--- Show items; call on_choice(item) on selection, nothing on cancel.
---@param items table[]
---@param opts LogseqPickOpts|nil
function M.pick(items, opts)
  opts = opts or {}
  local prompt = opts.prompt_title or 'Logseq Pages'
  local format_item = opts.format_item or default_format
  local on_choice = opts.on_choice or function() end
  local ordinal_of = opts.ordinal or default_ordinal
  if pcall(require, 'telescope') then
    if pcall(telescope_pick, items, prompt, on_choice, format_item, ordinal_of) then
      return
    end
  end
  vim.ui.select(items, { prompt = prompt, format_item = format_item }, function(choice)
    if choice then
      on_choice(choice)
    end
  end)
end

return M
