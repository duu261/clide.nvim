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
    assert.equals(12, #result.result.tools)

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
end)

describe("MCP config", function()
  local mcp_config

  before_each(function()
    mcp_config = require("clide.mcp_config")
    -- ensure tools available for full test
    tools.setup()
  end)

  it("writes settings.local.json with clide SSE URL", function()
    local tmpdir = vim.fn.tempname() .. "_clide_mcp"
    vim.fn.mkdir(tmpdir)
    local original_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmpdir)
    vim.fn.mkdir(".claude", "p")

    mcp_config.install(12345)

    local raw = table.concat(vim.fn.readfile(".claude/settings.local.json"), "\n")
    local data = vim.json.decode(raw)
    assert.equals("sse", data.mcpServers.clide.type)
    assert.equals("http://127.0.0.1:12345/sse", data.mcpServers.clide.url)

    -- Idempotent: second call doesn't corrupt
    mcp_config.install(12346)
    local raw2 = table.concat(vim.fn.readfile(".claude/settings.local.json"), "\n")
    local data2 = vim.json.decode(raw2)
    assert.equals("http://127.0.0.1:12346/sse", data2.mcpServers.clide.url)

    vim.fn.chdir(original_cwd)
    vim.fn.delete(tmpdir, "rf")
  end)

  it("preserves existing settings keys when merging", function()
    local tmpdir = vim.fn.tempname() .. "_clide_mcp2"
    vim.fn.mkdir(tmpdir)
    local original_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmpdir)
    vim.fn.mkdir(".claude", "p")

    -- Pre-populate with some other setting
    local existing = { otherKey = "value", mcpServers = { other_server = { type = "stdio" } } }
    require("plenary.path"):new(".claude/settings.local.json"):write(vim.json.encode(existing), "w")

    mcp_config.install(9999)
    local data = vim.json.decode(require("plenary.path"):new(".claude/settings.local.json"):read())
    assert.equals("value", data.otherKey)
    assert.equals("stdio", data.mcpServers.other_server.type)
    assert.equals("sse", data.mcpServers.clide.type)

    vim.fn.chdir(original_cwd)
    vim.fn.delete(tmpdir, "rf")
  end)
end)
