local graph = require('logseq.graph')
local config = require('logseq.config')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('graph.find_root (M1)', function()
  local saved_g
  before_each(function()
    -- Hermetic: minimal_init.lua pre-seeds vim.g.logseq, and get() now
    -- honors g: without setup(), so clear it per test (restore after).
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    -- find_root consults the active graph (M5.3 step 3): isolate the state
    -- file so a real stdpath entry can never leak into these specs.
    graph._set_state_file(vim.fn.tempname())
  end)
  after_each(function()
    graph._set_state_file(nil)
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('finds the root upward from a nested page file', function()
    assert.are.equal(fixture, graph.find_root(fixture .. '/pages/A.md'))
  end)

  it('finds the root from the root itself and from a journal file', function()
    assert.are.equal(fixture, graph.find_root(fixture))
    assert.are.equal(fixture, graph.find_root(fixture .. '/journals/2026_08_27.md'))
  end)

  it('returns nil outside any graph', function()
    assert.is_nil(graph.find_root('/tmp/no-such-logseq-graph-xyz'))
  end)

  it('graph_path applies when the startpath is outside any graph', function()
    config.setup({ graph_path = fixture })
    assert.are.equal(fixture, graph.find_root('/tmp'))
  end)

  it('explicit startpath inside a graph resolves despite set-but-missing graph_path', function()
    -- M5.3 order: the asked-about location (step 2) precedes strict
    -- graph_path (step 4). The short-circuit half of strictness (no cwd
    -- fallback) is covered by the order matrix below.
    config.setup({ graph_path = fixture .. '/does-not-exist' })
    assert.are.equal(fixture, graph.find_root(fixture .. '/pages/A.md'))
  end)

  it('expands ~ in graph_path', function()
    -- Unnamed buffer: no-arg find_root must not depend on ambient buffers
    -- left behind by other spec files (M5.3 buffer-wins).
    local prev = vim.api.nvim_get_current_buf()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    config.setup({ graph_path = '~/' })
    assert.are.equal(vim.fn.expand('~/'):gsub('/+$', ''), graph.find_root())
    vim.api.nvim_set_current_buf(prev)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe('graph.list_pages (M1)', function()
  local saved_g
  before_each(function()
    -- Hermetic: minimal_init.lua pre-seeds vim.g.logseq, and get() now
    -- honors g: without setup(), so clear it per test (restore after).
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
  end)
  after_each(function()
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('lists fixture pages + journals with kinds and paths', function()
    local items = graph.list_pages(fixture)
    local by_title = {}
    for _, item in ipairs(items) do
      by_title[item.title] = item
    end
    assert.are.equal('page', by_title['A'].kind)
    assert.are.equal(fixture .. '/pages/A.md', by_title['A'].path)
    assert.are.equal('page', by_title['B'].kind)
    assert.are.equal('journal', by_title['2026_08_27'].kind)
    assert.are.equal(fixture .. '/journals/2026_08_27.md', by_title['2026_08_27'].path)
    assert.are.equal(3, #items)
  end)

  it('excludes hidden files, non-md files, and subdirs (non-recursive)', function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. '/pages/sub', 'p')
    vim.fn.mkdir(tmp .. '/journals', 'p')
    vim.fn.writefile({ '- x' }, tmp .. '/pages/Visible.md')
    vim.fn.writefile({ '- hidden' }, tmp .. '/pages/.hidden.md')
    vim.fn.writefile({ '- nested' }, tmp .. '/pages/sub/Nested.md')
    vim.fn.writefile({ 'not markdown' }, tmp .. '/pages/notes.txt')
    local items = graph.list_pages(tmp)
    assert.are.equal(1, #items)
    assert.are.equal('Visible', items[1].title)
    assert.are.equal('page', items[1].kind)
    vim.fn.delete(tmp, 'rf')
  end)

  it('returns {} when the dirs are missing', function()
    assert.are.same({}, graph.list_pages('/tmp/no-such-logseq-graph-xyz'))
  end)
end)

describe('graph.find_root_from (M3)', function()
  local saved_g
  local tmps
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    tmps = {}
  end)
  after_each(function()
    for _, t in ipairs(tmps) do
      vim.fn.delete(t, 'rf')
    end
    vim.g.logseq = saved_g
    config._reset()
  end)

  it('locates the root from a nested file, ignoring config.graph_path', function()
    config.setup({ graph_path = '/tmp' }) -- override points elsewhere...
    -- ...yet the buffer-anchored search still finds the real graph.
    assert.are.equal(fixture, graph.find_root_from(fixture .. '/pages/A.md'))
  end)

  it('returns nil outside any graph even with graph_path set', function()
    config.setup({ graph_path = fixture })
    assert.is_nil(graph.find_root_from('/tmp/no-such-logseq-graph-xyz/f.md'))
  end)

  it('detects a root via logseq/config.edn alone', function()
    local tmp = vim.fn.tempname()
    table.insert(tmps, tmp)
    vim.fn.mkdir(tmp .. '/logseq', 'p')
    vim.fn.writefile({ '{:x 1}' }, tmp .. '/logseq/config.edn')
    -- walk_up does not resolve symlinks, so expect tmp verbatim.
    assert.are.equal(tmp, graph.find_root_from(tmp .. '/logseq/config.edn'))
  end)

  it('is nil-safe', function()
    assert.is_nil(graph.find_root_from(nil))
    assert.is_nil(graph.find_root_from(''))
  end)
end)

describe('graph.discover_graphs (M5.1)', function()
  local saved_g
  local tmps
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    tmps = {}
  end)
  after_each(function()
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

  local function mkpages(root)
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    vim.fn.writefile({ '- x' }, root .. '/pages/A.md')
  end

  local function mkedn(root)
    vim.fn.mkdir(root .. '/logseq', 'p')
    vim.fn.writefile({ '{:x 1}' }, root .. '/logseq/config.edn')
  end

  it('finds roots via both markers, skips non-roots, sorts by name', function()
    local tmp = track(vim.fn.tempname())
    mkpages(tmp .. '/zeta') -- created first, sorts last
    mkedn(tmp .. '/alpha')
    vim.fn.mkdir(tmp .. '/plain/pages', 'p') -- pages/ alone is not a root
    config.setup({ graphs_dirs = { tmp }, graphs_depth = 2 })
    assert.are.same({
      { name = 'alpha', path = tmp .. '/alpha' },
      { name = 'zeta', path = tmp .. '/zeta' },
    }, graph.discover_graphs())
  end)

  it('respects graphs_depth', function()
    local tmp = track(vim.fn.tempname())
    mkpages(tmp .. '/shallow') -- level 1
    mkpages(tmp .. '/mid/deep') -- level 2
    config.setup({ graphs_dirs = { tmp }, graphs_depth = 1 })
    assert.are.same({
      { name = 'shallow', path = tmp .. '/shallow' },
    }, graph.discover_graphs())
  end)

  it('checks the scan dir itself (level 0)', function()
    local tmp = track(vim.fn.tempname())
    mkpages(tmp)
    config.setup({ graphs_dirs = { tmp }, graphs_depth = 0 })
    assert.are.same({
      { name = vim.fn.fnamemodify(tmp, ':t'), path = tmp },
    }, graph.discover_graphs())
  end)

  it('skips hidden dirs and does not descend into found roots', function()
    local tmp = track(vim.fn.tempname())
    mkpages(tmp .. '/.hiddenroot')
    mkpages(tmp .. '/outer')
    mkpages(tmp .. '/outer/inner') -- nested root prunes to the outer graph
    config.setup({ graphs_dirs = { tmp }, graphs_depth = 3 })
    assert.are.same({
      { name = 'outer', path = tmp .. '/outer' },
    }, graph.discover_graphs())
  end)

  it('keeps same-basename graphs distinct and dedupes scan dirs', function()
    local tmp1 = track(vim.fn.tempname())
    local tmp2 = track(vim.fn.tempname())
    mkpages(tmp1 .. '/dup')
    mkpages(tmp2 .. '/dup')
    config.setup({ graphs_dirs = { tmp2, tmp1, tmp1 }, graphs_depth = 1 })
    local found = graph.discover_graphs()
    assert.are.equal(2, #found)
    assert.are.equal('dup', found[1].name)
    assert.are.equal('dup', found[2].name)
    local paths = { found[1].path, found[2].path }
    table.sort(paths)
    local expected = { tmp1 .. '/dup', tmp2 .. '/dup' }
    table.sort(expected)
    assert.are.same(expected, paths)
  end)

  it('returns {} for empty, missing, or invalid scan config', function()
    assert.are.same({}, graph.discover_graphs()) -- defaults: graphs_dirs = {}
    config.setup({ graphs_dirs = { '/tmp/no-such-logseq-graph-xyz', '', 42 } })
    assert.are.same({}, graph.discover_graphs())
  end)
end)

describe('graph.find_root order (M5.3)', function()
  local saved_g
  local saved_cwd
  local orig_buf
  local tmps
  local bufs
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    graph._set_state_file(vim.fn.tempname()) -- hermetic: no real active graph
    tmps = {}
    bufs = {}
    saved_cwd = vim.fn.getcwd()
    orig_buf = vim.api.nvim_get_current_buf()
  end)
  after_each(function()
    pcall(vim.api.nvim_set_current_buf, orig_buf)
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.fn.chdir(saved_cwd)
    for _, t in ipairs(tmps) do
      vim.fn.delete(t, 'rf')
    end
    graph._set_state_file(nil)
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

  -- Fresh unnamed buffer (a safe switch: never fails on modified buffers).
  local function home()
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(bufs, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = false
    return buf
  end

  -- Current buffer inside a graph: home first so :edit never hits E37.
  local function edit_in(path)
    home()
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    table.insert(bufs, vim.api.nvim_get_current_buf())
  end

  -- :edit resolves symlinks (macOS /tmp -> /private/tmp); compare canonical.
  local function canon(path)
    return vim.fn.resolve(path)
  end

  local missing = '/tmp/no-such-logseq-graph-xyz'

  it('buffer walk-up beats a valid graph_path', function()
    local a = mkgraph(track(vim.fn.tempname()))
    local b = mkgraph(track(vim.fn.tempname()))
    config.setup({ graph_path = a })
    edit_in(b .. '/pages/A.md')
    assert.are.equal(canon(b), graph.find_root())
  end)

  it('buffer walk-up beats even a set-but-missing graph_path', function()
    local b = mkgraph(track(vim.fn.tempname()))
    config.setup({ graph_path = missing })
    edit_in(b .. '/pages/A.md')
    assert.are.equal(canon(b), graph.find_root())
  end)

  it('active graph beats graph_path when the buffer is outside', function()
    local a = mkgraph(track(vim.fn.tempname()))
    local b = mkgraph(track(vim.fn.tempname()))
    config.setup({ graph_path = a })
    graph.set_active(b)
    home()
    assert.are.equal(b, graph.find_root())
  end)

  it('graph_path applies when buffer and active miss', function()
    local a = mkgraph(track(vim.fn.tempname()))
    config.setup({ graph_path = a })
    home()
    assert.are.equal(a, graph.find_root())
  end)

  it('cwd walk-up is the last resort', function()
    local b = mkgraph(track(vim.fn.tempname()))
    home()
    vim.fn.chdir(b)
    assert.are.equal(canon(b), graph.find_root())
  end)

  it('set-but-missing graph_path short-circuits: no cwd fallback', function()
    local b = mkgraph(track(vim.fn.tempname()))
    config.setup({ graph_path = missing })
    home()
    vim.fn.chdir(b) -- inside a live graph, yet strictness wins
    assert.is_nil(graph.find_root())
  end)

  it('returns nil when everything misses', function()
    local plain = track(vim.fn.tempname())
    vim.fn.mkdir(plain, 'p')
    home()
    vim.fn.chdir(plain)
    assert.is_nil(graph.find_root())
  end)
end)
