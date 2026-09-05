local logseq = require('logseq')
local config = require('logseq.config')
local graph = require('logseq.graph')

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local fixture = repo .. '/tests/fixtures/graph'

describe('follow_link (M2)', function()
  local saved_g
  local saved_cwd
  local orig_notify
  local notes
  local bufs
  before_each(function()
    saved_g = vim.g.logseq
    vim.g.logseq = nil
    config._reset()
    config.setup({ graph_path = fixture })
    graph._set_state_file(vim.fn.tempname()) -- hermetic: no real active graph
    notes = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notes, { msg = msg, level = level })
    end
    bufs = {}
    saved_cwd = vim.fn.getcwd()
  end)
  after_each(function()
    vim.notify = orig_notify
    graph._set_state_file(nil)
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.fn.chdir(saved_cwd)
    vim.g.logseq = saved_g
    config._reset()
  end)

  -- Scratch window buffer with cursor placed; 0-based col like get_cursor().
  -- Marked unmodified so follow's :edit (which never forces) can switch.
  local function scratch(lines, col)
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(bufs, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
    vim.api.nvim_win_set_cursor(0, { 1, col })
    return buf
  end

  local function notified(level, fragment)
    for _, n in ipairs(notes) do
      if n.level == level and n.msg:find(fragment, 1, true) then
        return true
      end
    end
    return false
  end

  it('follows [[A]] to the existing page', function()
    scratch({ '- see [[A]]' }, 8)
    logseq.follow_link()
    table.insert(bufs, vim.api.nvim_get_current_buf())
    assert.are.equal(fixture .. '/pages/A.md', vim.api.nvim_buf_get_name(0))
  end)

  it('opens a dangling page without creating the file', function()
    scratch({ '- see [[No Such Page M2]]' }, 10)
    logseq.follow_link()
    table.insert(bufs, vim.api.nvim_get_current_buf())
    local name = vim.api.nvim_buf_get_name(0)
    assert.are.equal(fixture .. '/pages/No Such Page M2.md', name)
    assert.are.equal(0, vim.fn.filereadable(name))
  end)

  it('warns and stays put with no link under cursor', function()
    local buf = scratch({ '- plain line' }, 3)
    logseq.follow_link()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(notified(vim.log.levels.WARN, 'no link under cursor'))
  end)

  it('refuses [[a/b]] namespaces with a warning (M4, out of scope)', function()
    local buf = scratch({ '- see [[parent/child]]' }, 10)
    logseq.follow_link()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(notified(vim.log.levels.WARN, 'out of scope for v0.1'))
  end)

  it('errors with no graph root', function()
    config._reset() -- drop the fixture graph_path; g: is already nil
    vim.fn.chdir('/tmp') -- outside any graph, like the M1 strict case
    local buf = scratch({ '- [[A]]' }, 4)
    logseq.follow_link()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(notified(vim.log.levels.ERROR, 'graph root not found'))
  end)
end)

-- Shared harness for the M3 facade fns: tmp graph via opts.root (hermetic,
-- no config needed), clean home buffer per test, notify capture.
local function m3_harness()
  local H = {}
  H.notes = {}
  H.bufs = {}
  H.tmps = {}
  H.saved_cwd = vim.fn.getcwd()
  H.orig_notify = vim.notify
  H.orig_input = vim.ui.input
  H.config = require('logseq.config')
  H.graph = require('logseq.graph')
  H.tele = require('logseq.telescope')
  function H.setup()
    -- Hermetic: minimal_init.lua pre-seeds vim.g.logseq; clear per test.
    H.saved_g = vim.g.logseq
    vim.g.logseq = nil
    H.config._reset()
    H.graph._set_state_file(vim.fn.tempname()) -- no real active graph
    -- minimal_init puts telescope.nvim on the rtp, so pick() would take
    -- the real Telescope branch headless; tests stub the pick boundary.
    H.orig_pick = H.tele.pick
    vim.notify = function(msg, level)
      table.insert(H.notes, { msg = msg, level = level })
    end
    H.saved_cwd = vim.fn.getcwd()
  end
  function H.teardown()
    vim.notify = H.orig_notify
    vim.ui.input = H.orig_input
    H.tele.pick = H.orig_pick
    H.graph._set_state_file(nil)
    for _, b in ipairs(H.bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    for _, t in ipairs(H.tmps) do
      vim.fn.delete(t, 'rf')
    end
    vim.fn.chdir(H.saved_cwd)
    vim.g.logseq = H.saved_g
    H.config._reset()
  end
  -- Fresh tmp graph root with pages/ + journals/ dirs.
  function H.tmpgraph()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/pages', 'p')
    vim.fn.mkdir(root .. '/journals', 'p')
    table.insert(H.tmps, root)
    return root
  end
  -- Clean unmodified home buffer; :edit-based opens need this.
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
  return H
end

describe('today (M3)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('opens journals/<date>.md lazily without creating the file', function()
    local root = H.tmpgraph()
    H.home()
    logseq.today({ root = root, date = '2026_08_27' })
    H.track_current()
    local buf = vim.api.nvim_get_current_buf()
    assert.are.equal(
      vim.fn.resolve(root) .. '/journals/2026_08_27.md',
      vim.api.nvim_buf_get_name(buf)
    )
    assert.are.equal(0, vim.fn.filereadable(vim.api.nvim_buf_get_name(buf)))
    assert.is_true(vim.b[buf].logseq_dangling)
  end)

  it('defaults to os.date(journal_format)', function()
    local root = H.tmpgraph()
    H.home()
    logseq.today({ root = root })
    H.track_current()
    local stem = os.date(require('logseq.config').get().journal_format)
    assert.are.equal(
      vim.fn.resolve(root) .. '/journals/' .. stem .. '.md',
      vim.api.nvim_buf_get_name(0)
    )
  end)

  it('honors a custom journal_format', function()
    local root = H.tmpgraph()
    H.home()
    require('logseq.config').setup({ journal_format = '%Y-%m-%d' })
    logseq.today({ root = root })
    H.track_current()
    local stem = os.date('%Y-%m-%d')
    assert.are.equal(
      vim.fn.resolve(root) .. '/journals/' .. stem .. '.md',
      vim.api.nvim_buf_get_name(0)
    )
    require('logseq.config')._reset()
  end)

  it('errors with no graph root', function()
    H.home()
    vim.fn.chdir('/tmp') -- outside any graph; unnamed buf so cwd applies
    local buf = vim.api.nvim_get_current_buf()
    logseq.today()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.ERROR, 'graph root not found'))
  end)
end)

describe('new_page (M3)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('opens pages/<title>.md lazily without creating the file', function()
    local root = H.tmpgraph()
    H.home()
    logseq.new_page('M3 Page', { root = root })
    H.track_current()
    local buf = vim.api.nvim_get_current_buf()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/M3 Page.md', vim.api.nvim_buf_get_name(buf))
    assert.are.equal(0, vim.fn.filereadable(vim.api.nvim_buf_get_name(buf)))
    assert.is_true(vim.b[buf].logseq_dangling)
  end)

  it('accepts :LogseqNew cmd_opts ({args=title})', function()
    local root = H.tmpgraph()
    H.home()
    logseq.new_page({ args = 'Cmd Title' }, { root = root })
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Cmd Title.md', vim.api.nvim_buf_get_name(0))
  end)

  it('prompts when no title; opens the answer', function()
    local root = H.tmpgraph()
    H.home()
    vim.ui.input = function(_, on_confirm)
      on_confirm('Prompted Page')
    end
    logseq.new_page({ root = root })
    H.track_current()
    assert.are.equal(
      vim.fn.resolve(root) .. '/pages/Prompted Page.md',
      vim.api.nvim_buf_get_name(0)
    )
  end)

  it('cancel (nil input) stays put with an INFO note', function()
    local root = H.tmpgraph()
    local buf = H.home()
    vim.ui.input = function(_, on_confirm)
      on_confirm(nil)
    end
    logseq.new_page({ root = root })
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.INFO, 'new page cancelled'))
  end)

  it('blank input cancels too', function()
    local root = H.tmpgraph()
    local buf = H.home()
    vim.ui.input = function(_, on_confirm)
      on_confirm('   ')
    end
    logseq.new_page({ root = root })
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
  end)

  it('blank explicit title prompts instead of erroring', function()
    local root = H.tmpgraph()
    H.home()
    vim.ui.input = function(_, on_confirm)
      on_confirm('After Blank')
    end
    logseq.new_page('   ', { root = root })
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/After Blank.md', vim.api.nvim_buf_get_name(0))
  end)

  it('errors with no graph root', function()
    H.home()
    vim.fn.chdir('/tmp')
    local buf = vim.api.nvim_get_current_buf()
    logseq.new_page('Nope', {})
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.ERROR, 'graph root not found'))
  end)

  it('refuses a/b titles with a warning, explicit or prompted (M4)', function()
    local root = H.tmpgraph()
    local buf = H.home()
    logseq.new_page('parent/child', { root = root })
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'out of scope for v0.1'))
    vim.ui.input = function(_, on_confirm)
      on_confirm('a/b')
    end
    logseq.new_page({ root = root })
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
  end)
end)

describe('resolution order end-to-end (M5.3)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  -- Current buffer inside a graph: home first so :edit never hits E37.
  local function edit_in(path)
    H.home()
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    H.track_current()
  end

  it('opts.root wins over buffer, active, and graph_path', function()
    local a = H.tmpgraph()
    local b = H.tmpgraph()
    local c = H.tmpgraph()
    local d = H.tmpgraph()
    config.setup({ graph_path = a })
    graph.set_active(c)
    edit_in(b .. '/pages/A.md')
    logseq.today({ root = d, date = '2026_08_27' })
    H.track_current()
    assert.are.equal(vim.fn.resolve(d) .. '/journals/2026_08_27.md', vim.api.nvim_buf_get_name(0))
  end)

  it('buffer wins end-to-end in today()', function()
    local a = H.tmpgraph()
    local b = H.tmpgraph()
    config.setup({ graph_path = a })
    edit_in(b .. '/pages/A.md')
    logseq.today({ date = '2026_08_27' })
    H.track_current()
    assert.are.equal(vim.fn.resolve(b) .. '/journals/2026_08_27.md', vim.api.nvim_buf_get_name(0))
  end)

  it('active graph resolves today() when the buffer is outside', function()
    local a = H.tmpgraph()
    local b = H.tmpgraph()
    config.setup({ graph_path = a })
    graph.set_active(b)
    H.home()
    logseq.today({ date = '2026_08_27' })
    H.track_current()
    assert.are.equal(vim.fn.resolve(b) .. '/journals/2026_08_27.md', vim.api.nvim_buf_get_name(0))
  end)

  it('find_files titles the picker with the graph name', function()
    local b = H.tmpgraph()
    vim.fn.writefile({ '- x' }, b .. '/pages/A.md') -- the picker needs a page
    edit_in(b .. '/pages/A.md')
    local prompt
    H.tele.pick = function(_, opts)
      prompt = opts.prompt_title
    end
    logseq.find_files()
    assert.are.equal('Logseq Pages — ' .. vim.fn.fnamemodify(b, ':t'), prompt)
  end)
end)

describe('switch_graph (M5.3)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  local function paths_of(items)
    local paths = {}
    for _, item in ipairs(items) do
      table.insert(paths, item.path or '(auto)')
    end
    return paths
  end

  -- Plain scan dir (not itself a graph) holding one discovered graph.
  local function scandir(name)
    local scan = vim.fn.tempname()
    table.insert(H.tmps, scan)
    vim.fn.mkdir(scan .. '/' .. name .. '/pages', 'p')
    vim.fn.mkdir(scan .. '/' .. name .. '/journals', 'p')
    return scan, scan .. '/' .. name
  end

  it('offers graph_path + discovered + (auto), sets the choice', function()
    local a = H.tmpgraph()
    local scan, beta = scandir('beta')
    config.setup({ graph_path = a, graphs_dirs = { scan }, graphs_depth = 1 })
    local seen
    H.tele.pick = function(items, opts)
      seen = items
      for _, item in ipairs(items) do
        if item.path == beta then
          opts.on_choice(item)
          return
        end
      end
      error('discovered graph missing from picker')
    end
    logseq.switch_graph()
    assert.are.same({ a, beta, '(auto)' }, paths_of(seen))
    assert.is_true(seen[3].title:find('(auto)', 1, true) ~= nil)
    assert.are.equal(beta, graph.get_active())
    assert.is_true(H.notified(vim.log.levels.INFO, 'active graph: beta'))
  end)

  it('(auto) clears the override, which stays listed while set', function()
    local b = H.tmpgraph()
    graph.set_active(b)
    H.tele.pick = function(items, opts)
      for _, item in ipairs(items) do
        if item.path == nil then
          opts.on_choice(item)
          return
        end
      end
      error('(auto) entry missing')
    end
    logseq.switch_graph()
    assert.is_nil(graph.get_active())
    assert.is_true(H.notified(vim.log.levels.INFO, 'cleared'))
  end)

  it('empty discovery with no graph_path warns without opening a picker', function()
    local opened = false
    H.tele.pick = function()
      opened = true
    end
    logseq.switch_graph()
    assert.is_false(opened)
    assert.is_true(H.notified(vim.log.levels.WARN, 'graphs_dirs'))
  end)

  it('selecting a stale graph_path errors loudly', function()
    config.setup({ graph_path = '/tmp/no-such-logseq-graph-xyz' })
    H.tele.pick = function(items, opts)
      opts.on_choice(items[1]) -- the graph_path entry
    end
    assert.has_error(function()
      logseq.switch_graph()
    end)
    assert.is_nil(graph.get_active())
  end)
end)

describe('todos picker (M7.2)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  it('titles the picker with the graph name and jumps to path:lnum on choice', function()
    local root = H.tmpgraph()
    vim.fn.writefile({ '- TODO Buy milk', '- plain', '\t- DONE paid' }, root .. '/pages/Errands.md')
    vim.fn.writefile({ '- NOW standup notes' }, root .. '/journals/2026_09_05.md')
    H.home()
    local seen_items, seen_prompt, seen_format
    H.tele.pick = function(items, opts)
      seen_items, seen_prompt, seen_format = items, opts.prompt_title, opts.format_item
      for _, task in ipairs(items) do
        if task.status == 'DONE' then
          opts.on_choice(task) -- line 3: proves the +lnum jump, not just the file
          return
        end
      end
      error('DONE task missing from picker')
    end
    logseq.todos({ root = root })
    H.track_current()
    assert.are.equal('Logseq Todos — ' .. vim.fn.fnamemodify(root, ':t'), seen_prompt)
    assert.are.equal(3, #seen_items)
    assert.are.equal('[TODO] Errands: Buy milk', seen_format(seen_items[2]))
    assert.are.equal('[DONE] Errands: paid', seen_format(seen_items[3]))
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Errands.md', vim.api.nvim_buf_get_name(0))
    assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it('empty graph warns without opening a picker', function()
    local root = H.tmpgraph()
    vim.fn.writefile({ '- just a bullet', '- todo lowercase' }, root .. '/pages/Plain.md')
    H.home()
    local opened = false
    H.tele.pick = function()
      opened = true
    end
    logseq.todos({ root = root })
    assert.is_false(opened)
    assert.is_true(H.notified(vim.log.levels.WARN, 'no tasks found'))
  end)

  it('errors with no graph root', function()
    H.home()
    vim.fn.chdir('/tmp') -- outside any graph; unnamed buf so cwd applies
    local buf = vim.api.nvim_get_current_buf()
    logseq.todos()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.ERROR, 'graph root not found'))
  end)
end)

describe('todos_view scratch buffer (M7.3)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  local function seed(root)
    vim.fn.writefile({ '- TODO Buy milk', '- plain', '\t- DONE paid' }, root .. '/pages/Errands.md')
    vim.fn.writefile({ '- NOW standup notes' }, root .. '/journals/2026_09_05.md')
  end

  -- Invoke a buffer-local Lua keymap by its description (lhs encoding
  -- varies; the desc is the stable handle).
  local function key_cb(buf, desc)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.desc == desc then
        assert.is_not_nil(map.callback, 'key has no Lua callback: ' .. desc)
        return map.callback
      end
    end
    error('missing key: ' .. desc)
  end

  local function todos_buffers()
    local out = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local ok, st = pcall(vim.api.nvim_buf_get_var, buf, 'logseq_todos')
        if ok and type(st) == 'table' then
          table.insert(out, buf)
        end
      end
    end
    return out
  end

  it('renders grouped sections with header, rows, and the b: lnum map', function()
    local root = H.tmpgraph()
    seed(root)
    H.home()
    local buf = logseq.todos_view({ root = root })
    assert.is_not_nil(buf)
    H.track_current()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.are.equal('logseq-todos', vim.bo[buf].filetype)
    assert.are.equal('nofile', vim.bo[buf].buftype)
    assert.is_false(vim.bo[buf].modifiable)
    local head = '# Logseq Todos · ' .. vim.fn.fnamemodify(root, ':t') .. ' (3)'
    assert.are.same({
      head,
      '',
      '## 2026_09_05 (journal)',
      '- [NOW] 1: standup notes',
      '',
      '## Errands (page)',
      '- [TODO] 1: Buy milk',
      '- [DONE] 3: paid',
    }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local st = vim.api.nvim_buf_get_var(buf, 'logseq_todos')
    assert.are.equal(root, st.root)
    assert.are.same({ path = root .. '/journals/2026_09_05.md', lnum = 1 }, st.map['4'])
    assert.are.same({ path = root .. '/pages/Errands.md', lnum = 1 }, st.map['7'])
    assert.are.same({ path = root .. '/pages/Errands.md', lnum = 3 }, st.map['8'])
    assert.is_nil(st.map['1']) -- header line maps to nothing
  end)

  it('<CR> jumps to the task location; off-row warns and stays put', function()
    local root = H.tmpgraph()
    seed(root)
    H.home()
    local buf = logseq.todos_view({ root = root })
    H.track_current()
    local jump = key_cb(buf, 'Logseq: open task under cursor')
    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- header line: no task here
    jump()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.WARN, 'no task under cursor'))
    vim.api.nvim_win_set_cursor(0, { 7, 0 }) -- '- [TODO] 1: Buy milk'
    jump()
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Errands.md', vim.api.nvim_buf_get_name(0))
    assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it('q closes the view', function()
    local root = H.tmpgraph()
    seed(root)
    H.home()
    local buf = logseq.todos_view({ root = root })
    H.track_current()
    key_cb(buf, 'Logseq: close todos view')()
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)

  it('re-running reuses the single buffer and refreshes its content', function()
    local root = H.tmpgraph()
    seed(root)
    H.home()
    local buf = logseq.todos_view({ root = root })
    H.track_current()
    vim.fn.writefile({ '- LATER file more taxes' }, root .. '/pages/Extra.md')
    local again = logseq.todos_view({ root = root })
    assert.are.equal(buf, again)
    assert.are.same({ buf }, todos_buffers())
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are.equal('# Logseq Todos · ' .. vim.fn.fnamemodify(root, ':t') .. ' (4)', lines[1])
    local found_extra = false
    for _, line in ipairs(lines) do
      if line == '- [LATER] 1: file more taxes' then
        found_extra = true
      end
    end
    assert.is_true(found_extra)
  end)

  it('empty graph warns without opening a view', function()
    local root = H.tmpgraph()
    vim.fn.writefile({ '- just a bullet' }, root .. '/pages/Plain.md')
    H.home()
    local buf = vim.api.nvim_get_current_buf()
    assert.is_nil(logseq.todos_view({ root = root }))
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.are.same({}, todos_buffers())
    assert.is_true(H.notified(vim.log.levels.WARN, 'no tasks found'))
  end)

  it('errors with no graph root', function()
    H.home()
    vim.fn.chdir('/tmp') -- outside any graph; unnamed buf so cwd applies
    local buf = vim.api.nvim_get_current_buf()
    assert.is_nil(logseq.todos_view())
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.is_true(H.notified(vim.log.levels.ERROR, 'graph root not found'))
  end)
end)

describe('cycle_todo buffer behavior (M8.4)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  -- Scratch buffer on row with col; cycle_todo works in any buffer, so no
  -- graph or config is needed (defaults come from config.get()).
  local function scratch(lines, row, col)
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(H.bufs, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
    vim.api.nvim_win_set_cursor(0, { row, col })
    return buf
  end

  local function line_of(buf, row)
    return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
  end

  it('cycles the cursor line through the default chain and wraps', function()
    local buf = scratch({ '- TODO a', '- DOING b', '- DONE c' }, 1, 0)
    logseq.cycle_todo()
    assert.are.equal('- DOING a', line_of(buf, 1))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    logseq.cycle_todo()
    assert.are.equal('- DONE b', line_of(buf, 2))
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    logseq.cycle_todo()
    assert.are.equal('- TODO c', line_of(buf, 3))
    assert.are.same({}, H.notes) -- silent on success
  end)

  it('keeps indent, cursor row, and a valid cursor col', function()
    local buf = scratch({ '  * DOING [#A] call [[Mom]]' }, 1, 0)
    logseq.cycle_todo()
    assert.are.equal('  * DONE [#A] call [[Mom]]', line_of(buf, 1))
    local cur = vim.api.nvim_win_get_cursor(0)
    assert.are.equal(1, cur[1])
    assert.is_true(cur[2] <= #'  * DONE [#A] call [[Mom]]')
  end)

  it('restores the marker with a single undo', function()
    -- Seed via :edit (not buf_set_lines) so the file load owns the prior
    -- undo history, exactly like a user opening a page and cycling once.
    local path = vim.fn.tempname() .. '.md'
    vim.fn.writefile({ '- TODO a' }, path)
    H.home()
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    table.insert(H.bufs, buf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    logseq.cycle_todo()
    assert.are.equal('- DOING a', line_of(buf, 1))
    vim.cmd('undo')
    assert.are.equal('- TODO a', line_of(buf, 1))
    vim.fn.delete(path)
  end)

  it('warns and leaves the buffer untouched off-task', function()
    local buf = scratch({ '- just a bullet', '- TODO kept' }, 1, 0)
    logseq.cycle_todo()
    assert.are.equal('- just a bullet', line_of(buf, 1))
    assert.are.equal('- TODO kept', line_of(buf, 2))
    assert.is_true(H.notified(vim.log.levels.WARN, 'no cyclable task'))
  end)

  it('warns when the marker sits in no configured chain', function()
    vim.g.logseq = { todo_cycles = { { 'TODO', 'DONE' } } }
    local buf = scratch({ '- WAIT x' }, 1, 0)
    logseq.cycle_todo()
    assert.are.equal('- WAIT x', line_of(buf, 1))
    assert.is_true(H.notified(vim.log.levels.WARN, 'no cyclable task'))
  end)

  it('honors custom todo_cycles from vim.g.logseq', function()
    vim.g.logseq = { todo_cycles = { { 'TODO', 'DONE' } } }
    local buf = scratch({ '- TODO x' }, 1, 0)
    logseq.cycle_todo()
    assert.are.equal('- DONE x', line_of(buf, 1))
    assert.are.same({}, H.notes)
  end)

  it('refuses non-modifiable buffers with a warning', function()
    local buf = scratch({ '- TODO x' }, 1, 0)
    vim.bo[buf].modifiable = false
    logseq.cycle_todo()
    assert.are.equal('- TODO x', line_of(buf, 1))
    assert.is_true(H.notified(vim.log.levels.WARN, 'not modifiable'))
  end)
end)

describe('smart_action dispatch (M9.1)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  -- Scratch buffer on row with 0-based col; opts.root override is threaded
  -- through to follow_link so link specs stay hermetic (lazy open).
  local function scratch(lines, row, col)
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(H.bufs, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
    vim.api.nvim_win_set_cursor(0, { row, col })
    return buf
  end

  local function line_of(buf, row)
    return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
  end

  it('follows the link under the cursor', function()
    local root = H.tmpgraph()
    scratch({ '- see [[Target]]' }, 1, 8)
    logseq.smart_action({ root = root })
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Target.md', vim.api.nvim_buf_get_name(0))
  end)

  it('prefers the link over the task cycle on a task line', function()
    local root = H.tmpgraph()
    local buf = scratch({ '- TODO read [[Target]]' }, 1, 15)
    logseq.smart_action({ root = root })
    H.track_current()
    assert.are.equal(vim.fn.resolve(root) .. '/pages/Target.md', vim.api.nvim_buf_get_name(0))
    assert.are.equal('- TODO read [[Target]]', line_of(buf, 1))
  end)

  it('cycles a task line when no link is under the cursor', function()
    local buf = scratch({ '- TODO x' }, 1, 0)
    logseq.smart_action()
    assert.are.equal('- DOING x', line_of(buf, 1))
    assert.are.same({}, H.notes) -- silent on success
  end)

  it('falls back to the default <CR> motion on plain prose', function()
    scratch({ 'first', '  second' }, 1, 0)
    logseq.smart_action()
    assert.are.same({ 2, 2 }, vim.api.nvim_win_get_cursor(0))
    assert.are.same({}, H.notes) -- silent, no root needed
  end)

  it('fallback needs no graph root and stays silent at the last line', function()
    vim.fn.chdir('/tmp') -- outside any graph; unnamed buf so cwd applies
    local buf = scratch({ 'only' }, 1, 0)
    logseq.smart_action()
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
    assert.are.same({}, H.notes)
  end)
end)

describe('nav_link next/prev (M9.1)', function()
  local H
  before_each(function()
    H = m3_harness()
    H.setup()
  end)
  after_each(function()
    H.teardown()
  end)

  local function scratch(lines, row, col)
    local buf = vim.api.nvim_create_buf(true, false)
    table.insert(H.bufs, buf)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
    vim.api.nvim_win_set_cursor(0, { row, col })
    return buf
  end

  it('jumps to the next link across lines', function()
    scratch({ 'see [[A]] here', 'and [[B]]' }, 1, 0)
    logseq.nav_link('next')
    assert.are.same({ 1, 4 }, vim.api.nvim_win_get_cursor(0))
    logseq.nav_link('next')
    assert.are.same({ 2, 4 }, vim.api.nvim_win_get_cursor(0))
    assert.are.same({}, H.notes)
  end)

  it('skips the link under the cursor when moving next', function()
    -- Cursor sits on the '[' of [[A]] (0-based col 4): next must move on.
    scratch({ 'see [[A]] and [[B]]' }, 1, 4)
    logseq.nav_link('next')
    assert.are.same({ 1, 14 }, vim.api.nvim_win_get_cursor(0))
  end)

  it('moves to the previous link and stops silently at the start', function()
    scratch({ 'see [[A]] here', 'and [[B]]' }, 2, 4)
    logseq.nav_link('prev')
    assert.are.same({ 1, 4 }, vim.api.nvim_win_get_cursor(0))
    logseq.nav_link('prev')
    assert.are.same({ 1, 4 }, vim.api.nvim_win_get_cursor(0)) -- no wrap
    assert.are.same({}, H.notes)
  end)

  it('stops silently at the last link without wrapping', function()
    scratch({ 'see [[A]]' }, 1, 4)
    logseq.nav_link('next')
    assert.are.same({ 1, 4 }, vim.api.nvim_win_get_cursor(0))
    assert.are.same({}, H.notes)
  end)

  it('does nothing silently when the buffer has no links', function()
    scratch({ 'plain prose', 'more prose' }, 1, 0)
    logseq.nav_link('next')
    logseq.nav_link('prev')
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
    assert.are.same({}, H.notes)
  end)

  it('counts hashtags as stops', function()
    scratch({ 'about #topic here' }, 1, 0)
    logseq.nav_link('next')
    assert.are.same({ 1, 6 }, vim.api.nvim_win_get_cursor(0))
  end)

  it('asserts on an invalid direction', function()
    scratch({ 'see [[A]]' }, 1, 0)
    assert.has_error(function()
      logseq.nav_link('sideways')
    end)
  end)
end)
