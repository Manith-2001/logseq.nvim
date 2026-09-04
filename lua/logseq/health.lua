local M = {}

local function report_graph(graph_path, pages_dir, journals_dir)
  if graph_path == nil or graph_path == '' then
    vim.health.warn('graph_path unset: auto-detect lands in M1 (graph.find_root)')
  elseif vim.fn.isdirectory(graph_path) == 0 then
    vim.health.error(('graph_path not a directory: %s'):format(graph_path))
    return
  else
    vim.health.ok(('graph_path: %s'):format(graph_path))
  end
  if graph_path and vim.fn.isdirectory(graph_path) == 1 then
    for _, sub in ipairs({ pages_dir, journals_dir }) do
      local dir = graph_path .. '/' .. sub
      if vim.fn.isdirectory(dir) == 1 then
        vim.health.ok(sub .. '/ exists')
      else
        vim.health.warn(sub .. '/ missing under graph root: ' .. dir)
      end
    end
    if vim.fn.filereadable(graph_path .. '/logseq/config.edn') == 1 then
      vim.health.ok('logseq/config.edn found (file graph)')
    else
      vim.health.warn('logseq/config.edn not found under graph root')
    end
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
  report_graph(cfg.graph_path, cfg.pages_dir, cfg.journals_dir)
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
