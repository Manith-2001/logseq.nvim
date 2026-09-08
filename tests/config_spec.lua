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

  it('setup() with no opts is a no-op, not a wipe (CFG-01)', function()
    config.setup({ pages_dir = 'keepme' })
    config.setup()
    assert.are.equal('keepme', config.get().pages_dir)
    config.setup({})
    assert.are.equal('keepme', config.get().pages_dir)
  end)

  it('setup() merges key-by-key across calls; later keys win (CFG-01)', function()
    config.setup({ pages_dir = 'a' })
    config.setup({ journals_dir = 'b' })
    local cfg = config.get()
    assert.are.equal('a', cfg.pages_dir)
    assert.are.equal('b', cfg.journals_dir)
    config.setup({ pages_dir = 'c' })
    assert.are.equal('c', config.get().pages_dir)
  end)

  it('setup() raises on invalid types and retains the last valid config (CFG-02)', function()
    config.setup({ completion_limit = 5 })
    assert.has_error(function()
      config.setup({ completion_limit = 'many' })
    end)
    assert.has_error(function()
      config.setup({ completion_auto = 'yes' })
    end)
    assert.has_error(function()
      config.setup({ graph_depth = 3 })
    end)
    assert.has_error(function()
      config.setup({ graph_max_files = 0 })
    end)
    assert.has_error(function()
      config.setup({ graphs_depth = -1 })
    end)
    assert.has_error(function()
      config.setup({ graphs_dirs = { 1 } })
    end)
    assert.has_error(function()
      config.setup('nope')
    end)
    assert.are.equal(5, config.get().completion_limit)
  end)

  it('validate() reports problems in a full snapshot (CFG-02)', function()
    -- NOTE(deviation from plan verbatim): plan passed a partial table
    -- { graph_depth=9, completion_limit=-1 }, but validate() checks a FULL
    -- snapshot so missing keys report too (10 problems, not 2). Build a full
    -- snapshot from get() and corrupt 2 keys to assert the intended 2.
    local cfg = config.get()
    cfg.graph_depth = 9
    cfg.completion_limit = -1
    local problems = config.validate(cfg)
    assert.are.equal(2, #problems)
    local joined = table.concat(problems, '\n')
    assert.is_not_nil(joined:find('graph_depth', 1, true))
    assert.is_not_nil(joined:find('completion_limit', 1, true))
  end)

  it('unknown_keys() derives sorted from both layers (DRY-02)', function()
    vim.g.logseq = { nope = 1 }
    config.setup({ also_nope = 2 })
    assert.are.same({ 'also_nope', 'nope' }, config.unknown_keys())
  end)

  it('graph_path = nil stays valid (optional string)', function()
    assert.are.same({}, config.validate_opts({ graph_path = nil }))
  end)

  it('check_cycles flags non-canonical markers (DRY-03)', function()
    local problems = config.check_cycles({ { 'TODO', 'BLOCKED' } })
    assert.are.equal(1, #problems)
    assert.is_not_nil(problems[1]:find('BLOCKED', 1, true))
  end)
end)
