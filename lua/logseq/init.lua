--- Public facade. M1: find_files(); M2: follow_link(); M3: today()/new_page().
local config = require('logseq.config')

local M = {}

--- Merge opts (delegates to config). Optional; plugin works without it.
---@param opts table|nil
function M.setup(opts)
  return config.setup(opts)
end

--- Shared root resolution: opts.root wins (tests), else graph.find_root().
--- Notifies + returns nil when no root is found.
---@param opts table
---@return string|nil
local function resolve_root(opts)
  local graph = require('logseq.graph')
  local root = (type(opts.root) == 'string' and opts.root ~= '') and opts.root or graph.find_root()
  if not root then
    vim.notify(
      'logseq.nvim: graph root not found (set graph_path or open a file inside the graph)',
      vim.log.levels.ERROR
    )
    return nil
  end
  return root
end

--- Namespace guard (M4, see §2 non-goals + §8.1 finding): titles containing
--- `/` map to subpaths that Logseq namespaces own. v0.1 refuses them with a
--- warning instead of opening a buffer that could never round-trip.
---@param title string
---@return boolean true when the title is namespace-free
local function check_no_namespace(title)
  if title:find('/', 1, true) then
    vim.notify(
      ('logseq.nvim: namespace pages like [[%s]] are out of scope for v0.1'):format(title),
      vim.log.levels.WARN
    )
    return false
  end
  return true
end

--- Find/open pages + journals via Telescope (vim.ui.select fallback).
--- opts.root overrides root resolution (used by tests); otherwise
--- graph.find_root() applies (config.graph_path, else upward search).
---@param opts table|nil
function M.find_files(opts)
  opts = opts or {}
  local root = resolve_root(opts)
  if not root then
    return
  end
  local items = require('logseq.graph').list_pages(root)
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

--- Follow the [[link]] / #[[link]] / #tag under the cursor.
--- Opens lazily via page.open_lazy: missing pages open as empty buffers
--- and no file is created until content is written (dangling refs).
--- opts.root overrides root resolution (used by tests); otherwise
--- graph.find_root() applies (config.graph_path, else upward search).
---@param opts table|nil
function M.follow_link(opts)
  opts = opts or {}
  local root = resolve_root(opts)
  if not root then
    return
  end
  local parser = require('logseq.parser')
  local page = require('logseq.page')
  local ok, line = pcall(vim.api.nvim_get_current_line)
  if not ok then
    return
  end
  -- nvim_win_get_cursor col is 0-based; the parser uses 1-based cols.
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local link = parser.link_under_cursor(line, col)
  if not link then
    vim.notify('logseq.nvim: no link under cursor', vim.log.levels.WARN)
    return
  end
  if not check_no_namespace(link.text) then
    return
  end
  page.open_lazy(page.title_to_path(root, link.text))
end

--- Open today's journal (`journals/<os.date(journal_format)>.md`) lazily:
--- a missing journal opens as an empty buffer, no file until content + `:w`.
--- opts.root overrides root resolution (used by tests); opts.date
--- (a filename stem like '2026_08_27') overrides os.date (used by tests).
---@param opts table|nil
function M.today(opts)
  opts = opts or {}
  local root = resolve_root(opts)
  if not root then
    return
  end
  local stem = opts.date
  if type(stem) ~= 'string' or stem == '' then
    stem = os.date(config.get().journal_format)
  end
  local page = require('logseq.page')
  page.open_lazy(page.journal_to_path(root, stem))
end

--- Open a (possibly new) page lazily via page.open_lazy.
--- title may be a string, or the cmd_opts table from :LogseqNew
--- (whose .args holds the title, '' when none was given). With no usable
--- title the user is prompted via vim.ui.input; cancelling aborts quietly.
---@param title string|table|nil
---@param opts table|nil ({root=} override, used by tests)
function M.new_page(title, opts)
  if type(title) == 'table' then
    if type(title.args) == 'string' and title.args ~= '' then
      title = title.args -- :LogseqNew cmd_opts: .args holds the title
    else
      opts, title = title, nil -- opts-style call new_page({root=...}): prompt
    end
  end
  opts = opts or {}
  if type(title) == 'string' and title:match('^%s*$') then
    title = nil -- blank behaves like no title: prompt instead of asserting
  end
  local root = resolve_root(opts)
  if not root then
    return
  end
  local page = require('logseq.page')
  if title ~= nil then
    if not check_no_namespace(title) then
      return
    end
    page.open_lazy(page.title_to_path(root, title))
    return
  end
  vim.ui.input({ prompt = 'Logseq new page: ' }, function(input)
    if input == nil or input:match('^%s*$') then
      vim.notify('logseq.nvim: new page cancelled', vim.log.levels.INFO)
      return
    end
    if not check_no_namespace(input) then
      return
    end
    page.open_lazy(page.title_to_path(root, input))
  end)
end

return M
