local sse = require("clide.server.sse")
local tools = require("clide.tools")

describe("SSE server", function()
  before_each(function()
    tools.setup()
  end)

  it("starts and returns port", function()
    local server = assert(sse.start({ on_message = function() end }))
    assert.is_not_nil(server.port)
    assert.is_not_nil(server.handle)
    sse.stop(server)
  end)

  it("rejects POST /message before an SSE session exists (auth)", function()
    local called = false
    local server = assert(sse.start({
      on_message = function()
        called = true
      end,
    }))

    -- No /sse GET yet, so server.session_id is nil. A /message with no sessionId
    -- must be rejected, not slip past via nil ~= nil == false.
    local post_sock = vim.uv.new_tcp()
    local post_raw = ""
    post_sock:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      post_sock:read_start(function(_, data)
        if data then
          post_raw = post_raw .. data
        end
      end)
      local body = vim.json.encode({ jsonrpc = "2.0", id = 1, method = "tools/list" })
      post_sock:write(
        "POST /message HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. body
      )
    end)

    vim.wait(1000, function()
      return post_raw:find("400", 1, true) ~= nil
    end)
    assert.is_false(called, "on_message ran without a valid session")
    assert.is_not_nil(post_raw:find("400 Bad Request", 1, true))

    post_sock:close()
    sse.stop(server)
  end)

  it("serves SSE endpoint event on GET /sse", function()
    local server = assert(sse.start({ on_message = function() end }))

    local sock = vim.uv.new_tcp()
    local raw = ""
    sock:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock:read_start(function(rerr, data)
        if data then
          raw = raw .. data
        end
      end)
      sock:write("GET /sse HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    end)

    vim.wait(2000, function()
      return raw:find("event: endpoint", 1, true) ~= nil
    end)
    assert.is_not_nil(raw:find("HTTP/1.1 200", 1, true))
    assert.is_not_nil(raw:find("event: endpoint", 1, true))
    assert.is_not_nil(
      raw:find("data: http://127.0.0.1:" .. server.port .. "/message?sessionId=", 1, true)
    )
    sock:close()
    sse.stop(server)
  end)

  it("round-trips tools/list via POST /message", function()
    -- LuaJIT: local x = (function() closure_refs_x; return val end)()
    -- captures x as nil upvalue even after = assign.
    -- Must declare then assign separately.
    local server
    server = assert(sse.start({
      on_message = function(text)
        local msg = vim.json.decode(text)
        if msg.method == "tools/list" then
          sse.send(
            server,
            vim.json.encode({
              jsonrpc = "2.0",
              id = msg.id,
              result = { tools = tools.list() },
            })
          )
        end
      end,
    }))

    -- Connect to SSE, get sessionId
    local sock = vim.uv.new_tcp()
    local raw = ""
    sock:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock:read_start(function(rerr, data)
        if data then
          raw = raw .. data
        end
      end)
      sock:write("GET /sse HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    end)

    vim.wait(2000, function()
      return raw:find("event: endpoint", 1, true) ~= nil
    end)
    local session_id = raw:match("sessionId=([%w]+)")
    assert.is_not_nil(session_id)

    -- POST tools/list on separate connection (real MCP SSE uses separate connections)
    local post_sock = vim.uv.new_tcp()
    local post_raw = ""
    post_sock:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      post_sock:read_start(function(rerr, data)
        if data then
          post_raw = post_raw .. data
        end
      end)
      local body = vim.json.encode({ jsonrpc = "2.0", id = 1, method = "tools/list" })
      post_sock:write(
        "POST /message?sessionId="
          .. session_id
          .. " HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. body
      )
    end)

    vim.wait(2000, function()
      return raw:find("event: message", 1, true) ~= nil
    end)
    local data = raw:match("event: message\r\ndata: (.-)\r\n\r\n")
    assert.is_not_nil(data)
    local result = vim.json.decode(data)
    assert.equals(17, #result.result.tools)

    sock:close()
    sse.stop(server)
  end)

  it("rejects POST with wrong sessionId", function()
    local server = assert(sse.start({ on_message = function() end }))
    local sock = vim.uv.new_tcp()
    local raw = ""
    sock:connect("127.0.0.1", server.port, function()
      sock:read_start(function(_, data)
        if data then
          raw = raw .. data
        end
      end)
      sock:write("GET /sse HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    end)
    vim.wait(1000, function()
      return raw:find("200", 1, true) ~= nil
    end)

    local bad = vim.uv.new_tcp()
    local bad_raw = ""
    bad:connect("127.0.0.1", server.port, function()
      bad:read_start(function(_, data)
        if data then
          bad_raw = bad_raw .. data
        end
      end)
      bad:write(
        "POST /message?sessionId=WRONG HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 2\r\n\r\n{}"
      )
    end)
    vim.wait(1000, function()
      return #bad_raw > 0
    end)
    assert.is_not_nil(bad_raw:find("400", 1, true))

    sock:close()
    bad:close()
    sse.stop(server)
  end)

  it("POST /sse initialize returns 200 with Mcp-Session-Id and protocolVersion", function()
    local server = assert(sse.start({
      on_message = function(text, respond)
        local msg = vim.json.decode(text)
        if msg.method == "initialize" then
          respond(vim.json.encode({
            jsonrpc = "2.0",
            id = msg.id,
            result = { protocolVersion = "2025-03-26" },
          }))
        end
      end,
    }))

    local sock = vim.uv.new_tcp()
    local raw = ""
    sock:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock:read_start(function(_, data)
        if data then
          raw = raw .. data
        end
      end)
      local body = vim.json.encode({
        jsonrpc = "2.0",
        id = 1,
        method = "initialize",
        params = {
          protocolVersion = "2025-03-26",
          clientInfo = { name = "test", version = "1.0.0" },
        },
      })
      sock:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. body
      )
    end)

    vim.wait(2000, function()
      return raw:find("HTTP/1.1 200", 1, true) ~= nil
    end)

    assert.is_not_nil(raw:find("HTTP/1.1 200", 1, true))
    local session_id = raw:match("Mcp%-Session%-Id: ([%w]+)")
    assert.is_not_nil(session_id)

    local json_body = raw:match("\r\n\r\n(.+)")
    assert.is_not_nil(json_body)
    local result = vim.json.decode(json_body)
    assert.equals("2025-03-26", result.result.protocolVersion)

    sock:close()
    sse.stop(server)
  end)

  it("POST /sse tools/list with valid Mcp-Session-Id returns 200 with tools", function()
    local server = assert(sse.start({
      on_message = function(text, respond)
        local msg = vim.json.decode(text)
        if msg.method == "initialize" then
          respond(vim.json.encode({
            jsonrpc = "2.0",
            id = msg.id,
            result = { protocolVersion = "2025-03-26" },
          }))
        elseif msg.method == "tools/list" and respond then
          respond(vim.json.encode({
            jsonrpc = "2.0",
            id = msg.id,
            result = { tools = tools.list() },
          }))
        end
      end,
    }))

    -- Step 1: initialize to get session id
    local sock1 = vim.uv.new_tcp()
    local raw1 = ""
    sock1:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock1:read_start(function(_, data)
        if data then
          raw1 = raw1 .. data
        end
      end)
      local body = vim.json.encode({
        jsonrpc = "2.0",
        id = 1,
        method = "initialize",
      })
      sock1:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. body
      )
    end)
    vim.wait(2000, function()
      return raw1:find("HTTP/1.1 200", 1, true) ~= nil
    end)
    local session_id = raw1:match("Mcp%-Session%-Id: ([%w]+)")
    assert.is_not_nil(session_id)
    sock1:close()

    -- Step 2: tools/list with the session id header
    local sock2 = vim.uv.new_tcp()
    local raw2 = ""
    sock2:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock2:read_start(function(_, data)
        if data then
          raw2 = raw2 .. data
        end
      end)
      local body = vim.json.encode({
        jsonrpc = "2.0",
        id = 2,
        method = "tools/list",
      })
      sock2:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n"
          .. "Mcp-Session-Id: "
          .. session_id
          .. "\r\n\r\n"
          .. body
      )
    end)
    vim.wait(2000, function()
      return raw2:find("HTTP/1.1 200", 1, true) ~= nil
    end)
    assert.is_not_nil(raw2:find("HTTP/1.1 200", 1, true))

    local json_body = raw2:match("\r\n\r\n(.+)")
    assert.is_not_nil(json_body)
    local result = vim.json.decode(json_body)
    assert.is_not_nil(result.result.tools)
    assert.equals(17, #result.result.tools)

    sock2:close()
    sse.stop(server)
  end)

  it("POST /sse tools/list without Mcp-Session-Id returns 401", function()
    local server = assert(sse.start({
      on_message = function(text, respond)
        local msg = vim.json.decode(text)
        if msg.method == "initialize" then
          respond(vim.json.encode({
            jsonrpc = "2.0",
            id = msg.id,
            result = { protocolVersion = "2025-03-26" },
          }))
        end
      end,
    }))

    -- Initialize first to mint a session
    local sock1 = vim.uv.new_tcp()
    local raw1 = ""
    sock1:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock1:read_start(function(_, data)
        if data then
          raw1 = raw1 .. data
        end
      end)
      local body = vim.json.encode({
        jsonrpc = "2.0",
        id = 1,
        method = "initialize",
      })
      sock1:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. body
      )
    end)
    vim.wait(2000, function()
      return raw1:find("HTTP/1.1 200", 1, true) ~= nil
    end)
    sock1:close()

    -- Now send tools/list without Mcp-Session-Id (session exists → must 401)
    local sock2 = vim.uv.new_tcp()
    local raw2 = ""
    sock2:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock2:read_start(function(_, data)
        if data then
          raw2 = raw2 .. data
        end
      end)
      local body = vim.json.encode({
        jsonrpc = "2.0",
        id = 2,
        method = "tools/list",
      })
      sock2:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. body
      )
    end)
    vim.wait(2000, function()
      return raw2:find("401", 1, true) ~= nil
    end)
    assert.is_not_nil(raw2:find("401 Unauthorized", 1, true))

    sock2:close()
    sse.stop(server)
  end)

  it("POST /sse tools/list with wrong Mcp-Session-Id returns 401", function()
    local server = assert(sse.start({
      on_message = function(text, respond)
        local msg = vim.json.decode(text)
        if msg.method == "initialize" then
          respond(vim.json.encode({
            jsonrpc = "2.0",
            id = msg.id,
            result = { protocolVersion = "2025-03-26" },
          }))
        end
      end,
    }))

    -- Initialize first to mint a session
    local sock1 = vim.uv.new_tcp()
    local raw1 = ""
    sock1:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock1:read_start(function(_, data)
        if data then
          raw1 = raw1 .. data
        end
      end)
      local body = vim.json.encode({
        jsonrpc = "2.0",
        id = 1,
        method = "initialize",
      })
      sock1:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. body
      )
    end)
    vim.wait(2000, function()
      return raw1:find("HTTP/1.1 200", 1, true) ~= nil
    end)
    sock1:close()

    -- Now send tools/list with a wrong session id
    local sock2 = vim.uv.new_tcp()
    local raw2 = ""
    sock2:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock2:read_start(function(_, data)
        if data then
          raw2 = raw2 .. data
        end
      end)
      local body = vim.json.encode({
        jsonrpc = "2.0",
        id = 2,
        method = "tools/list",
      })
      sock2:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n"
          .. "Mcp-Session-Id: WRONGDEADBEEF\r\n\r\n"
          .. body
      )
    end)
    vim.wait(2000, function()
      return raw2:find("401", 1, true) ~= nil
    end)
    assert.is_not_nil(raw2:find("401 Unauthorized", 1, true))

    sock2:close()
    sse.stop(server)
  end)

  it("POST /sse malformed JSON body returns 400 and server stays alive", function()
    local server = assert(sse.start({
      on_message = function(text, respond)
        local msg = vim.json.decode(text)
        if msg.method == "initialize" and respond then
          respond(vim.json.encode({
            jsonrpc = "2.0",
            id = msg.id,
            result = { protocolVersion = "2025-03-26" },
          }))
        end
      end,
    }))

    -- Malformed body: send non-JSON content
    local sock1 = vim.uv.new_tcp()
    local raw1 = ""
    sock1:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock1:read_start(function(_, data)
        if data then
          raw1 = raw1 .. data
        end
      end)
      sock1:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: 13\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. "not valid json"
      )
    end)
    vim.wait(2000, function()
      return raw1:find("400", 1, true) ~= nil
    end)
    assert.is_not_nil(raw1:find("400 Bad Request", 1, true))
    sock1:close()

    -- Verify server still handles valid requests
    local sock2 = vim.uv.new_tcp()
    local raw2 = ""
    sock2:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock2:read_start(function(_, data)
        if data then
          raw2 = raw2 .. data
        end
      end)
      local body = vim.json.encode({
        jsonrpc = "2.0",
        id = 1,
        method = "initialize",
      })
      sock2:write(
        "POST /sse HTTP/1.1\r\n"
          .. "Host: 127.0.0.1\r\n"
          .. "Content-Length: "
          .. #body
          .. "\r\n"
          .. "Content-Type: application/json\r\n\r\n"
          .. body
      )
    end)
    vim.wait(2000, function()
      return raw2:find("HTTP/1.1 200", 1, true) ~= nil
    end)
    assert.is_not_nil(raw2:find("HTTP/1.1 200", 1, true))

    sock2:close()
    sse.stop(server)
  end)
end)

describe("MCP config", function()
  local mcp_config

  before_each(function()
    mcp_config = require("clide.mcp_config")
    -- ensure tools available for full test
    tools.setup()
  end)

  it("writes .mcp.json with clide SSE URL and auto-approves in settings", function()
    local tmpdir = vim.fn.tempname() .. "_clide_mcp"
    vim.fn.mkdir(tmpdir)
    local original_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmpdir)
    vim.fn.mkdir(".claude", "p")

    mcp_config.install(12345)

    -- MCP server config in .mcp.json
    local raw = table.concat(vim.fn.readfile(".mcp.json"), "\n")
    local data = vim.json.decode(raw)
    assert.equals("sse", data.mcpServers.clide.type)
    assert.equals("http://127.0.0.1:12345/sse", data.mcpServers.clide.url)

    -- Auto-approval in settings.local.json
    local settings =
      vim.json.decode(require("plenary.path"):new(".claude/settings.local.json"):read())
    assert.equals("clide", settings.enabledMcpjsonServers[1])

    -- Idempotent: second call doesn't corrupt
    mcp_config.install(12346)
    local raw2 = table.concat(vim.fn.readfile(".mcp.json"), "\n")
    local data2 = vim.json.decode(raw2)
    assert.equals("http://127.0.0.1:12346/sse", data2.mcpServers.clide.url)

    vim.fn.chdir(original_cwd)
    vim.fn.delete(tmpdir, "rf")
  end)

  it("preserves existing .mcp.json keys when merging", function()
    local tmpdir = vim.fn.tempname() .. "_clide_mcp2"
    vim.fn.mkdir(tmpdir)
    local original_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmpdir)
    vim.fn.mkdir(".claude", "p")

    -- Pre-populate .mcp.json with another server
    local existing = { mcpServers = { other_server = { type = "stdio" } } }
    require("plenary.path"):new(".mcp.json"):write(vim.json.encode(existing), "w")

    mcp_config.install(9999)
    local data = vim.json.decode(require("plenary.path"):new(".mcp.json"):read())
    assert.equals("stdio", data.mcpServers.other_server.type)
    assert.equals("sse", data.mcpServers.clide.type)

    vim.fn.chdir(original_cwd)
    vim.fn.delete(tmpdir, "rf")
  end)
end)
