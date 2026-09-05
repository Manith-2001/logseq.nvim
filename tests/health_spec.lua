-- Spec for lua/logseq/health.lua reporting (M10.4): stub vim.health,
-- run check(), assert the completion summary line.
local health = require('logseq.health')

describe('health.check (M10.4)', function()
  local saved_g, saved_health
  local config = require('logseq.config')
  local calls
  before_each(function()
    saved_g = vim.g.logseq
    saved_health = vim.health
    calls = {}
    local function rec(level)
      return function(msg)
        table.insert(calls, { level = level, msg = msg })
      end
    end
    vim.health = {
      start = function() end,
      ok = rec('ok'),
      warn = rec('warn'),
      error = rec('error'),
      info = rec('info'),
    }
  end)
  after_each(function()
    vim.health = saved_health
    vim.g.logseq = saved_g
    config._reset()
  end)

  local function infos(fragment)
    local out = {}
    for _, c in ipairs(calls) do
      if c.level == 'info' and c.msg:find(fragment, 1, true) then
        table.insert(out, c.msg)
      end
    end
    return out
  end

  it('reports the completion setup in one info line', function()
    health.check()
    local lines = infos('completion:')
    assert.are.equal(1, #lines)
    assert.is_not_nil(lines[1]:find('auto-popup on', 1, true))
    assert.is_not_nil(lines[1]:find('limit 50', 1, true))
    assert.is_not_nil(lines[1]:find('omnifunc', 1, true))
  end)

  it('reflects completion_auto=false', function()
    -- Via vim.g.logseq: check() re-runs setup() bare, which replaces
    -- setup()-given opts but keeps the g: layer.
    vim.g.logseq = { completion_auto = false }
    health.check()
    local lines = infos('completion:')
    assert.are.equal(1, #lines)
    assert.is_not_nil(lines[1]:find('auto-popup off', 1, true))
  end)
end)
