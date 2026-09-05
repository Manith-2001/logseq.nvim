local view = require('logseq.view')
local index_mod = require('logseq.index')
local config = require('logseq.config')
local graph = require('logseq.graph')
local logseq = require('logseq')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('view.entry_title with counts (M6.3)', function()
  it('strips global-view count suffixes back to titles', function()
    assert.are.equal('A', view.entry_title('● A →1 ←1'))
    assert.are.equal('B', view.entry_title('● B →1 ←0'))
    assert.are.equal('World', view.entry_title('○ World ←1'))
    assert.are.equal('a b', view.entry_title('● a b →0 ←3'))
  end)

  it('still parses plain local-view entries', function()
    assert.are.equal('B', view.entry_title('● B'))
    assert.are.equal('World', view.entry_title('○ World'))
    assert.is_nil(view.entry_title('# graph · graph overview'))
    assert.is_nil(view.entry_title('2 pages · 1 journals · 1 dangling · 2 edges'))
  end)
end)

describe('view.all_lines pure layout (M6.3)', function()
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

  it('renders stats plus Pages/Journals/Dangling with counts', function()
    -- Fixture: A -> [[World]] (dangling), B -> [[A]], lone journal.
    local idx = index_mod.build(fixture)
    assert.are.same({
      '# graph · graph overview',
      '',
      '2 pages · 1 journals · 1 dangling · 2 edges',
      '',
      '## Pages (2)',
      '● A →1 ←1',
      '● B →1 ←0',
      '',
      '## Journals (1)',
      '● 2026_08_27 →0 ←0',
      '',
      '## Dangling (1)',
      '○ World ←1',
    }, view.all_lines(idx, { graph_name = 'graph' }))
  end)

  it('hides dangling with show_dangling=false, section count follows', function()
    local idx = index_mod.build(fixture)
    local lines = view.all_lines(idx, { graph_name = 'graph', show_dangling = false })
    assert.are.same({
      '# graph · graph overview',
      '',
      '2 pages · 1 journals · 1 dangling · 2 edges', -- stats stay graph totals
      '',
      '## Pages (2)',
      '● A →1 ←1',
      '● B →1 ←0',
      '',
      '## Journals (1)',
      '● 2026_08_27 →0 ←0',
      '',
      '## Dangling (0)',
      '(none)',
    }, lines)
  end)

  it('renders an empty graph as empty sections, never an error', function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    local ok, lines = pcall(view.all_lines, index_mod.build(root), { graph_name = 'graph' })
    vim.fn.delete(root, 'rf')
    assert.is_true(ok)
    assert.are.same({
      '# graph · graph overview',
      '',
      '0 pages · 0 journals · 0 dangling · 0 edges',
      '',
      '## Pages (0)',
      '(none)',
      '',
      '## Journals (0)',
      '(none)',
      '',
      '## Dangling (0)',
      '(none)',
    }, lines)
  end)
end)

-- Shared harness: tmp graph, clean home buffer, notify capture, pick stub.
local function harness()
  local H = {}
  H.notes = {}
  H.bufs = {}
  H.tmps = {}
  H.saved_cwd = vim.fn.getcwd()
  H.orig_notify = vim.notify
  H.orig_input = vim.ui.input
  H.tele = require('logseq.telescope')
  H.orig_pick = H.tele.pick
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
    H.tele.pick = function()
      error('pick() called without a test stub')
    end
  end
  function H.teardown()
    vim.notify = H.orig_notify
    vim.ui.input = H.orig_input
    H.tele.pick = H.orig_pick
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

describe('view.open_all buffer behavior (M6.3)', function()
  local H
  before_each(function()
    H = harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('opens a global scratch buffer with kind=all state and content', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open_all({ root = root })
    H.track_current()
    assert.are.equal('logseq-graph', vim.bo[buf].filetype)
    assert.are.equal('nofile', vim.bo[buf].buftype)
    assert.is_false(vim.bo[buf].modifiable)
    local st = vim.api.nvim_buf_get_var(buf, 'logseq_graph')
    assert.are.equal(root, st.root)
    assert.are.equal('all', st.kind)
    assert.is_true(st.show_dangling)
    local idx = index_mod.build(root)
    local name = vim.fn.fnamemodify(root, ':t')
    assert.are.same(view.all_lines(idx, { graph_name = name }), H.buf_lines(buf))
    assert.are.equal(1, H.find_line(buf, '# ' .. name .. ' · graph overview'))
  end)

  it('binds P for the picker and no depth keys', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open_all({ root = root })
    H.track_current()
    local descs = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      descs[map.desc] = true
    end
    assert.is_true(descs['Logseq: pick page for local view'] == true)
    assert.is_true(descs['Logseq: open graph entry'] == true)
    assert.is_nil(descs['Logseq: graph depth 1'])
    assert.is_nil(descs['Logseq: graph depth 2'])
  end)

  it('jump opens counted entries, existing and dangling', function()
    local root = H.tmpgraph({ A = { '- [[B]] and [[Missing M63]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open_all({ root = root })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '● B →0 ←1'), 0 })
    view.jump()
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/B.md', vim.api.nvim_buf_get_name(0))
    -- The overview wiped itself on :edit (bufhidden=wipe); reopen for part two.
    buf = view.open_all({ root = root })
    H.track_current()
    vim.api.nvim_win_set_cursor(0, { H.find_line(buf, '○ Missing M63 ←1'), 0 })
    view.jump()
    H.track_current()
    local name = vim.api.nvim_buf_get_name(0)
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Missing M63.md', name)
    assert.are.equal(0, vim.fn.filereadable(name))
  end)

  it('refresh and toggle_dangling work on the global buffer', function()
    local root = H.tmpgraph({ A = { '- [[Missing M63]]' } })
    H.home()
    local buf = view.open_all({ root = root })
    H.track_current()
    assert.is_true(H.contains(buf, '○ Missing M63 ←1'))
    assert.is_false(view.toggle_dangling(buf))
    assert.is_true(H.contains(buf, '## Dangling (0)'))
    assert.is_true(view.toggle_dangling(buf))
    vim.fn.writefile({ '- lone' }, root .. '/pages/C.md')
    view.refresh(buf)
    assert.is_true(H.contains(buf, '● C →0 ←0'))
  end)

  it('set_depth warns and leaves a global buffer alone', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open_all({ root = root })
    H.track_current()
    local before = H.buf_lines(buf)
    view.set_depth(buf, 2)
    assert.is_true(H.notified(vim.log.levels.WARN, 'local explorer only'))
    assert.are.same(before, H.buf_lines(buf))
  end)
end)

describe('view.pick_page (M6.3)', function()
  local H
  before_each(function()
    H = harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('lists titles with counts and opens the local view on choice', function()
    local root = H.tmpgraph({ A = { '- [[B]]' }, B = { '- lone' } })
    H.home()
    local buf = view.open_all({ root = root })
    H.track_current()
    local seen, seen_opts
    H.tele.pick = function(items, opts)
      seen, seen_opts = items, opts
      assert.is_not_nil(seen_opts.prompt_title:find('Logseq Graph', 1, true))
      for _, item in ipairs(items) do
        if item.title == 'B' then
          opts.on_choice(item)
          return
        end
      end
      error('B missing from picker')
    end
    view.pick_page(buf)
    H.track_current()
    local titles = {}
    for _, item in ipairs(seen) do
      table.insert(titles, item.title)
    end
    assert.are.same({ 'A', 'B' }, titles) -- sorted, dangling-free here
    assert.are.equal('● B →0 ←1', seen_opts.format_item(seen[2]))
    -- Choice opened the local explorer for B (plain local entries there).
    assert.are.equal('logseq-graph', vim.bo[vim.api.nvim_get_current_buf()].filetype)
    assert.is_true(H.contains(vim.api.nvim_get_current_buf(), '● A'))
    local st = vim.api.nvim_buf_get_var(vim.api.nvim_get_current_buf(), 'logseq_graph')
    assert.are.equal('local', st.kind)
    assert.are.equal('B', st.title)
  end)

  it('formats dangling items and hides them when the buffer does', function()
    local root = H.tmpgraph({ A = { '- [[Missing M63]]' } })
    H.home()
    local buf = view.open_all({ root = root })
    H.track_current()
    local seen, seen_format
    H.tele.pick = function(items, opts)
      seen, seen_format = items, opts.format_item
    end
    view.pick_page(buf)
    assert.are.equal(2, #seen)
    assert.are.equal('○ Missing M63 ←1', seen_format(seen[2]))
    view.toggle_dangling(buf) -- hide dangling, pick again
    H.tele.pick = function(items)
      seen = items
    end
    view.pick_page(buf)
    assert.are.same({ 'A' }, { seen[1].title })
    assert.are.equal(1, #seen)
  end)

  it('warns instead of picking from an empty graph', function()
    local root = H.tmpgraph({})
    H.home()
    local buf = view.open_all({ root = root })
    H.track_current()
    local called = false
    H.tele.pick = function()
      called = true
    end
    view.pick_page(buf)
    assert.is_false(called)
    assert.is_true(H.notified(vim.log.levels.WARN, 'no pages found to pick'))
  end)
end)

describe('graph_view_all facade (M6.3)', function()
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
    vim.fn.chdir('/tmp') -- outside any graph, like the M6.2 strict case
    local buf = vim.api.nvim_get_current_buf()
    assert.is_nil(logseq.graph_view_all())
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.ERROR, 'graph root not found'))
  end)

  it('opens the global overview for the resolved root', function()
    H.home()
    local buf = logseq.graph_view_all({ root = fixture })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.equal('logseq-graph', vim.bo[buf].filetype)
    local lines = H.buf_lines(buf)
    assert.are.equal('# graph · graph overview', lines[1])
    assert.are.equal('2 pages · 1 journals · 1 dangling · 2 edges', lines[3])
    assert.is_true(H.contains(buf, '● A →1 ←1'))
    assert.is_true(H.contains(buf, '○ World ←1'))
  end)

  it('warns when the graph exceeds graph_max_files', function()
    config.setup({ graph_max_files = 1 }) -- fixture holds 3 files
    H.home()
    local buf = vim.api.nvim_get_current_buf()
    assert.is_nil(logseq.graph_view_all({ root = fixture }))
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'too large'))
  end)
end)
