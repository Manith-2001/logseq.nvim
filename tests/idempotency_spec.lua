-- Idempotency (M4, §5 checklist): double setup()/source must not duplicate
-- commands, mappings, or autocmds; the write guard group is created once.
local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('idempotency (M4)', function()
  local saved_g
  local config = require('logseq.config')
  local bufs
  local tmp
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    bufs = {}
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. '/pages', 'p')
    vim.fn.mkdir(tmp .. '/journals', 'p')
  end)
  after_each(function()
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.fn.delete(tmp, 'rf')
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('double setup() merges identically', function()
    config.setup({ graph_path = fixture })
    local once = config.get()
    config.setup({ graph_path = fixture })
    assert.are.same(once, config.get())
  end)

  it('double :source keeps one of each command and map', function()
    local plugin = repo .. '/plugin/logseq.lua'
    vim.cmd('source ' .. vim.fn.fnameescape(plugin))
    vim.cmd('source ' .. vim.fn.fnameescape(plugin))
    for _, name in ipairs({
      'LogseqFind',
      'LogseqFollow',
      'LogseqToday',
      'LogseqNew',
      'LogseqGraphs',
      'LogseqGraph',
      'LogseqTodos',
      'LogseqTodosView',
      'LogseqCycleTodo',
    }) do
      assert.are.equal(2, vim.fn.exists(':' .. name))
    end
    assert.are_not.equal('', vim.fn.maparg('<Plug>(LogseqFollow)', 'n'))
    assert.are_not.equal('', vim.fn.maparg('<Plug>(LogseqCycleTodo)', 'n'))
  end)

  it('repeated open_lazy() leaves a single write-guard autocmd pair', function()
    local page = require('logseq.page')
    local home = vim.api.nvim_create_buf(true, false)
    table.insert(bufs, home)
    vim.api.nvim_set_current_buf(home)
    vim.bo[home].modified = false
    for _ = 1, 3 do
      vim.api.nvim_set_current_buf(home)
      table.insert(bufs, page.open_lazy(tmp .. '/pages/Dupe.md'))
    end
    local pre = vim.api.nvim_get_autocmds({ group = 'LogseqNvim', event = 'BufWritePre' })
    local post = vim.api.nvim_get_autocmds({ group = 'LogseqNvim', event = 'BufWritePost' })
    assert.are.equal(1, #pre)
    assert.are.equal(1, #post)
  end)
end)
