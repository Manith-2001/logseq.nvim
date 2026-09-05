local config = require('logseq.config')
local graph = require('logseq.graph')

-- Active-graph state round-trips (M5.2). The state file is redirected to a
-- tmp path so specs never touch the real stdpath('data'); after_each
-- restores the default location plus a cleared memory cache, so later
-- spec files (M5.3 order matrix) start with no active graph.
describe('graph active state (M5.2)', function()
  local saved_g
  local tmps
  local statefile
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    tmps = {}
    statefile = vim.fn.tempname() .. '_active'
    table.insert(tmps, statefile)
    graph._set_state_file(statefile)
  end)
  after_each(function()
    graph._set_state_file(nil)
    for _, t in ipairs(tmps) do
      vim.fn.delete(t, 'rf')
    end
    vim.g.logseq = saved_g
    config._reset()
  end)

  local function track(tmp)
    table.insert(tmps, tmp)
    return tmp
  end

  local function mkgraph(root)
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    vim.fn.writefile({ '- x' }, root .. '/pages/A.md')
    return root
  end

  it('starts with no active graph and no state file', function()
    assert.is_nil(graph.get_active())
    assert.are.equal(0, vim.fn.filereadable(statefile))
  end)

  it('set_active stores the path and persists a single line', function()
    local root = mkgraph(track(vim.fn.tempname()))
    assert.are.equal(root, graph.set_active(root))
    assert.are.equal(root, graph.get_active())
    assert.are.same({ root }, vim.fn.readfile(statefile))
  end)

  it('set_active normalizes trailing slashes', function()
    local root = mkgraph(track(vim.fn.tempname()))
    assert.are.equal(root, graph.set_active(root .. '/'))
    assert.are.equal(root, graph.get_active())
  end)

  it('round-trips across a simulated restart', function()
    local root = mkgraph(track(vim.fn.tempname()))
    graph.set_active(root)
    graph._reset_active() -- drop memory, keep the file: like a restart
    assert.are.equal(root, graph.get_active())
  end)

  it('lazy-loads a state file written out-of-band', function()
    local root = mkgraph(track(vim.fn.tempname()))
    vim.fn.writefile({ root }, statefile)
    assert.are.equal(root, graph.get_active())
  end)

  it('ignores a stale state entry: missing dir', function()
    vim.fn.writefile({ '/tmp/no-such-logseq-graph-xyz' }, statefile)
    assert.is_nil(graph.get_active())
  end)

  it('ignores a stale state entry: dir exists but is not a graph', function()
    local plain = track(vim.fn.tempname())
    vim.fn.mkdir(plain, 'p')
    vim.fn.writefile({ plain }, statefile)
    assert.is_nil(graph.get_active())
  end)

  it('forgets a graph deleted mid-session', function()
    local root = mkgraph(track(vim.fn.tempname()))
    graph.set_active(root)
    assert.are.equal(root, graph.get_active())
    vim.fn.delete(root, 'rf')
    assert.is_nil(graph.get_active())
  end)

  it('clear_active forgets and deletes the state file', function()
    local root = mkgraph(track(vim.fn.tempname()))
    graph.set_active(root)
    graph.clear_active()
    assert.is_nil(graph.get_active())
    assert.are.equal(0, vim.fn.filereadable(statefile))
  end)

  it('clear_active is a no-op when nothing is set', function()
    graph.clear_active()
    assert.is_nil(graph.get_active())
  end)

  it('set_active rejects blanks, missing paths, and non-roots', function()
    local plain = track(vim.fn.tempname())
    vim.fn.mkdir(plain, 'p')
    assert.has_error(function()
      graph.set_active(nil)
    end)
    assert.has_error(function()
      graph.set_active('   ')
    end)
    assert.has_error(function()
      graph.set_active('/tmp/no-such-logseq-graph-xyz')
    end)
    assert.has_error(function()
      graph.set_active(plain)
    end)
    assert.is_nil(graph.get_active())
  end)

  it('set_active resolves a discovered basename', function()
    local tmp = track(vim.fn.tempname())
    mkgraph(tmp .. '/alpha')
    mkgraph(tmp .. '/beta')
    config.setup({ graphs_dirs = { tmp }, graphs_depth = 1 })
    assert.are.equal(tmp .. '/beta', graph.set_active('beta'))
    assert.are.equal(tmp .. '/beta', graph.get_active())
  end)

  it('set_active accepts a direct path with no discovery configured', function()
    local root = mkgraph(track(vim.fn.tempname()))
    -- No graphs_dirs set: the dir itself resolves without name lookup.
    assert.are.equal(root, graph.set_active(root))
  end)

  it('set_active errors on unknown and ambiguous names', function()
    local tmp = track(vim.fn.tempname())
    mkgraph(tmp .. '/one/dup')
    mkgraph(tmp .. '/two/dup')
    config.setup({ graphs_dirs = { tmp }, graphs_depth = 2 })
    assert.has_error(function()
      graph.set_active('nope')
    end)
    assert.has_error(function()
      graph.set_active('dup')
    end)
    assert.is_nil(graph.get_active())
  end)
end)
