local sha1 = require("clide.util.sha1")

local M = {}

local GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

function M.accept_key(key)
  return vim.base64.encode(sha1.digest(key .. GUID))
end

--- @return table|nil req {method, path, headers} — nil until "\r\n\r\n" seen
function M.parse_request(data)
  local head = data:match("^(.-)\r\n\r\n")
  if not head then
    return nil
  end
  local lines = vim.split(head, "\r\n")
  local method, path = lines[1]:match("^(%S+)%s+(%S+)")
  local headers = {}
  for i = 2, #lines do
    local k, v = lines[i]:match("^([^:]+):%s*(.*)$")
    if k then
      headers[k:lower()] = v
    end
  end
  return { method = method, path = path, headers = headers }
end

--- @return string|nil response, string|nil error_response
function M.response(req, auth_token)
  local h = req.headers
  if
    req.method ~= "GET"
    or not h["sec-websocket-key"]
    or (h["upgrade"] or ""):lower() ~= "websocket"
  then
    return nil, "HTTP/1.1 400 Bad Request\r\n\r\n"
  end
  -- Deviation from spec §auth: spec mentions WS close 1008, but auth happens
  -- at the HTTP stage before the WS connection exists — 401 is the correct
  -- rejection here and matches what a failed upgrade looks like to the client.
  if h["x-claude-code-ide-authorization"] ~= auth_token then
    return nil, "HTTP/1.1 401 Unauthorized\r\n\r\n"
  end
  return table.concat({
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Accept: " .. M.accept_key(h["sec-websocket-key"]),
    "\r\n",
  }, "\r\n")
end

return M
