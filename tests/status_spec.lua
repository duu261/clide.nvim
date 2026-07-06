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

  it("SessionStart hook prints priming snippet when CLAUDE_CODE_SSE_PORT set", function()
    local hooks = status.hooks_config()
    assert.is_not_nil(hooks.hooks.SessionStart, "SessionStart hook should exist")
    local cmd = hooks.hooks.SessionStart[1].hooks[1].command
    assert.matches("CLAUDE_CODE_SSE_PORT", cmd, 1, true)
    -- execute the real command: catches shell quoting breakage
    local out = vim.fn.system({ "env", "CLAUDE_CODE_SSE_PORT=12345", "sh", "-c", cmd })
    assert.equals(0, vim.v.shell_error, "hook command must exit 0: " .. out)
    assert.matches("connected to a live Neovim editor", out, 1, true)
    assert.matches("mcp__ide__", out, 1, true)
    -- silent when not launched from clide
    out = vim.fn.system({ "env", "-u", "CLAUDE_CODE_SSE_PORT", "sh", "-c", cmd })
    assert.equals(0, vim.v.shell_error, "hook command must exit 0 without port")
    assert.equals("", out)
  end)
end)
