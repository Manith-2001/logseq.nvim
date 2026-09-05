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
    -- One test here calls graph.find_root (M5.3: consults active state).
    graph._set_state_file(vim.fn.tempname())
  end)
  after_each(function()
    graph._set_state_file(nil)
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

  it('defaults graphs_dirs to {} and graphs_depth to 2 (M5.1)', function()
    local cfg = config.get()
    assert.are.same({}, cfg.graphs_dirs)
    assert.are.equal(2, cfg.graphs_depth)
  end)

  it('graphs_dirs replaces wholesale across layers, no index merge (M5.1)', function()
    vim.g.logseq = { graphs_dirs = { 'a', 'b' } }
    config.setup({ graphs_dirs = { 'c' } })
    assert.are.same({ 'c' }, config.get().graphs_dirs)
  end)

  it('defaults todo_cycles to the 7 documented chains (M8.1)', function()
    assert.are.same({
      { 'TODO', 'DOING', 'DONE' },
      { 'LATER', 'NOW', 'DONE' },
      { 'IN-PROGRESS', 'DONE' },
      { 'WAIT', 'TODO' },
      { 'WAITING', 'TODO' },
      { 'CANCELLED', 'TODO' },
      { 'CANCELED', 'TODO' },
    }, config.get().todo_cycles)
  end)

  it('todo_cycles replaces wholesale across layers, no index merge (M8.1)', function()
    vim.g.logseq = { todo_cycles = { { 'TODO', 'DOING', 'DONE' }, { 'LATER', 'NOW' } } }
    config.setup({ todo_cycles = { { 'TODO', 'DONE' } } })
    assert.are.same({ { 'TODO', 'DONE' } }, config.get().todo_cycles)
  end)

  it('check_cycles passes clean chains and flags malformed entries (M8.1)', function()
    assert.are.same({}, config.check_cycles(config.get().todo_cycles))
    assert.are.same({}, config.check_cycles({ { 'TODO', 'DONE' } }))
    assert.are.equal(1, #config.check_cycles('nope'))
    assert.are.equal(1, #config.check_cycles({ {} }))
    assert.are.equal(1, #config.check_cycles({ { 'TODO', 42 } }))
  end)

  it('defaults completion_auto to true and completion_limit to 50 (M10.2)', function()
    local cfg = config.get()
    assert.is_true(cfg.completion_auto)
    assert.are.equal(50, cfg.completion_limit)
    config.setup({ completion_auto = false, completion_limit = 7 })
    cfg = config.get()
    assert.is_false(cfg.completion_auto)
    assert.are.equal(7, cfg.completion_limit)
  end)
end)
