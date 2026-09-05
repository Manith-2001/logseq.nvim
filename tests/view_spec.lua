local view = require('logseq.view')
local index_mod = require('logseq.index')
local config = require('logseq.config')
local graph = require('logseq.graph')
local logseq = require('logseq')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('view.entry_title (M6.2)', function()
  it('parses entry lines back to titles', function()
    assert.are.equal('B', view.entry_title('● B'))
    assert.are.equal('World', view.entry_title('○ World'))
    assert.are.equal('a b', view.entry_title('● a b'))
  end)

  it('parses tree page rows and context rows (M8.2)', function()
    assert.are.equal('B', view.entry_title('└─ ● B'))
    assert.are.equal('World', view.entry_title('├─ ○ World'))
    assert.are.equal('a b', view.entry_title('└─ ● a b'))
    assert.are.equal('B', view.entry_title('   └─ "- Ref to [[A]]" → B:1'))
    assert.are.equal('B', view.entry_title('│  ├─ "- Ref to [[A]]" → B:2'))
    assert.are.equal(1, view.entry_lnum('   └─ "- Ref to [[A]]" → B:1'))
    assert.are.equal(2, view.entry_lnum('│  ├─ "- Ref to [[A]]" → B:2'))
    assert.is_nil(view.entry_lnum('└─ ● B'))
    assert.is_nil(view.entry_lnum('● B'))
  end)

  it('returns nil for headers, blanks, placeholders, overflow, via, and junk', function()
    assert.is_nil(view.entry_title('# A · graph (depth 1)'))
    assert.is_nil(view.entry_title('## Outgoing (1)'))
    assert.is_nil(view.entry_title('## Incoming (1)'))
    assert.is_nil(view.entry_title(''))
    assert.is_nil(view.entry_title('(none)'))
    assert.is_nil(view.entry_title('   └─ more=2'))
    assert.is_nil(view.entry_title('│  └─ more=1'))
    assert.is_nil(view.entry_title('via B'))
    assert.is_nil(view.entry_title('- [[A]]'))
    assert.is_nil(view.entry_title(nil))
  end)
end)

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

  it('renders Outgoing/Incoming trees with exists/dangling markers', function()
    -- Fixture: A -> [[World]] (dangling), B -> [[A]].
    local idx = index_mod.build(fixture)
    assert.are.same({
      '# A · graph (depth 1)',
      '',
      '## Outgoing (1)',
      '└─ ○ World',
      '',
      '## Incoming (1)',
      '└─ ● B',
      '   └─ "- Ref to [[A]]" → B:1',
    }, view.lines(idx, 'A', 1, { graph_name = 'graph' }))
  end)

  it('renders (none) for empty sections', function()
    local idx = index_mod.build(fixture)
    assert.are.same({
      '# B · graph (depth 1)',
      '',
      '## Outgoing (1)',
      '└─ ● A',
      '',
      '## Incoming (0)',
      '(none)',
    }, view.lines(idx, 'B', 1, { graph_name = 'graph' }))
  end)

  it('renders unknown titles as empty, never an error', function()
    local idx = index_mod.build(fixture)
    assert.are.same({
      '# Nope · graph (depth 1)',
      '',
      '## Outgoing (0)',
      '(none)',
      '',
      '## Incoming (0)',
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
      '## Outgoing (0)',
      '(none)',
      '',
      '## Incoming (1)',
      '└─ ● B',
      '   └─ "- Ref to [[A]]" → B:1',
    }, view.lines(idx, 'A', 1, { graph_name = 'graph', show_dangling = false }))
  end)
end)

-- Shared harness: tmp graph, clean home buffer, notify + input capture.
local function harness()
  local H = {}
  H.notes = {}
  H.bufs = {}
  H.tmps = {}
  H.saved_cwd = vim.fn.getcwd()
  H.orig_notify = vim.notify
  H.orig_input = vim.ui.input
  function H.setup()
    H.saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    graph._set_state_file(vim.fn.tempname()) -- no real active graph
    vim.notify = function(msg, level)
      table.insert(H.notes, { msg = msg, level = level })
    end
    vim.ui.input = function(_, cb) -- default: cancel the prompt
      cb(nil)
    end
  end
  function H.teardown()
    vim.notify = H.orig_notify
    vim.ui.input = H.orig_input
    graph._set_state_file(nil)
    for _, b in ipairs(H.bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    for _, t in ipairs(H.tmps) do
      vim.fn.delete(t, 'rf')
    end
    vim.fn.chdir(H.saved_cwd)
    vim.g.logseq = H.saved_g
    config._reset()
  end
  function H.tmpgraph(files)
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    for name, lines in pairs(files or {}) do
      vim.fn.writefile(lines, root .. '/pages/' .. name .. '.md')
    end
    table.insert(H.tmps, root)
    return root
  end
  function H.home()
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(H.bufs, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = false
    return buf
  end
  function H.track_current()
    table.insert(H.bufs, vim.api.nvim_get_current_buf())
  end
  function H.notified(level, fragment)
    for _, n in ipairs(H.notes) do
      if n.level == level and n.msg:find(fragment, 1, true) then
        return true
      end
    end
    return false
  end
  function H.buf_lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  function H.find_line(buf, text)
    for i, line in ipairs(H.buf_lines(buf)) do
      if line == text then
        return i
      end
    end
    return nil
  end
  function H.contains(buf, text)
    return H.find_line(buf, text) ~= nil
  end
  return H
end

describe('view depth-2 layout (M6.2)', function()
  local H
  before_each(function()
    H = harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('adds an exactly-two-hops section grouped under via at depth 2', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- [[C]]' }, C = { '- lone' } })
    local idx = index_mod.build(root)
    assert.are.same({
      '# A · graph (depth 2)',
      '',
      '## Outgoing (1)',
      '└─ ● B',
      '',
      '## Incoming (0)',
      '(none)',
      '',
      '## 2 hops (1)',
      'via B',
      '└─ ● C',
    }, view.lines(idx, 'A', 2, { graph_name = 'graph' }))
  end)
end)

describe('view.open buffer behavior (M6.2)', function()
  local H
  before_each(function()
    H = harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('opens a logseq-graph scratch buffer with state and content', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open({ root = root, title = 'A' })
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
    local buf = view.open({ root = root, title = 'A' })
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
    local buf = view.open({ root = root, title = 'A' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '└─ ● B'), 0 })
    view.jump()
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/B.md', vim.api.nvim_buf_get_name(0))
  end)

  it('jump opens dangling refs lazily without creating the file', function()
    local root = H.tmpgraph({ A = { '- [[Missing M62]]' } })
    H.home()
    local buf = view.open({ root = root, title = 'A' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '└─ ○ Missing M62'), 0 })
    view.jump()
    H.track_current()
    local name = vim.api.nvim_buf_get_name(0)
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Missing M62.md', name)
    assert.are.equal(0, vim.fn.filereadable(name))
    assert.is_true(vim.b[vim.api.nvim_get_current_buf()].logseq_dangling)
  end)

  it('jump warns and stays put off entries', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open({ root = root, title = 'A' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- header line
    view.jump()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'no graph entry'))
  end)

  it('refresh picks up links added on disk', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open({ root = root, title = 'A' })
    H.track_current()
    assert.is_false(H.contains(buf, '└─ ● C'))
    vim.fn.writefile({ '- lone' }, root .. '/pages/C.md')
    vim.fn.writefile({ '- [[B]] and [[C]]' }, root .. '/pages/A.md')
    view.refresh(buf)
    assert.is_true(H.contains(buf, '└─ ● C'))
  end)

  it('set_depth toggles the 2-hops section', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- [[C]]' }, C = { '- lone' } })
    H.home()
    local buf = view.open({ root = root, title = 'A' })
    H.track_current()
    assert.is_false(H.contains(buf, '## 2 hops (1)'))
    view.set_depth(buf, 2)
    assert.is_true(H.contains(buf, '## 2 hops (1)'))
    assert.is_true(H.contains(buf, '└─ ● C'))
    view.set_depth(buf, 1)
    assert.is_false(H.contains(buf, '## 2 hops (1)'))
  end)

  it('toggle_dangling hides and restores ○ entries', function()
    local root = H.tmpgraph({ A = { '- [[Missing M62]]' } })
    H.home()
    local buf = view.open({ root = root, title = 'A' })
    H.track_current()
    assert.is_true(H.contains(buf, '└─ ○ Missing M62'))
    assert.is_false(view.toggle_dangling(buf))
    assert.is_false(H.contains(buf, '└─ ○ Missing M62'))
    assert.is_true(H.contains(buf, '## Outgoing (0)'))
    assert.is_true(view.toggle_dangling(buf))
    assert.is_true(H.contains(buf, '└─ ○ Missing M62'))
  end)

  it('close deletes the explorer buffer', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open({ root = root, title = 'A' })
    H.track_current()
    view.close(buf)
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)
end)

describe('graph_view facade (M6.2)', function()
  local H
  before_each(function()
    H = harness()
    H.setup()
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
    view.close(ok_buf)
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
    view.close(buf)
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
      '## Outgoing (0)',
      '(none)',
      '',
      '## Incoming (1)',
      '└─ ● A',
      '   └─ "- Hello [[World]]" → A:1',
    }, H.buf_lines(buf))
  end)
end)

describe('view.lines incoming tree + context (M8.2)', function()
  local H
  before_each(function()
    H = harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('groups context rows under each source with │ continuation', function()
    local root = H.tmpgraph({
      T = { '- lone' },
      A = { '- first [[T]]', '- second [[T]]' },
      B = { '- only [[T]]' },
    })
    local idx = index_mod.build(root)
    assert.are.same({
      '# T · graph (depth 1)',
      '',
      '## Outgoing (0)',
      '(none)',
      '',
      '## Incoming (2)',
      '├─ ● A',
      '│  ├─ "- first [[T]]" → A:1',
      '│  └─ "- second [[T]]" → A:2',
      '└─ ● B',
      '   └─ "- only [[T]]" → B:1',
    }, view.lines(idx, 'T', 1, { graph_name = 'graph' }))
  end)

  it('caps context per pair with more=N, counts stay on page rows', function()
    local root = H.tmpgraph({
      T = { '- lone' },
      A = { '- l1 [[T]]', '- l2 [[T]]', '- l3 [[T]]', '- l4 [[T]]', '- l5 [[T]]' },
    })
    local idx = index_mod.build(root)
    assert.are.same({
      '# T · graph (depth 1)',
      '',
      '## Outgoing (0)',
      '(none)',
      '',
      '## Incoming (1)',
      '└─ ● A',
      '   ├─ "- l1 [[T]]" → A:1',
      '   ├─ "- l2 [[T]]" → A:2',
      '   ├─ "- l3 [[T]]" → A:3',
      '   └─ more=2',
    }, view.lines(idx, 'T', 1, { graph_name = 'graph' }))
  end)

  it('truncates long blocks with … keeping the → Src:lnum suffix', function()
    local long = string.rep('x', 100)
    local root = H.tmpgraph({ T = { '- lone' }, A = { '- ' .. long .. ' [[T]]' } })
    local idx = index_mod.build(root)
    local lines = view.lines(idx, 'T', 1, { graph_name = 'graph' })
    local ctx = lines[#lines]
    assert.is_not_nil(ctx:find('…', 1, true))
    assert.is_not_nil(ctx:match('→ A:1$'))
    local inner = ctx:match('"([^"]*)" →')
    assert.is_not_nil(inner)
    assert.are.equal(80, vim.fn.strchars(inner))
  end)

  it('shows no context children under Outgoing rows', function()
    local root = H.tmpgraph({ T = { '- lone' }, A = { '- a [[T]]', '- b [[T]]' } })
    local idx = index_mod.build(root)
    assert.are.same({
      '# A · graph (depth 1)',
      '',
      '## Outgoing (1)',
      '└─ ● T',
      '',
      '## Incoming (0)',
      '(none)',
    }, view.lines(idx, 'A', 1, { graph_name = 'graph' }))
  end)
end)

describe('view.jump jump-to-line (M8.2)', function()
  local H
  before_each(function()
    H = harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('lands on the exact source line from a context row', function()
    local root = H.tmpgraph({ T = { '- lone' }, A = { '- one', '- two [[T]]', '- three' } })
    H.home()
    local buf = view.open({ root = root, title = 'T' })
    H.track_current()
    local ctx = '   └─ "- two [[T]]" → A:2'
    assert.is_not_nil(H.find_line(buf, ctx))
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, ctx), 0 })
    view.jump()
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/A.md', vim.api.nvim_buf_get_name(0))
    assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it('opens page rows at the top of the file', function()
    local root = H.tmpgraph({ T = { '- lone' }, A = { '- one', '- two [[T]]' } })
    H.home()
    local buf = view.open({ root = root, title = 'T' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '└─ ● A'), 0 })
    view.jump()
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/A.md', vim.api.nvim_buf_get_name(0))
    assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it('warns and stays put on overflow and header rows', function()
    local root = H.tmpgraph({
      T = { '- lone' },
      A = { '- l1 [[T]]', '- l2 [[T]]', '- l3 [[T]]', '- l4 [[T]]' },
    })
    H.home()
    local buf = view.open({ root = root, title = 'T' })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '   └─ more=1'), 0 })
    view.jump()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'no graph entry'))
    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- header line
    view.jump()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
  end)
end)

describe('view.lines 2-hops via groups (M8.3)', function()
  local H
  before_each(function()
    H = harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('groups 2-hop pages under each intermediate; shared pages repeat', function()
    -- A -> B, C; B -> D; C -> D, E: D is reachable via both.
    local root = H.tmpgraph({
      A = { '- [[B]] [[C]]' },
      B = { '- [[D]]' },
      C = { '- [[D]] [[E]]' },
      D = { '- lone' },
      E = { '- lone' },
    })
    local idx = index_mod.build(root)
    assert.are.same({
      '# A · graph (depth 2)',
      '',
      '## Outgoing (2)',
      '├─ ● B',
      '└─ ● C',
      '',
      '## Incoming (0)',
      '(none)',
      '',
      '## 2 hops (2)',
      'via B',
      '└─ ● D',
      'via C',
      '├─ ● D',
      '└─ ● E',
    }, view.lines(idx, 'A', 2, { graph_name = 'graph' }))
  end)

  it('groups incoming-direction paths under via too', function()
    -- X -> B -> A: X is two edges behind the center.
    local root = H.tmpgraph({ A = { '- lone' }, B = { '- [[A]]' }, X = { '- [[B]]' } })
    local idx = index_mod.build(root)
    assert.are.same({
      '# A · graph (depth 2)',
      '',
      '## Outgoing (0)',
      '(none)',
      '',
      '## Incoming (1)',
      '└─ ● B',
      '   └─ "- [[A]]" → B:1',
      '',
      '## 2 hops (1)',
      'via B',
      '└─ ● X',
    }, view.lines(idx, 'A', 2, { graph_name = 'graph' }))
  end)

  it('omits empty groups, (none) when no 2-hop pages exist', function()
    local bare = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    local idx = index_mod.build(bare)
    local lines = view.lines(idx, 'A', 2, { graph_name = 'graph' })
    assert.are.same({ '## 2 hops (0)', '(none)' }, { lines[#lines - 1], lines[#lines] })
    -- B reaches only C, which is already 1 hop away: no group for B.
    local root = H.tmpgraph({ A = { '- [[B]] [[C]]' }, B = { '- [[C]]' }, C = { '- lone' } })
    local idx2 = index_mod.build(root)
    local lines2 = view.lines(idx2, 'A', 2, { graph_name = 'graph' })
    assert.are.same({ '## 2 hops (0)', '(none)' }, { lines2[#lines2 - 1], lines2[#lines2] })
  end)

  it('hides dangling intermediates and orphan pages with show_dangling=false', function()
    -- X -> [[M]] <- A -> B -> Y: X hangs off dangling M.
    local root = H.tmpgraph({
      A = { '- [[M]] [[B]]' },
      B = { '- [[Y]]' },
      X = { '- [[M]]' },
      Y = { '- lone' },
    })
    local idx = index_mod.build(root)
    assert.are.same({
      '# A · graph (depth 2)',
      '',
      '## Outgoing (2)',
      '├─ ● B',
      '└─ ○ M',
      '',
      '## Incoming (0)',
      '(none)',
      '',
      '## 2 hops (2)',
      'via B',
      '└─ ● Y',
      'via M',
      '└─ ● X',
    }, view.lines(idx, 'A', 2, { graph_name = 'graph' }))
    assert.are.same({
      '# A · graph (depth 2)',
      '',
      '## Outgoing (1)',
      '└─ ● B',
      '',
      '## Incoming (0)',
      '(none)',
      '',
      '## 2 hops (1)',
      'via B',
      '└─ ● Y',
    }, view.lines(idx, 'A', 2, { graph_name = 'graph', show_dangling = false }))
  end)

  it('warns and stays put on via subheadings', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- [[C]]' }, C = { '- lone' } })
    H.home()
    local buf = view.open({ root = root, title = 'A', depth = 2 })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, 'via B'), 0 })
    view.jump()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'no graph entry'))
  end)
end)
