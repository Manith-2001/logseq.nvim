-- Documentation inventory checks (audit DOC-02): every command the plugin
-- defines is documented in README + vimdoc; every |anchor| referenced in
-- the vimdoc is defined. Catches drift like the missing :LogseqGraphAll
-- rows and the dangling |logseq-todos| / |logseq-smartaction| references.
describe('documentation inventory (DOC-02)', function()
  local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

  local function read(rel)
    return table.concat(vim.fn.readfile(repo .. '/' .. rel), '\n')
  end

  local function plugin_commands()
    local src = read('plugin/logseq.lua')
    local names = {}
    for name in src:gmatch("n?cmd%('([%w]+)'") do
      table.insert(names, name)
    end
    for name in src:gmatch("navcmd%('([%w]+)'") do
      table.insert(names, name)
    end
    table.sort(names)
    return names
  end

  it('every plugin command is documented in doc/logseq.txt', function()
    local help = read('doc/logseq.txt')
    for _, name in ipairs(plugin_commands()) do
      assert.is_not_nil(
        help:find(('*:' .. name .. '*'), 1, true),
        'missing vimdoc tag for :' .. name
      )
    end
  end)

  it('every plugin command is documented in README.md', function()
    local readme = read('README.md')
    for _, name in ipairs(plugin_commands()) do
      assert.is_not_nil(
        readme:find('`:' .. name .. '`', 1, true),
        'missing README row for :' .. name
      )
    end
  end)

  it('every |tag| referenced in the vimdoc is defined', function()
    local help = read('doc/logseq.txt')
    local defined = {}
    for tag in help:gmatch('%*([^*\n]+)%*') do
      defined[tag] = true
    end
    local refs = {}
    for tag in help:gmatch('|([^|\n]+)|') do
      refs[tag] = true
    end
    for tag, _ in pairs(refs) do
      assert.is_not_nil(defined[tag], 'dangling help reference |' .. tag .. '|')
    end
  end)

  it('helptags generation succeeds and resolves the module help', function()
    assert(pcall(vim.cmd, 'helptags ' .. vim.fn.fnameescape(repo .. '/doc')))
    local tags = vim.fn.readfile(repo .. '/doc/tags')
    local found = false
    for _, line in ipairs(tags) do
      if line:find('^logseq%-contents\t') then
        found = true
      end
    end
    assert.is_true(found, 'doc/tags missing logseq-contents (helptags failed)')
  end)
end)
