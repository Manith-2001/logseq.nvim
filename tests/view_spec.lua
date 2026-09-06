local view = require('logseq.view')
local gv = require('logseq.graph_view')
local index_mod = require('logseq.index')
local config = require('logseq.config')
local graph = require('logseq.graph')
local logseq = require('logseq')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('view.lines pure layout (M6.2)', function()
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

  it('renders Linked/Backlinks with exists/dangling markers', function()
    -- Fixture: A -> [[World]] (dangling), B -> [[A]].
    local idx = index_mod.build(fixture)
    assert.are.same({
      '# A · graph (depth 1)',
      '',
      '## Linked (1)',
      '○ World',
      '',
      '## Backlinks (1)',
      '● B',
    }, view.lines(idx, 'A', 1, { graph_name = 'graph' }))
  end)

  it('renders (none) for empty sections', function()
    local idx = index_mod.build(fixture)
    assert.are.same({
      '# B · graph (depth 1)',
      '',
      '## Linked (1)',
      '● A',
      '',
      '## Backlinks (0)',
      '(none)',
    }, view.lines(idx, 'B', 1, { graph_name = 'graph' }))
  end)

  it('renders unknown titles as empty, never an error', function()
    local idx = index_mod.build(fixture)
    assert.are.same({
      '# Nope · graph (depth 1)',
      '',
      '## Linked (0)',
      '(none)',
      '',
      '## Backlinks (0)',
      '(none)',
    }, view.lines(idx, 'Nope', 1, { graph_name = 'graph' }))
  end)

  it('clamps bogus depths to 1', function()
    local idx = index_mod.build(fixture)
    local one = view.lines(idx, 'A', 1, { graph_name = 'graph' })
    assert.are.same(one, view.lines(idx, 'A', 0, { graph_name = 'graph' }))
    assert.are.same(one, view.lines(idx, 'A', 99, { graph_name = 'graph' }))
  end)

  it('hides dangling entries with show_dangling=false, counts follow', function()
    local idx = index_mod.build(fixture)
    assert.are.same({
      '# A · graph (depth 1)',
      '',
      '## Linked (0)',
      '(none)',
      '',
      '## Backlinks (1)',
      '● B',
    }, view.lines(idx, 'A', 1, { graph_name = 'graph', show_dangling = false }))
  end)

  it('lines_with_map maps entry lines, not headers or placeholders', function()
    local idx = index_mod.build(fixture)
    local lines, map = view.lines_with_map(idx, 'A', 1, { graph_name = 'graph' })
    assert.is_nil(map['1']) -- header
    local found = {}
    for k, entry in pairs(map) do
      found[entry.title] = tonumber(k)
    end
    assert.are.equal(4, found['World']) -- '○ World' line
    assert.are.equal(7, found['B']) -- '● B' line
  end)
end)

-- Shared lifecycle (tests/harness.lua); the view-spec policy stays local:
-- vim.ui.input defaults to cancelling the prompt (see the before_each
-- blocks below).
local harness = require('tests.harness')

describe('view depth-2 layout (M6.2)', function()
  local H
  before_each(function()
    H = harness
    H.setup()
    vim.ui.input = function(_, cb) -- default: cancel the prompt
      cb(nil)
    end
  end)
  after_each(function()
    H.teardown()
  end)

  it('adds an exactly-two-hops section at depth 2', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- [[C]]' }, C = { '- lone' } })
    local idx = index_mod.build(root)
    assert.are.same({
      '# A · graph (depth 2)',
      '',
      '## Linked (1)',
      '● B',
      '',
      '## Backlinks (0)',
      '(none)',
      '',
      '## 2 hops (1)',
      '● C',
    }, view.lines(idx, 'A', 2, { graph_name = 'graph' }))
  end)
end)

describe('view.open buffer behavior (M6.2)', function()
  local H
  before_each(function()
    H = harness
    H.setup()
    vim.ui.input = function(_, cb) -- default: cancel the prompt
      cb(nil)
    end
  end)
  after_each(function()
    H.teardown()
  end)

  it('opens a logseq-graph scratch buffer with state and content', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.are.equal('logseq-graph', vim.bo[buf].filetype)
    assert.are.equal('nofile', vim.bo[buf].buftype)
    assert.are.equal('wipe', vim.bo[buf].bufhidden)
    assert.is_false(vim.bo[buf].modifiable)
    local st = vim.api.nvim_buf_get_var(buf, 'logseq_graph')
    assert.are.equal(root, st.root)
    assert.are.equal('A', st.title)
    assert.are.equal(1, st.depth)
    assert.is_true(st.show_dangling)
    local idx = index_mod.build(root)
    local name = vim.fn.fnamemodify(root, ':t')
    assert.are.same(view.lines(idx, 'A', 1, { graph_name = name }), H.buf_lines(buf))
  end)

  it('binds the explorer keys with descriptions', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    local descs = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      descs[map.desc] = true
    end
    for _, want in ipairs({
      'Logseq: open graph entry',
      'Logseq: close graph explorer',
      'Logseq: refresh graph explorer',
      'Logseq: graph depth 1',
      'Logseq: graph depth 2',
      'Logseq: toggle dangling entries',
    }) do
      assert.is_true(descs[want] == true, 'missing key: ' .. want)
    end
  end)

  it('jump opens the existing page under the cursor', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '● B'), 0 })
    gv.jump()
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/B.md', vim.api.nvim_buf_get_name(0))
  end)

  it('jump opens dangling refs lazily without creating the file', function()
    local root = H.tmpgraph({ A = { '- [[Missing M62]]' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '○ Missing M62'), 0 })
    gv.jump()
    H.track_current()
    local name = vim.api.nvim_buf_get_name(0)
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Missing M62.md', name)
    assert.are.equal(0, vim.fn.filereadable(name))
    assert.is_true(vim.b[vim.api.nvim_get_current_buf()].logseq_dangling)
  end)

  it('jump warns and stays put off entries', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- header line
    gv.jump()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'no graph entry'))
  end)

  it('refresh picks up links added on disk', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    assert.is_false(H.contains(buf, '● C'))
    vim.fn.writefile({ '- lone' }, root .. '/pages/C.md')
    vim.fn.writefile({ '- [[B]] and [[C]]' }, root .. '/pages/A.md')
    gv.refresh(buf)
    assert.is_true(H.contains(buf, '● C'))
  end)

  it('set_depth toggles the 2-hops section', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- [[C]]' }, C = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    assert.is_false(H.contains(buf, '## 2 hops (1)'))
    gv.set_depth(buf, 2)
    assert.is_true(H.contains(buf, '## 2 hops (1)'))
    assert.is_true(H.contains(buf, '● C'))
    gv.set_depth(buf, 1)
    assert.is_false(H.contains(buf, '## 2 hops (1)'))
  end)

  it('toggle_dangling hides and restores ○ entries', function()
    local root = H.tmpgraph({ A = { '- [[Missing M62]]' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    assert.is_true(H.contains(buf, '○ Missing M62'))
    assert.is_false(gv.toggle_dangling(buf))
    assert.is_false(H.contains(buf, '○ Missing M62'))
    assert.is_true(H.contains(buf, '## Linked (0)'))
    assert.is_true(gv.toggle_dangling(buf))
    assert.is_true(H.contains(buf, '○ Missing M62'))
  end)

  it('close deletes the explorer buffer', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    gv.close(buf)
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)
end)

describe('graph_view facade (M6.2)', function()
  local H
  before_each(function()
    H = harness
    H.setup()
    vim.ui.input = function(_, cb) -- default: cancel the prompt
      cb(nil)
    end
  end)
  after_each(function()
    H.teardown()
  end)

  it('errors with no graph root', function()
    H.home()
    vim.fn.chdir('/tmp') -- outside any graph, like the M1 strict case
    local buf = vim.api.nvim_get_current_buf()
    assert.is_nil(logseq.graph_view())
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.ERROR, 'graph root not found'))
  end)

  it('opens the explorer for an explicit title', function()
    H.home()
    local buf = logseq.graph_view({ root = fixture, title = 'A' })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.equal('logseq-graph', vim.bo[buf].filetype)
    assert.are.equal('# A · graph (depth 1)', H.buf_lines(buf)[1])
  end)

  it('derives the title from a pages buffer', function()
    H.home()
    vim.cmd('edit ' .. vim.fn.fnameescape(fixture .. '/pages/A.md'))
    H.track_current()
    local buf = logseq.graph_view({ root = fixture })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.equal('# A · graph (depth 1)', H.buf_lines(buf)[1])
  end)

  it('derives the title from a journals buffer', function()
    H.home()
    vim.cmd('edit ' .. vim.fn.fnameescape(fixture .. '/journals/2026_08_27.md'))
    H.track_current()
    local buf = logseq.graph_view({ root = fixture })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.equal('# 2026_08_27 · graph (depth 1)', H.buf_lines(buf)[1])
  end)

  it('refuses namespace titles with a warning', function()
    H.home()
    local buf = vim.api.nvim_get_current_buf()
    assert.is_nil(logseq.graph_view({ root = fixture, title = 'a/b' }))
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'out of scope for v0.1'))
  end)

  it('prompts when the title cannot be derived', function()
    H.home()
    vim.ui.input = function(prompt, cb)
      assert.is_not_nil(prompt.prompt:find('graph page', 1, true))
      cb('B')
    end
    local buf = logseq.graph_view({ root = fixture })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.equal('# B · graph (depth 1)', H.buf_lines(buf)[1])
  end)

  it('cancelling the prompt aborts quietly', function()
    H.home()
    local buf = vim.api.nvim_get_current_buf()
    assert.is_nil(logseq.graph_view({ root = fixture }))
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.INFO, 'graph view cancelled'))
  end)

  it('accepts the :LogseqGraph [title] arg', function()
    config.setup({ graph_path = fixture })
    H.home()
    local buf = logseq.graph_view({ args = 'A' })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.equal('# A · graph (depth 1)', H.buf_lines(buf)[1])
  end)

  it('warns when the graph exceeds graph_max_files', function()
    H.home()
    local buf = vim.api.nvim_get_current_buf()
    -- Sanity first (guard passes at defaults); then trip it.
    local ok_buf = logseq.graph_view({ root = fixture, title = 'A', depth = 1 })
    assert.is_not_nil(ok_buf)
    H.track_current()
    gv.close(ok_buf)
    config.setup({ graph_max_files = 1 }) -- fixture holds 3 files
    assert.is_nil(logseq.graph_view({ root = fixture, title = 'A' }))
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'too large'))
  end)

  it('honors depth 2 from opts and from config', function()
    H.home()
    local buf = logseq.graph_view({ root = fixture, title = 'A', depth = 2 })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.equal('# A · graph (depth 2)', H.buf_lines(buf)[1])
    assert.is_true(H.contains(buf, '## 2 hops (0)'))
    gv.close(buf)
    config.setup({ graph_depth = 2 })
    local buf2 = logseq.graph_view({ root = fixture, title = 'A' })
    assert.is_not_nil(buf2)
    H.track_current()
    assert.are.equal('# A · graph (depth 2)', H.buf_lines(buf2)[1])
  end)

  it('opens a dangling center with empty sections', function()
    H.home()
    local buf = logseq.graph_view({ root = fixture, title = 'World' })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.same({
      '# World · graph (depth 1)',
      '',
      '## Linked (0)',
      '(none)',
      '',
      '## Backlinks (1)',
      '● A',
    }, H.buf_lines(buf))
  end)
end)

describe('graph_view controller regressions (VIEW-01/PERF-01/API-02)', function()
  local H
  before_each(function()
    H = harness
    H.setup()
    vim.ui.input = function(_, cb) -- default: cancel the prompt
      cb(nil)
    end
  end)
  after_each(function()
    H.teardown()
  end)

  it('jump resolves titles that literally end in count-like suffixes (VIEW-01)', function()
    local root = H.tmpgraph({ A = { '- [[Evil ←1]]' }, ['Evil ←1'] = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '● Evil ←1'), 0 })
    gv.jump()
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Evil ←1.md', vim.api.nvim_buf_get_name(0))
  end)

  it('render stores the line map for navigation (VIEW-01)', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    local st = vim.api.nvim_buf_get_var(buf, 'logseq_graph')
    assert.are.equal('B', st.line_map[tostring(H.find_line(buf, '● B'))].title)
    assert.is_true(st.line_map[tostring(H.find_line(buf, '● B'))].exists)
  end)

  it(
    'refresh warns instead of stalling when the graph grew past graph_max_files (PERF-01)',
    function()
      local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
      H.home()
      local buf = gv.open({ root = root, title = 'A' })
      H.track_current()
      config.setup({ graph_max_files = 1 })
      local before = H.buf_lines(buf)
      gv.refresh(buf)
      assert.are.same(before, H.buf_lines(buf))
      assert.is_true(H.notified(vim.log.levels.WARN, 'too large'))
      config.setup({ graph_max_files = 2000 })
      vim.fn.writefile({ '- [[A]]' }, root .. '/pages/C.md')
      gv.refresh(buf)
      assert.is_true(H.contains(buf, '● C'))
    end
  )

  it('jump with explicit lnum works while another buffer is current (API-02)', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = gv.open({ root = root, title = 'A' })
    H.track_current()
    local other = vim.api.nvim_create_buf(true, false)
    table.insert(H.bufs, other)
    vim.cmd('split') -- keep the wipe-on-hide explorer displayed elsewhere
    vim.api.nvim_set_current_buf(other)
    local entry_lnum = H.find_line(buf, '● B')
    gv.jump(buf, entry_lnum) -- explicit lnum: no implicit current-window read
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/B.md', vim.api.nvim_buf_get_name(0))
  end)
end)
