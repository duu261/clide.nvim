local handshake = require("clide.server.handshake")

describe("handshake", function()
  it("computes the RFC 6455 accept key", function()
    assert.equals("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", handshake.accept_key("dGhlIHNhbXBsZSBub25jZQ=="))
  end)

  it("returns nil for an incomplete request", function()
    assert.is_nil(handshake.parse_request("GET / HTTP/1.1\r\nHost: x"))
  end)

  it("parses a complete request with lowercased headers", function()
    local req = handshake.parse_request(
      "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
        .. "Sec-WebSocket-Key: abc\r\nX-Claude-Code-Ide-Authorization: tok\r\n\r\n"
    )
    assert.equals("websocket", req.headers["upgrade"])
    assert.equals("tok", req.headers["x-claude-code-ide-authorization"])
  end)

  it("builds a 101 response for a valid authorized request", function()
    local req = handshake.parse_request(
      "GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        .. "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"
        .. "x-claude-code-ide-authorization: tok\r\n\r\n"
    )
    local resp = handshake.response(req, "tok")
    assert.matches("101 Switching Protocols", resp)
    assert.matches("s3pPLMBiTxaQ9kYGzzhZRbK%+xOo=", resp)
  end)

  it("rejects a bad token with 401", function()
    local req = handshake.parse_request(
      "GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        .. "Sec-WebSocket-Key: abc\r\nSec-WebSocket-Version: 13\r\n"
        .. "x-claude-code-ide-authorization: WRONG\r\n\r\n"
    )
    local resp, err = handshake.response(req, "tok")
    assert.is_nil(resp)
    assert.matches("401", err)
  end)
end)
