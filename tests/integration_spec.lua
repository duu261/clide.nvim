local ws = require("clide.server.ws")
local rpc_mod = require("clide.server.rpc")
local frame = require("clide.server.frame")
local tools = require("clide.tools")

--- Client-side masked TEXT frame with zero mask key (XOR no-op).
local function client_frame(payload)
  local len = #payload
  local header
  if len < 126 then
    header = string.char(0x81, 0x80 + len)
  else
    header = string.char(0x81, 0x80 + 126, math.floor(len / 256), len % 256)
  end
  return header .. "\0\0\0\0" .. payload
end

describe("integration: full protocol flow", function()
  it("handshakes, initializes, lists and calls tools", function()
    tools.setup()

    local rpc
    local server = assert(ws.start({
      auth_token = "integration-token",
      on_message = function(_, text)
        rpc:handle(text)
      end,
      on_connect = function(client)
        rpc = rpc_mod.new(function(text)
          ws.send(client, text)
        end)
      end,
    }))

    local received = {} -- decoded JSON responses, in order
    local raw = ""
    local handshake_done = false

    local sock = vim.uv.new_tcp()
    sock:connect("127.0.0.1", server.port, function(err)
      assert(not err, err)
      sock:read_start(function(rerr, data)
        assert(not rerr, rerr)
        if not data then
          return
        end
        raw = raw .. data
        if not handshake_done then
          local _, hend = raw:find("\r\n\r\n")
          if not hend then
            return
          end
          assert(raw:find("101 Switching Protocols"), "handshake failed: " .. raw)
          raw = raw:sub(hend + 1)
          handshake_done = true
        end
        while true do
          local f, rest = frame.decode(raw)
          if not f then
            break
          end
          raw = rest
          if f.opcode == frame.TEXT then
            table.insert(received, vim.json.decode(f.payload))
          end
        end
      end)
      sock:write(
        "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
          .. "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
          .. "Sec-WebSocket-Version: 13\r\n"
          .. "x-claude-code-ide-authorization: integration-token\r\n\r\n"
      )
    end)

    vim.wait(2000, function()
      return handshake_done
    end)
    assert.is_true(handshake_done)

    -- initialize
    sock:write(client_frame(
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
        .. '{"protocolVersion":"2025-03-26","capabilities":{},'
        .. '"clientInfo":{"name":"test","version":"0"}}}'
    ))
    vim.wait(2000, function()
      return #received >= 1
    end)
    assert.equals("2025-03-26", received[1].result.protocolVersion)
    assert.equals("clide.nvim", received[1].result.serverInfo.name)

    -- tools/list: all 12 protocol tools present
    sock:write(client_frame('{"jsonrpc":"2.0","id":2,"method":"tools/list"}'))
    vim.wait(2000, function()
      return #received >= 2
    end)
    local names = {}
    for _, t in ipairs(received[2].result.tools) do
      names[t.name] = true
    end
    for _, expected in ipairs({
      "openFile", "openDiff", "getCurrentSelection", "getLatestSelection",
      "getOpenEditors", "getWorkspaceFolders", "getDiagnostics",
      "checkDocumentDirty", "saveDocument", "close_tab",
      "closeAllDiffTabs", "executeCode",
    }) do
      assert.is_true(names[expected] == true, "missing tool: " .. expected)
    end

    -- tools/call round trip
    sock:write(client_frame(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":'
        .. '{"name":"getWorkspaceFolders","arguments":{}}}'
    ))
    vim.wait(2000, function()
      return #received >= 3
    end)
    local body = vim.json.decode(received[3].result.content[1].text)
    assert.is_true(body.success)
    assert.equals(vim.fn.getcwd(), body.rootPath)

    -- wrong-token client is rejected
    local bad = vim.uv.new_tcp()
    local bad_resp = nil
    bad:connect("127.0.0.1", server.port, function()
      bad:read_start(function(_, data)
        if data then
          bad_resp = (bad_resp or "") .. data
        end
      end)
      bad:write(
        "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
          .. "Connection: Upgrade\r\nSec-WebSocket-Key: abc\r\n"
          .. "Sec-WebSocket-Version: 13\r\n"
          .. "x-claude-code-ide-authorization: WRONG\r\n\r\n"
      )
    end)
    vim.wait(2000, function()
      return bad_resp ~= nil
    end)
    assert.matches("401", bad_resp)

    sock:close()
    bad:close()
    ws.stop(server)
  end)
end)
