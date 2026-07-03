local terminal = require("clide.terminal")
local config = require("clide.config")

-- Helpers to reset module-level state
local function reset_native()
  package.loaded["clide.terminal.native"] = nil
end

local function reset_tmux()
  package.loaded["clide.terminal.tmux"] = nil
end

describe("terminal provider resolution", function()
  it("resolves an explicit provider", function()
    config.setup({ terminal = { provider = "none" } })
    local p = terminal.provider()
    assert.equals("none", p.name)
  end)

  it("resolves native when explicitly set", function()
    config.setup({ terminal = { provider = "native" } })
    local p = terminal.provider()
    assert.equals("native", p.name)
  end)

  it("auto resolves tmux only inside tmux", function()
    config.setup({ terminal = { provider = "auto" } })
    local tmux = require("clide.terminal.tmux")
    if vim.env.TMUX and vim.fn.executable("tmux") == 1 then
      assert.is_true(tmux.is_available())
    else
      assert.is_false(tmux.is_available())
    end
  end)

  it("auto falls back to native when nothing else available", function()
    local saved_env = vim.env.TMUX
    vim.env.TMUX = nil
    -- Temporarily replace snacks is_available to force native
    local snacks = require("clide.terminal.snacks")
    local orig = snacks.is_available
    snacks.is_available = function() return false end
    config.setup({ terminal = { provider = "auto" } })
    local p = terminal.provider()
    assert.equals("native", p.name)
    snacks.is_available = orig
    vim.env.TMUX = saved_env
  end)
end)

describe("terminal none provider", function()
  it("is_available returns true", function()
    local none = require("clide.terminal.none")
    assert.is_true(none.is_available())
  end)

  it("open calls vim.notify with env", function()
    local none = require("clide.terminal.none")
    local notified
    local orig = vim.notify
    vim.notify = function(msg, level)
      notified = msg
      orig(msg, level)
    end
    none.open("claude", { FOO = "bar" })
    vim.notify = orig
    assert.is_not_nil(notified)
    assert.matches("FOO=bar", notified)
    assert.matches("claude", notified)
  end)

  it("close is a no-op", function()
    local none = require("clide.terminal.none")
    none.close() -- should not error
    assert.is_true(true)
  end)

  it("toggle calls open", function()
    local none = require("clide.terminal.none")
    local opened = false
    local orig = none.open
    none.open = function(...) opened = true; orig(...) end
    none.toggle("claude", {})
    none.open = orig
    assert.is_true(opened)
  end)
end)

describe("terminal native provider", function()
  before_each(function()
    reset_native()
    config.setup({ terminal = { provider = "native", cmd = "sh", split_width = 0.35 } })
  end)

  it("is_available returns true", function()
    local native = require("clide.terminal.native")
    assert.is_true(native.is_available())
  end)

  it("open creates a terminal buffer", function()
    local native = require("clide.terminal.native")
    native.open("sh", { CLIDE_TEST = "1" })
    local found = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buftype == "terminal" then
        found = true
      end
    end
    assert.is_true(found)
    native.close()
  end)

  it("close cleans up window state", function()
    local native = require("clide.terminal.native")
    native.open("sh", { TEST_VAR = "1" })
    native.close()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      assert.is_not_equal("terminal", vim.bo[buf].buftype)
    end
  end)

  it("close is safe when already closed", function()
    local native = require("clide.terminal.native")
    native.close()
    assert.is_true(true)
  end)

  it("open reuses existing window on second call", function()
    local native = require("clide.terminal.native")
    native.open("sh", { TEST_VAR = "1" })
    local win_count_before = #vim.api.nvim_list_wins()
    native.open("sh", { TEST_VAR = "1" })
    local win_count_after = #vim.api.nvim_list_wins()
    assert.equals(win_count_before, win_count_after)
    native.close()
  end)

  it("toggle opens when closed", function()
    local native = require("clide.terminal.native")
    native.toggle("sh", { TEST_VAR = "1" })
    local found = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buftype == "terminal" then
        found = true
      end
    end
    assert.is_true(found)
    native.close()
  end)

  it("toggle closes when open", function()
    local native = require("clide.terminal.native")
    native.open("sh", { TEST_VAR = "1" })
    native.toggle("sh", { TEST_VAR = "1" })
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      assert.is_not_equal("terminal", vim.bo[buf].buftype)
    end
  end)
end)

describe("terminal tmux provider", function()
  before_each(function()
    reset_tmux()
    config.setup({ terminal = { provider = "tmux", cmd = "sh", split_width = 0.35 } })
  end)

  it("is_available respects tmux env", function()
    local tmux = require("clide.terminal.tmux")
    assert.equals(vim.env.TMUX ~= nil and vim.fn.executable("tmux") == 1, tmux.is_available())
  end)

  it("close is safe when no pane", function()
    local tmux = require("clide.terminal.tmux")
    tmux.close()
    assert.is_true(true)
  end)
end)

describe("terminal snacks provider", function()
  it("is_available detects installed dep", function()
    local snacks = require("clide.terminal.snacks")
    assert.is_true(snacks.is_available())
  end)

  it("open does not crash", function()
    local snacks = require("clide.terminal.snacks")
    snacks.open("sh", {})
    assert.is_true(true)
  end)

  it("close does not crash", function()
    local snacks = require("clide.terminal.snacks")
    snacks.close()
    assert.is_true(true)
  end)

  it("toggle does not crash", function()
    local snacks = require("clide.terminal.snacks")
    snacks.toggle("sh", {})
    assert.is_true(true)
  end)
end)

describe("terminal dispatcher", function()
  before_each(function()
    config.setup({ terminal = { provider = "native", cmd = "sh" } })
  end)

  it("open delegates to provider", function()
    terminal.open({ TEST = "1" })
    local found = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buftype == "terminal" then
        found = true
      end
    end
    assert.is_true(found)
    terminal.close()
  end)

  it("close delegates to provider", function()
    terminal.open({ TEST = "1" })
    terminal.close()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      assert.is_not_equal("terminal", vim.bo[buf].buftype)
    end
  end)

  it("toggle delegates to provider", function()
    terminal.toggle({ TEST = "1" })
    terminal.toggle({ TEST = "1" })
    assert.is_true(true)
  end)
end)
