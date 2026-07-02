describe("rpc", function()
  local sent
  local dispatcher
  local tools
  local rpc

  before_each(function()
    sent = {}
    -- Reset both modules to clear registry state between tests
    package.loaded["clide.tools"] = nil
    package.loaded["clide.server.rpc"] = nil
    tools = require("clide.tools")
    rpc = require("clide.server.rpc")
    dispatcher = rpc.new(function(text)
      table.insert(sent, vim.json.decode(text))
    end)
  end)

  it("answers initialize with MCP server info", function()
    dispatcher:handle('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
    assert.equals(1, #sent)
    assert.equals(1, sent[1].id)
    assert.equals("2025-03-26", sent[1].result.protocolVersion)
    assert.equals("clide.nvim", sent[1].result.serverInfo.name)
  end)

  it("answers tools/list with registered tools", function()
    tools.register({
      name = "zzz_test_tool",
      description = "test",
      inputSchema = { type = "object" },
      handler = function()
        return tools.text_result("ok")
      end,
    })
    dispatcher:handle('{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
    local names = vim.tbl_map(function(t)
      return t.name
    end, sent[1].result.tools)
    assert.is_true(vim.tbl_contains(names, "zzz_test_tool"))
  end)

  it("calls a tool and returns its result", function()
    tools.register({
      name = "zzz_test_tool",
      description = "test",
      inputSchema = { type = "object" },
      handler = function()
        return tools.text_result("ok")
      end,
    })
    dispatcher:handle(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"zzz_test_tool","arguments":{}}}'
    )
    assert.equals("ok", sent[1].result.content[1].text)
  end)

  it("returns -32601 for unknown methods", function()
    dispatcher:handle('{"jsonrpc":"2.0","id":4,"method":"nope"}')
    assert.equals(-32601, sent[1].error.code)
  end)

  it("returns -32602 for unknown tools", function()
    dispatcher:handle(
      '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"missing","arguments":{}}}'
    )
    assert.equals(-32602, sent[1].error.code)
  end)

  it("drops malformed json without raising", function()
    assert.has_no.errors(function()
      dispatcher:handle("{not json")
    end)
    assert.equals(0, #sent)
  end)

  it("sends notifications without id", function()
    dispatcher:notify("selection_changed", { text = "x" })
    assert.equals("selection_changed", sent[1].method)
    assert.is_nil(sent[1].id)
  end)
end)
