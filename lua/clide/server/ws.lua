local frame = require("clide.server.frame")
local handshake = require("clide.server.handshake")
local log = require("clide.util.log")

local M = {}

-- Same rationale as frame.MAX_PAYLOAD: cap the unparsed handshake buffer so a
-- client that never sends "\r\n\r\n" can't grow it without limit.
local MAX_HANDSHAKE_SIZE = 16 * 1024
-- After handshake, a client sending partial frames (slow-roll attack) could grow
-- the accumulated unparsed buffer without bound. Disconnect above this threshold.
local MAX_BUFFER_SIZE = 256 * 1024

--- Start the server.
--- opts: { auth_token, on_message(client, text), on_connect(client), on_disconnect(client) }
--- @return table|nil server {port, clients, handle}, string|nil err
function M.start(opts)
  local server = { clients = {}, opts = opts }
  -- Bind port 0: the OS hands back a guaranteed-free ephemeral port, so there
  -- is no candidate collision to retry (unseeded math.random used to flake here).
  local handle = vim.uv.new_tcp()
  local bound, bind_err = pcall(function()
    assert(handle:bind("127.0.0.1", 0) == 0)
  end)
  if not bound then
    handle:close()
    return nil, "could not bind a port: " .. tostring(bind_err)
  end
  local addr = handle:getsockname()

  server.handle = handle
  server.port = addr.port

  handle:listen(16, function(err)
    if err then
      log.log("error", "listen error: " .. err)
      vim.schedule(function()
        vim.notify("clide: WS server listen failed — " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    local ok, aerr = pcall(function()
      local sock = vim.uv.new_tcp()
      handle:accept(sock)
      local client = { sock = sock, buf = "", ready = false, rejected = false }
      sock:read_start(function(rerr, data)
        if rerr or not data then
          M.disconnect(server, client)
          return
        end
        client.buf = client.buf .. data
        local pok, perr = pcall(M.process, server, client)
        if not pok then
          log.log("error", "ws process error: " .. tostring(perr))
          M.disconnect(server, client)
        end
      end)
    end)
    if not ok then
      log.log("error", "accept error: " .. tostring(aerr))
      vim.schedule(function()
        vim.notify("clide: WS accept failed — " .. tostring(aerr), vim.log.levels.WARN)
      end)
    end
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
      if #client.buf > MAX_HANDSHAKE_SIZE then
        log.log("error", "handshake request too large")
        vim.schedule(function()
          vim.notify("clide: WS handshake too large", vim.log.levels.WARN)
        end)
        M.disconnect(server, client)
      end
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
    local f, rest, ferr = frame.decode(client.buf)
    if ferr then
      log.log("error", ferr)
      M.disconnect(server, client)
      return
    end
    if not f then
      if #client.buf > MAX_BUFFER_SIZE then
        log.log("error", "client buffer exceeded " .. MAX_BUFFER_SIZE .. " bytes")
        vim.schedule(function()
          vim.notify(
            "clide: WS client buffer exceeded " .. MAX_BUFFER_SIZE .. " bytes",
            vim.log.levels.WARN
          )
        end)
        M.disconnect(server, client)
      end
      return
    end
    client.buf = rest
    if f.opcode == frame.TEXT then
      if server.opts.on_message then
        vim.schedule(function()
          local ok, merr = pcall(server.opts.on_message, client, f.payload)
          if not ok then
            log.log("error", "on_message handler error: " .. tostring(merr))
            vim.schedule(function()
              vim.notify("clide: WS handler error — " .. tostring(merr), vim.log.levels.ERROR)
            end)
          end
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
