local config = require('logseq.config')
local graph = require('logseq.graph')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('config lazy vim.g.logseq merge (M1 bugfix)', function()
  local saved_g
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
  end)
  after_each(function()
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('returns defaults with neither g: nor setup()', function()
    local cfg = config.get()
    assert.is_nil(cfg.graph_path)
    assert.are.equal('pages', cfg.pages_dir)
    assert.are.equal('journals', cfg.journals_dir)
  end)

  it('honors vim.g.logseq with zero setup() calls', function()
    vim.g.logseq = { graph_path = fixture }
    assert.are.equal(fixture, config.get().graph_path)
  end)

  it('setup(opts) wins over vim.g.logseq', function()
    vim.g.logseq = { graph_path = fixture, pages_dir = 'g_pages' }
    config.setup({ pages_dir = 'setup_pages' })
    local cfg = config.get()
    assert.are.equal(fixture, cfg.graph_path)
    assert.are.equal('setup_pages', cfg.pages_dir)
  end)

  it('picks up mid-session g: changes without another setup()', function()
    vim.g.logseq = { graph_path = fixture }
    assert.are.equal(fixture, config.get().graph_path)
    vim.g.logseq = { graph_path = '/tmp' }
    assert.are.equal('/tmp', config.get().graph_path)
  end)

  it('find_root resolves a g:-configured path with no setup() call', function()
    vim.g.logseq = { graph_path = fixture }
    assert.are.equal(fixture, graph.find_root('/tmp'))
  end)
end)
