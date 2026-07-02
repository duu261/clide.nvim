local frame = require("clide.server.frame")
local handshake = require("clide.server.handshake")
local log = require("clide.util.log")

local M = {}

--- Start the server.
--- opts: { auth_token, on_message(client, text), on_connect(client), on_disconnect(client) }
--- @return table|nil server {port, clients, handle}, string|nil err
function M.start(opts)
  local server = { clients = {}, opts = opts }
  local handle, port

  for _ = 1, 5 do
    local try = vim.uv.new_tcp()
    -- port randomness is not security-relevant (the token is); math.random fine
    local candidate = math.random(10000, 65535)
    if try:bind("127.0.0.1", candidate) == 0 then
      handle, port = try, candidate
      break
    end
    try:close()
  end
  if not handle then
    return nil, "could not bind a port after 5 attempts"
  end

  server.handle = handle
  server.port = port

  handle:listen(16, function(err)
    if err then
      log.log("error", "listen error: " .. err)
      return
    end
    local sock = vim.uv.new_tcp()
    handle:accept(sock)
    local client = { sock = sock, buf = "", ready = false, rejected = false }
    sock:read_start(function(rerr, data)
      if rerr or not data then
        M.disconnect(server, client)
        return
      end
      client.buf = client.buf .. data
      local ok, perr = pcall(M.process, server, client)
      if not ok then
        log.log("error", "ws process error: " .. tostring(perr))
        M.disconnect(server, client)
      end
    end)
  end)

  return server
end

function M.process(server, client)
  if client.rejected then
    return
  end
  if not client.ready then
    local req = handshake.parse_request(client.buf)
    if not req then
      return -- wait for more bytes
    end
    local resp, err_resp = handshake.response(req, server.opts.auth_token)
    if not resp then
      client.rejected = true
      client.sock:write(err_resp, function()
        M.disconnect(server, client)
      end)
      return
    end
    client.buf = client.buf:match("\r\n\r\n(.*)$") or ""
    client.ready = true
    client.sock:write(resp)
    table.insert(server.clients, client)
    if server.opts.on_connect then
      vim.schedule(function()
        server.opts.on_connect(client)
      end)
    end
  end

  while true do
    local f, rest = frame.decode(client.buf)
    if not f then
      return
    end
    client.buf = rest
    if f.opcode == frame.TEXT then
      if server.opts.on_message then
        vim.schedule(function()
          server.opts.on_message(client, f.payload)
        end)
      end
    elseif f.opcode == frame.PING then
      client.sock:write(frame.encode(frame.PONG, f.payload))
    elseif f.opcode == frame.CLOSE then
      client.sock:write(frame.encode(frame.CLOSE, f.payload))
      M.disconnect(server, client)
      return
    end
    -- ponytail: no fragmented-message reassembly; Claude CLI sends single,
    -- unfragmented TEXT frames. Add continuation handling if that changes.
  end
end

function M.send(client, text)
  if client.sock and not client.sock:is_closing() then
    client.sock:write(frame.encode(frame.TEXT, text))
  end
end

function M.disconnect(server, client)
  for i, c in ipairs(server.clients) do
    if c == client then
      table.remove(server.clients, i)
      break
    end
  end
  if client.sock and not client.sock:is_closing() then
    client.sock:close()
  end
  if server.opts.on_disconnect then
    vim.schedule(function()
      server.opts.on_disconnect(client)
    end)
  end
end

function M.stop(server)
  for _, client in ipairs(server.clients) do
    if client.sock and not client.sock:is_closing() then
      client.sock:write(frame.encode(frame.CLOSE, ""))
      client.sock:close()
    end
  end
  server.clients = {}
  if server.handle and not server.handle:is_closing() then
    server.handle:close()
  end
end

return M
