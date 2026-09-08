-- Direct coverage for lua/logseq/telescope.lua (audit TEST-01): the
-- Telescope success path, its error fallback, the vim.ui.select fallback,
-- and the format/ordinal/default wiring.
local telescope = require('logseq.telescope')

describe('telescope adapter (M1, TEST-01)', function()
  local saved_loaded, saved_preload, saved_select, select_fn

  local function save_and_unload()
    for k in pairs(package.loaded) do
      if k:match('^telescope') then
        saved_loaded[k] = package.loaded[k]
        package.loaded[k] = nil
      end
    end
  end

  before_each(function()
    saved_loaded, saved_preload = {}, {}
    saved_select = vim.ui.select
    select_fn = nil
    save_and_unload()
  end)
  after_each(function()
    for k in pairs(package.loaded) do
      if k:match('^telescope') then
        package.loaded[k] = nil
      end
    end
    for k, v in pairs(saved_loaded) do
      package.loaded[k] = v
    end
    for k in pairs(package.preload) do
      if k:match('^telescope') then
        saved_preload[k] = package.preload[k]
        package.preload[k] = nil
      end
    end
    for k, v in pairs(saved_preload) do
      package.preload[k] = v
    end
    vim.ui.select = saved_select
  end)

  it('falls back to vim.ui.select when telescope is absent', function()
    package.preload['telescope'] = function()
      error('not installed')
    end
    local seen_items, seen_prompt, chosen
    vim.ui.select = function(items, opts, on_choice)
      seen_items, seen_prompt = items, opts.prompt
      on_choice(items[1])
    end
    telescope.pick({ { kind = 'page', title = 'A' } }, {
      prompt_title = 'Pages!',
      on_choice = function(item)
        chosen = item
      end,
    })
    assert.are.equal(1, #seen_items)
    assert.are.equal('Pages!', seen_prompt)
    assert.are.equal('A', chosen.title)
  end)

  it('falls back to vim.ui.select when the Telescope call errors', function()
    package.loaded['telescope'] = true
    package.loaded['telescope.pickers'] = {
      new = function()
        error('boom')
      end,
    }
    local used_fallback = false
    vim.ui.select = function(items, _, on_choice)
      used_fallback = true
      on_choice(items[1])
    end
    local chosen
    telescope.pick({ { title = 'A' } }, {
      on_choice = function(item)
        chosen = item
      end,
    })
    assert.is_true(used_fallback)
    assert.are.equal('A', chosen.title)
  end)

  it('selects through Telescope when present; cancel selects nothing', function()
    local captured
    package.loaded['telescope'] = true
    package.loaded['telescope.pickers'] = {
      new = function(_, spec)
        captured = spec
        return { find = function() end }
      end,
    }
    package.loaded['telescope.finders'] = {
      new_table = function(t)
        return t
      end,
    }
    package.loaded['telescope.config'] = {
      values = {
        generic_sorter = function()
          return {}
        end,
      },
    }
    package.loaded['telescope.actions'] = {
      select_default = {
        replace = function(_, fn)
          select_fn = fn
        end,
      },
      close = function() end,
    }
    package.loaded['telescope.actions.state'] = {
      get_selected_entry = function()
        return { value = 'PICKED' }
      end,
    }
    local result
    telescope.pick({ { kind = 'page', title = 'A' } }, {
      prompt_title = 'Via Telescope',
      format_item = function(item)
        return 'F:' .. item.title
      end,
      ordinal = function(item)
        return 'O:' .. item.title
      end,
      on_choice = function(v)
        result = v
      end,
    })
    -- The picker spec was captured; run its entry_maker and the wired
    -- select_default replacement, exactly like a real selection.
    assert.are.equal('Via Telescope', captured.prompt_title)
    local entry = captured.finder.entry_maker({ kind = 'page', title = 'A' })
    assert.are.equal('F:A', entry.display)
    assert.are.equal('O:A', entry.ordinal)
    -- Drive attach_mappings the way a real picker start would (the stubs
    -- above capture the spec but do not run the Telescope lifecycle).
    captured.attach_mappings(1, nil)
    select_fn(1) -- actions.close(bufnr) is stubbed; entry.value is 'PICKED'
    assert.are.equal('PICKED', result)
  end)

  it('applies the default format and ordinal when none are given', function()
    local captured
    package.loaded['telescope'] = true
    package.loaded['telescope.pickers'] = {
      new = function(_, spec)
        captured = spec
        return { find = function() end }
      end,
    }
    package.loaded['telescope.finders'] = {
      new_table = function(t)
        return t
      end,
    }
    package.loaded['telescope.config'] = {
      values = {
        generic_sorter = function()
          return {}
        end,
      },
    }
    package.loaded['telescope.actions'] = {
      select_default = {
        replace = function(_, fn)
          select_fn = fn
        end,
      },
      close = function() end,
    }
    package.loaded['telescope.actions.state'] = {
      get_selected_entry = function()
        return { value = { kind = 'journal', title = 'J' } }
      end,
    }
    telescope.pick({ { kind = 'journal', title = 'J' } }, { on_choice = function() end })
    local entry = captured.finder.entry_maker({ kind = 'journal', title = 'J' })
    assert.are.equal('[journal] J', entry.display)
    assert.are.equal('J', entry.ordinal)
    -- Cancel: select_default with no selected entry calls nothing.
    package.loaded['telescope.actions.state'] = {
      get_selected_entry = function()
        return nil
      end,
    }
    local fired = false
    package.loaded['telescope.pickers'] = {
      new = function(_, spec)
        captured = spec
        return { find = function() end }
      end,
    }
    telescope.pick({ { kind = 'journal', title = 'J' } }, {
      on_choice = function()
        fired = true
      end,
    })
    captured.attach_mappings(1, nil) -- real picker start wires select_default
    select_fn(1)
    assert.is_false(fired)
  end)
end)
