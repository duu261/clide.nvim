local terminal = require("clide.terminal")
local config = require("clide.config")

describe("terminal provider resolution", function()
  it("resolves an explicit provider", function()
    config.setup({ terminal = { provider = "none" } })
    local p = terminal.provider()
    assert.equals("none", p.name)
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
    local saved = vim.env.TMUX
    vim.env.TMUX = nil
    config.setup({ terminal = { provider = "auto" } })
    local p = terminal.provider()
    assert.is_true(p.name == "native" or p.name == "snacks")
    vim.env.TMUX = saved
  end)

  it("native provider opens a terminal buffer with env", function()
    config.setup({ terminal = { provider = "native", cmd = "sh" } })
    terminal.open({ CLIDE_TEST_VAR = "1" })
    local found = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buftype == "terminal" then
        found = true
      end
    end
    assert.is_true(found)
    terminal.close()
  end)
end)
