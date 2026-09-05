local M = {}

local function report_graphs(cfg)
  local ok, g = pcall(require, 'logseq.graph')
  if not ok then
    vim.health.error('logseq.graph failed to load')
    return
  end
  -- Discovery (M5.1) is on-demand: the switch picker and this check scan,
  -- never startup, so there is no cache to invalidate.
  local known = g.discover_graphs()
  if #known == 0 then
    if type(cfg.graphs_dirs) == 'table' and #cfg.graphs_dirs > 0 then
      vim.health.warn('graphs_dirs set but no graphs discovered (check graphs_dirs/graphs_depth)')
    else
      vim.health.info('graphs_dirs unset: single-graph mode')
    end
  else
    local names = {}
    for _, item in ipairs(known) do
      table.insert(names, item.name)
    end
    vim.health.ok(('discovered %d graph(s): %s'):format(#known, table.concat(names, ', ')))
  end
  -- A stored entry that no longer validates is ignored silently by
  -- get_active(); surface it here so it can be reset via :LogseqGraphs.
  local entry = g.state_entry()
  local active = g.get_active()
  if entry ~= nil and active ~= entry then
    vim.health.warn(
      ('stale active-graph entry ignored: %s (pick :LogseqGraphs to reset)'):format(entry)
    )
  end
  -- Effective root plus the resolution step that produced it (M5.3 order:
  -- buffer walk-up, active override, graph_path, cwd walk-up). The root
  -- comes from find_root() itself; the source is whichever step agrees.
  local graph_path = nil
  if type(cfg.graph_path) == 'string' and cfg.graph_path ~= '' then
    graph_path = vim.fn.expand(cfg.graph_path)
  end
  local root = g.find_root()
  if root then
    local source = 'auto:' .. root
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname ~= '' and g.find_root_from(bufname) == root then
      source = 'buffer:' .. root
    elseif active ~= nil and active == root then
      source = 'active:' .. root
    elseif graph_path ~= nil and vim.fn.isdirectory(graph_path) == 1 then
      source = 'graph_path'
    end
    vim.health.ok(('effective graph (%s): %s'):format(source, root))
  elseif graph_path ~= nil then
    vim.health.error(('graph_path not a directory: %s'):format(graph_path))
    return
  else
    vim.health.warn(
      'no graph resolved (open a file inside a graph, set graph_path, or pick :LogseqGraphs)'
    )
    return
  end
  for _, sub in ipairs({ cfg.pages_dir, cfg.journals_dir }) do
    local dir = root .. '/' .. sub
    if vim.fn.isdirectory(dir) == 1 then
      vim.health.ok(sub .. '/ exists')
    else
      vim.health.warn(sub .. '/ missing under graph root: ' .. dir)
    end
  end
  if vim.fn.filereadable(root .. '/logseq/config.edn') == 1 then
    vim.health.ok('logseq/config.edn found (file graph)')
  else
    vim.health.warn('logseq/config.edn not found under graph root')
  end
end

function M.check()
  vim.health.start('logseq')
  if vim.fn.has('nvim-0.10') == 1 then
    vim.health.ok(('nvim %s'):format(vim.fn.execute('version'):match('NVIM v(%S+)') or '?'))
  else
    vim.health.error('requires Neovim >= 0.10 (0.12 tested)')
  end
  local ok, cfg_mod = pcall(require, 'logseq.config')
  if not ok then
    vim.health.error('logseq.config failed to load: ' .. tostring(cfg_mod))
    return
  end
  -- setup() is merge-only/idempotent; picks up vim.g.logseq when the user
  -- skipped an explicit setup() call.
  cfg_mod.setup()
  local cfg = cfg_mod.get()
  for _, k in ipairs(cfg_mod.unknown_keys()) do
    vim.health.warn('unknown config key: ' .. k)
  end
  -- Malformed todo_cycles entries are skipped by the cycler (M8); surface
  -- them here so a typo'd chain doesn't fail silently.
  local problems = cfg_mod.check_cycles(cfg.todo_cycles)
  if #problems > 0 then
    vim.health.warn(
      ('todo_cycles problem(s), bad entries skipped: %s'):format(table.concat(problems, '; '))
    )
  end
  report_graphs(cfg)
  if pcall(require, 'telescope') then
    vim.health.ok('telescope available')
  else
    vim.health.warn('telescope not found: vim.ui.select fallback will be used (M1)')
  end
  if pcall(require, 'plenary.busted') then
    vim.health.ok('plenary.busted available (test runner)')
  else
    vim.health.warn('plenary.nvim not on rtp: `make test` needs it')
  end
end

return M
