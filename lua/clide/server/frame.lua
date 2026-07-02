-- lua/clide/server/frame.lua
-- RFC 6455 frame codec. Server side: incoming frames from clients are
-- masked, outgoing frames must not be masked.
local bit = require("bit")
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local rshift, lshift = bit.rshift, bit.lshift
local unpack = unpack or table.unpack

local M = {
  TEXT = 0x1,
  BINARY = 0x2,
  CLOSE = 0x8,
  PING = 0x9,
  PONG = 0xA,
}

--- Decode one frame from buf.
--- @return table|nil frame {fin, opcode, payload}, string rest
function M.decode(buf)
  if #buf < 2 then
    return nil, buf
  end
  local b1, b2 = buf:byte(1, 2)
  local fin = band(b1, 0x80) ~= 0
  local opcode = band(b1, 0x0F)
  local masked = band(b2, 0x80) ~= 0
  local len = band(b2, 0x7F)
  local pos = 3

  if len == 126 then
    if #buf < 4 then
      return nil, buf
    end
    local h, l = buf:byte(3, 4)
    len = bor(lshift(h, 8), l)
    pos = 5
  elseif len == 127 then
    if #buf < 10 then
      return nil, buf
    end
    len = 0
    for i = 3, 10 do
      len = len * 256 + buf:byte(i)
    end
    pos = 11
  end

  local mask_len = masked and 4 or 0
  if #buf < pos + mask_len + len - 1 then
    return nil, buf
  end

  local payload
  if masked then
    local key = { buf:byte(pos, pos + 3) }
    pos = pos + 4
    local raw = buf:sub(pos, pos + len - 1)
    local out = {}
    -- unmask in chunks; string.char has an argument limit
    for i = 1, len, 4096 do
      local last = math.min(i + 4095, len)
      local bytes = { raw:byte(i, last) }
      for j = 1, #bytes do
        bytes[j] = bxor(bytes[j], key[(i + j - 2) % 4 + 1])
      end
      out[#out + 1] = string.char(unpack(bytes))
    end
    payload = table.concat(out)
  else
    payload = buf:sub(pos, pos + len - 1)
  end

  return { fin = fin, opcode = opcode, payload = payload }, buf:sub(pos + len)
end

--- Encode a server frame (unmasked, FIN always set).
function M.encode(opcode, payload)
  payload = payload or ""
  local len = #payload
  local header
  if len < 126 then
    header = string.char(bor(0x80, opcode), len)
  elseif len < 65536 then
    header = string.char(bor(0x80, opcode), 126, rshift(len, 8), band(len, 0xFF))
  else
    local bytes = {}
    local n = len
    for i = 8, 1, -1 do
      bytes[i] = n % 256
      n = math.floor(n / 256)
    end
    header = string.char(bor(0x80, opcode), 127, unpack(bytes))
  end
  return header .. payload
end

return M
