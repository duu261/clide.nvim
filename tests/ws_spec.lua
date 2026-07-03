local ws = require("clide.server.ws")

describe("ws server", function()
  it("accepts a real TCP client and completes the handshake", function()
    local server = assert(ws.start({ auth_token = "tok" }))
    local response = nil

    local sock = vim.uv.new_tcp()
    sock:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock:read_start(function(rerr, data)
        assert(not rerr, rerr)
        if data then
          response = (response or "") .. data
        end
      end)
      sock:write(
        "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
          .. "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
          .. "Sec-WebSocket-Version: 13\r\n"
          .. "x-claude-code-ide-authorization: tok\r\n\r\n"
      )
    end)

    vim.wait(2000, function()
      return response ~= nil and response:find("\r\n\r\n") ~= nil
    end)

    assert.is_not_nil(response)
    assert.matches("101 Switching Protocols", response)
    assert.matches("s3pPLMBiTxaQ9kYGzzhZRbK%+xOo=", response)

    sock:close()
    ws.stop(server)
  end)

  it("binds a port in the protocol range", function()
    local server = assert(ws.start({ auth_token = "tok" }))
    assert.is_true(server.port >= 1024 and server.port <= 65535)
    ws.stop(server)
  end)

  it("assigns distinct ports without collision across many servers", function()
    local servers, seen = {}, {}
    for _ = 1, 20 do
      local s = assert(ws.start({ auth_token = "tok" }), "bind should never fail")
      assert.is_nil(seen[s.port], "duplicate port " .. tostring(s.port))
      seen[s.port] = true
      servers[#servers + 1] = s
    end
    for _, s in ipairs(servers) do
      ws.stop(s)
    end
  end)
end)
