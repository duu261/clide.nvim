local clide = require("clide")

describe("clide lifecycle", function()
  before_each(function()
    require("clide.lockfile").set_dir(vim.fn.tempname())
    require("clide.config").setup({ terminal = { provider = "none" } })
  end)

  after_each(function()
    clide.stop()
  end)

  it("start creates server and lock file", function()
    clide.start()
    assert.is_not_nil(clide.state.server)
    local lock = require("clide.lockfile").path(clide.state.server.port)
    assert.equals(1, vim.fn.filereadable(lock))
  end)

  it("stop removes server and lock file", function()
    clide.start()
    local lock = require("clide.lockfile").path(clide.state.server.port)
    clide.stop()
    assert.is_nil(clide.state.server)
    assert.equals(0, vim.fn.filereadable(lock))
  end)

  it("stop closes the terminal", function()
    clide.start()
    local terminal = require("clide.terminal")
    local closed = false
    local orig_close = terminal.close
    terminal.close = function()
      closed = true
    end
    clide.stop()
    terminal.close = orig_close
    assert.is_true(closed)
  end)

  it("stop then start recreates server and a fresh session table", function()
    clide.start()
    local old_server = clide.state.server
    assert.is_table(old_server.sessions)
    clide.stop()
    clide.start()
    assert.is_not_nil(clide.state.server)
    assert.is_not.equal(old_server, clide.state.server)
    assert.is_table(clide.state.server.sessions)
    assert.is_nil(next(clide.state.server.sessions))
  end)

  it("start is idempotent", function()
    clide.start()
    local port = clide.state.server.port
    clide.start()
    assert.equals(port, clide.state.server.port)
  end)

  it("registers user commands", function()
    require("clide.commands").setup()
    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds.ClideStart)
    assert.is_not_nil(cmds.ClideStop)
    assert.is_not_nil(cmds.ClideToggle)
    assert.is_not_nil(cmds.ClideSend)
    assert.is_not_nil(cmds.ClideLog)
  end)
end)
