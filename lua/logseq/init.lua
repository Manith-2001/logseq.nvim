--- Public facade. M1: find_files(); M2: follow_link(); M3: today()/new_page();
--- M5.3: switch_graph(); M6.2: graph_view().
local config = require('logseq.config')

local M = {}

--- Merge opts (delegates to config). Optional; plugin works without it.
---@param opts table|nil
function M.setup(opts)
  return config.setup(opts)
end

--- Shared root resolution (M5.3 order): opts.root (explicit per call) →
--- buffer walk-up → active graph → graph_path (strict) → cwd walk-up.
--- Notifies + returns nil when no root is found.
---@param opts table
---@return string|nil
local function resolve_root(opts)
  local graph = require('logseq.graph')
  local root = (type(opts.root) == 'string' and opts.root ~= '') and opts.root or graph.find_root()
  if not root then
    vim.notify(
      'logseq.nvim: graph root not found (set graph_path, pick :LogseqGraphs, or open a file inside the graph)',
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
--- graph.find_root() applies (buffer → active → graph_path → cwd).
--- The picker title shows the graph name so the scope is visible.
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
    prompt_title = ('Logseq Pages — %s'):format(vim.fn.fnamemodify(root, ':t')),
    on_choice = function(item)
      vim.cmd('edit ' .. vim.fn.fnameescape(item.path))
    end,
  })
end

--- Follow the [[link]] / #[[link]] / #tag under the cursor.
--- Opens lazily via page.open_lazy: missing pages open as empty buffers
--- and no file is created until content is written (dangling refs).
--- opts.root overrides root resolution (used by tests); otherwise
--- graph.find_root() applies (buffer → active → graph_path → cwd).
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

--- Derive the center title from the current buffer when it is a page or
--- journal directly under root (symlink-resolved on both sides, like the
--- M3 specs). Returns nil for unnamed buffers and files outside the graph.
---@param root string absolute graph root
---@return string|nil
local function title_from_buffer(root)
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then
    return nil
  end
  local resolved = vim.fn.resolve(name)
  local base = vim.fn.resolve(root)
  for _, sub in ipairs({ config.get().pages_dir, config.get().journals_dir }) do
    local prefix = base .. '/' .. sub .. '/'
    if resolved:sub(1, #prefix) == prefix and resolved:sub(-3) == '.md' then
      return resolved:sub(#prefix + 1, -4)
    end
  end
  return nil
end

--- Pick the active graph (M5.3, multi-graph switching) via Telescope
--- (vim.ui.select fallback). Items = graph_path ∪ discovered roots ∪ the
--- current active (so an override is listed — and clearable — even when it
--- came from outside the picker), shown as `name — path` so basename
--- collisions stay distinguishable; matched internally by path. The `(auto)`
--- entry clears the override back to plain resolution. Choosing sets +
--- persists (INFO notify); with nothing to offer, warns and hints at
--- graphs_dirs instead of opening a picker.
--- A stale graph_path stays listed and errors loudly on selection
--- (strictness: misconfiguration must not silently resolve elsewhere).
function M.switch_graph()
  local graph = require('logseq.graph')
  local cfg = config.get()
  local items = {}
  local seen = {}
  local function offer(name, path)
    local key = path or '(auto)'
    if not seen[key] then
      seen[key] = true
      table.insert(items, {
        title = path and ('%s — %s'):format(name, path) or '(auto) — resolve automatically',
        kind = path and 'graph' or 'auto',
        name = name,
        path = path,
      })
    end
  end
  if type(cfg.graph_path) == 'string' and cfg.graph_path ~= '' then
    local norm = vim.fn.fnamemodify(vim.fn.expand(cfg.graph_path), ':p'):gsub('/+$', '')
    if norm == '' then
      norm = '/'
    end
    offer(vim.fn.fnamemodify(norm, ':t'), norm)
  end
  for _, known in ipairs(graph.discover_graphs()) do
    offer(known.name, known.path)
  end
  local active = graph.get_active()
  if active then
    offer(vim.fn.fnamemodify(active, ':t'), active)
  end
  if #items == 0 then
    vim.notify(
      'logseq.nvim: no graphs found (set graphs_dirs to scan for graphs)',
      vim.log.levels.WARN
    )
    return
  end
  offer('(auto)', nil)
  require('logseq.telescope').pick(items, {
    prompt_title = 'Logseq Graphs',
    on_choice = function(choice)
      if choice.path == nil then
        graph.clear_active()
        vim.notify('logseq.nvim: active graph cleared (auto)', vim.log.levels.INFO)
        return
      end
      graph.set_active(choice.path)
      vim.notify(('logseq.nvim: active graph: %s'):format(choice.name), vim.log.levels.INFO)
    end,
  })
end

--- Open the local graph explorer (M6.2) for one page: Linked +
--- Backlinks (+ `2 hops` at depth 2) in a scratch `filetype=logseq-graph`
--- buffer. The center title comes from opts.title (or :LogseqGraph's
--- [title] arg), else the current pages/*/journals/* buffer, else a
--- prompt; cancelling aborts quietly. The index builds synchronously and
--- refuses graphs over graph_max_files with a warning (raise the key to
--- opt in). opts.root overrides root resolution (used by tests).
---@param opts table|nil ({title=, depth=, root=}; :LogseqGraph cmd_opts tolerated)
---@return integer|nil explorer bufnr, or nil when aborted
function M.graph_view(opts)
  opts = opts or {}
  if
    type(opts.title) ~= 'string'
    and opts.root == nil
    and type(opts.args) == 'string'
    and opts.args ~= ''
  then
    opts = { title = opts.args } -- :LogseqGraph cmd_opts: .args holds the title
  end
  local root = resolve_root(opts)
  if not root then
    return nil
  end
  local cfg = config.get()
  local depth = (opts.depth == 2 or cfg.graph_depth == 2) and 2 or 1
  local count = #require('logseq.graph').list_pages(root)
  if count > cfg.graph_max_files then
    vim.notify(
      ('logseq.nvim: graph too large (%d files > %d graph_max_files); raise graph_max_files to explore it'):format(
        count,
        cfg.graph_max_files
      ),
      vim.log.levels.WARN
    )
    return nil
  end
  local title = opts.title
  if type(title) == 'string' and title:match('^%s*$') then
    title = nil -- blank behaves like no title: derive, then prompt
  end
  if title == nil then
    title = title_from_buffer(root)
  end
  if title ~= nil then
    if not check_no_namespace(title) then
      return nil
    end
    return require('logseq.view').open({ root = root, title = title, depth = depth })
  end
  local bufnr = nil
  vim.ui.input({ prompt = 'Logseq graph page: ' }, function(input)
    if input == nil or input:match('^%s*$') then
      vim.notify('logseq.nvim: graph view cancelled', vim.log.levels.INFO)
      return
    end
    if not check_no_namespace(input) then
      return
    end
    bufnr = require('logseq.view').open({ root = root, title = input, depth = depth })
  end)
  return bufnr
end

return M
