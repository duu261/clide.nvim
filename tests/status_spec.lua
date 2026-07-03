local status = require("clide.status")

describe("status", function()
  after_each(function()
    status.teardown()
  end)

  it("reports stopped when no server is running", function()
    require("clide").state = {}
    assert.equals("stopped", status.get())
  end)

  it("reports disconnected when server up but no client", function()
    require("clide").state = { server = { port = 12345 }, connected = false }
    status.setup()
    assert.equals("disconnected", status.get())
  end)

  it("reads state written to the state file", function()
    require("clide").state = { server = { port = 12345 }, connected = true }
    status.setup()
    vim.fn.mkdir(vim.fn.fnamemodify(status.state_file(), ":h"), "p")
    vim.fn.writefile({ "working" }, status.state_file())
    assert.equals("working", status.get())
  end)

  it("lualine renders an icon + state", function()
    require("clide").state = {}
    assert.equals("", status.lualine()) -- stopped renders nothing
    require("clide").state = { server = { port = 1 }, connected = true }
    status.setup()
    vim.fn.mkdir(vim.fn.fnamemodify(status.state_file(), ":h"), "p")
    vim.fn.writefile({ "waiting" }, status.state_file())
    assert.matches("waiting", status.lualine())
  end)

  it("hooks config generation targets the state file", function()
    local hooks = status.hooks_config()
    assert.matches(status.state_file(), hooks.hooks.PreToolUse[1].hooks[1].command, 1, true)
    assert.matches("working", hooks.hooks.PreToolUse[1].hooks[1].command)
    assert.matches("idle", hooks.hooks.Stop[1].hooks[1].command)
    assert.matches("waiting", hooks.hooks.Notification[1].hooks[1].command)
  end)
end)
