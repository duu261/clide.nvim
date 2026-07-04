local log = require("clide.util.log")

-- Cap the unparsed HTTP header buffer so a slow client can't grow it unbounded.
local MAX_HEADER_SIZE = 16 * 1024

local M = {}

--- Minimal HTTP request parse from buffered bytes.
--- Returns nil if headers not yet complete.
local function parse_http(buf)
  local hend = (buf or ""):find("\r\n\r\n", 1, true)
  if not hend then
    return nil
  end
  local header_text = buf:sub(1, hend - 1)
  local rest = buf:sub(hend + 4)

  -- Request line
  local method, full_path = header_text:match("^(%u+) (.+) HTTP/")
  if not method then
    return nil -- not a request line, drop
  end

  -- Split path and query
  local path, query = full_path, ""
  local qpos = full_path:find("?", 1, true)
  if qpos then
    path = full_path:sub(1, qpos - 1)
    query = full_path:sub(qpos + 1)
  end

  -- Headers
  local content_length = 0
  local mcp_session_id = nil
  for line in header_text:gmatch("[^\r\n]+") do
    local key, val = line:match("^(.-): (.+)$")
    if key then
      if key:lower() == "content-length" then
        content_length = tonumber(val) or 0
      elseif key:lower() == "mcp-session-id" then
        mcp_session_id = val
      end
    end
  end

  return {
    method = method,
    path = path,
    query = query,
    content_length = content_length,
    mcp_session_id = mcp_session_id,
    rest = rest,
  }
end

--- Parse query string key=value pairs.
local function parse_query(qs)
  local t = {}
  for k, v in qs:gmatch("([^=&]+)=([^=&]*)") do
    t[k] = v
  end
  return t
end

function M.start(opts)
  opts = opts or {}
  local server = {
    handle = nil,
    port = 0,
    sse_client = nil,
    session_id = nil,
    streamable_session_id = nil,
    timer = nil,
  }

  local handle = vim.uv.new_tcp()
  local bind_port = opts.port or 0
  local bind_ok, bind_err = pcall(handle.bind, handle, "127.0.0.1", bind_port)
  if not bind_ok and bind_port ~= 0 then
    -- Fallback: configured port busy, let OS pick one
    log.log("warn", "sse port " .. bind_port .. " busy, using dynamic fallback")
    handle:close()
    handle = vim.uv.new_tcp()
    bind_ok, bind_err = pcall(handle.bind, handle, "127.0.0.1", 0)
  end
  if not bind_ok then
    handle:close()
    log.log("error", "sse bind failed: " .. tostring(bind_err))
    return nil
  end
  server.handle = handle
  server.port = handle:getsockname().port

  handle:listen(128, function(err)
    if err then
      log.log("error", "listen error: " .. tostring(err))
      vim.schedule(function()
        vim.notify("clide: SSE server listen failed — " .. tostring(err), vim.log.levels.ERROR)
      end)
      return
    end
    local ok, aerr = pcall(function()
      local client = vim.uv.new_tcp()
      handle:accept(client)
      local buf = ""

      client:read_start(function(rerr, data)
        local ok, perr = pcall(function()
          if rerr then
            -- ECONNRESET is normal TCP teardown when MCP client closes SSE stream
            if rerr ~= "ECONNRESET" then
              log.log("warn", "sse read error: " .. tostring(rerr))
            end
            pcall(client.close, client)
            return
          end
          if not data then
            -- Connection closed
            pcall(client.close, client)
            return
          end
          buf = buf .. data

          -- Cap unparsed header size
          if #buf > MAX_HEADER_SIZE then
            log.log("warn", "sse header exceeded " .. MAX_HEADER_SIZE .. " bytes")
            pcall(client.close, client)
            return
          end

          -- Parse HTTP
          local req = parse_http(buf)
          if not req then
            return -- waiting for more headers
          end

          -- Need body?
          if req.content_length > 0 and #req.rest < req.content_length then
            return -- waiting for body
          end

          buf = "" -- reset buffer

          if req.path == "/sse" then
            -- Reject methods other than GET and POST
            if req.method ~= "GET" and req.method ~= "POST" then
              pcall(
                client.write,
                client,
                "HTTP/1.1 405 Method Not Allowed\r\nAllow: GET, POST\r\nContent-Length: 0\r\n\r\n"
              )
              pcall(client.close, client)
              return
            end
            if req.method == "POST" then
              -- Streamable HTTP POST /sse
              local body = req.rest:sub(1, req.content_length)
              local ok, msg = pcall(vim.json.decode, body)
              if not ok or type(msg) ~= "table" then
                pcall(client.write, client, "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
                pcall(client.close, client)
                return
              end
              -- Session gate: initialize mints or reuses a session.
              -- Preserve across re-initializations so MCP client doesn't
              -- get "Session not found" on tool calls after reconnect (#55970).
              if
                msg.method == "initialize" and (not req.mcp_session_id or req.mcp_session_id == "")
              then
                if not server.streamable_session_id then
                  local rand_bytes = vim.uv.random(4)
                  server.streamable_session_id = rand_bytes:gsub(".", function(c)
                    return string.format("%02x", string.byte(c))
                  end)
                end
              else
                if
                  not server.streamable_session_id
                  or req.mcp_session_id ~= server.streamable_session_id
                then
                  pcall(
                    client.write,
                    client,
                    "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n"
                  )
                  pcall(client.close, client)
                  return
                end
              end
              if opts.on_message then
                local respond = function(json_text)
                  local sid = server.streamable_session_id
                  local n = #json_text
                  pcall(
                    client.write,
                    client,
                    "HTTP/1.1 200 OK\r\n"
                      .. "Content-Type: application/json\r\n"
                      .. "Mcp-Session-Id: "
                      .. sid
                      .. "\r\n"
                      .. "Content-Length: "
                      .. tostring(n)
                      .. "\r\n\r\n"
                      .. json_text
                  )
                  pcall(client.close, client)
                end
                -- Defer to main event loop so MCP tool handlers can call
                -- Neovim API without hitting E5560 (fast event context).
                vim.schedule(function()
                  opts.on_message(body, respond)
                end)
              end
              -- Keep connection open: respond closure writes response and closes
            else
              -- SSE event stream (GET)
              if server.sse_client then
                pcall(server.sse_client.close, server.sse_client)
              end
              server.sse_client = client
              -- Preserve session_id across reconnects so MCP client POSTs
              -- to /message?sessionId=… keep working after SSE stream drops.
              if not server.session_id then
                local rand_bytes = vim.uv.random(4)
                server.session_id = (
                  rand_bytes:gsub(".", function(c)
                    return string.format("%02x", string.byte(c))
                  end)
                )
              end

              -- Stop existing keepalive timer
              if server.timer then
                server.timer:stop()
              end

              -- Send 200 + SSE headers
              pcall(
                client.write,
                client,
                "HTTP/1.1 200 OK\r\n"
                  .. "Content-Type: text/event-stream\r\n"
                  .. "Cache-Control: no-cache\r\n"
                  .. "Connection: keep-alive\r\n\r\n"
              )

              -- Send endpoint event
              pcall(
                client.write,
                client,
                "event: endpoint\r\n"
                  .. "data: http://127.0.0.1:"
                  .. server.port
                  .. "/message?sessionId="
                  .. server.session_id
                  .. "\r\n\r\n"
              )

              -- Keepalive timer (15s)
              server.timer = vim.uv.new_timer()
              server.timer:start(15000, 15000, function()
                if server.sse_client then
                  local ok3 = pcall(function()
                    server.sse_client:write(": keepalive\r\n\r\n")
                  end)
                  if not ok3 then
                    server.sse_client = nil
                    if server.timer then
                      server.timer:stop()
                    end
                  end
                end
              end)
            end
          elseif req.path == "/message" then
            -- Parse sessionId from query
            local params = parse_query(req.query)
            -- Reject before an SSE stream exists (session_id still nil): otherwise
            -- a missing sessionId compares nil ~= nil = false and slips past auth.
            if not server.session_id or params.sessionId ~= server.session_id then
              pcall(client.write, client, "HTTP/1.1 400 Bad Request\r\n\r\n")
              pcall(client.close, client)
              return
            end
            local body = req.rest:sub(1, req.content_length)
            if opts.on_message then
              -- Defer to main event loop so MCP tool handlers can call
              -- Neovim API without hitting E5560 (fast event context).
              vim.schedule(function()
                opts.on_message(body)
              end)
            end
            pcall(client.write, client, "HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\n\r\n")
          else
            pcall(client.write, client, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
          end

          -- Close non-SSE connections; SSE stream stays open
          if req.path ~= "/sse" and client ~= server.sse_client then
            pcall(client.close, client)
          end
        end)
        if not ok then
          log.log("warn", "sse read error: " .. tostring(perr))
          pcall(client.close, client)
        end
      end)
    end)
    if not ok then
      log.log("warn", "sse accept error: " .. tostring(aerr))
    end
  end)

  return server
end

function M.send(server, text)
  if server.sse_client then
    local frame = "event: message\r\ndata: " .. text .. "\r\n\r\n"
    pcall(server.sse_client.write, server.sse_client, frame)
  end
end

function M.stop(server)
  if server.timer then
    server.timer:stop()
    server.timer:close()
  end
  if server.sse_client then
    pcall(server.sse_client.close, server.sse_client)
  end
  if server.handle then
    server.handle:close()
  end
end

return M
