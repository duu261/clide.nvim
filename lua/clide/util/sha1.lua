local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local rshift, lshift, rol, tobit = bit.rshift, bit.lshift, bit.rol, bit.tobit

local M = {}

---@param msg string
---@return string digest 20-byte binary digest
function M.digest(msg)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local len = #msg
  local bits = len * 8
  local pad = string.char(0x80) .. string.rep("\0", (55 - len) % 64)
  local hi, lo = math.floor(bits / 2 ^ 32), bits % 2 ^ 32
  local tail = {}
  for _, v in ipairs({ hi, lo }) do
    tail[#tail + 1] = string.char(
      math.floor(v / 2 ^ 24) % 256,
      math.floor(v / 2 ^ 16) % 256,
      math.floor(v / 2 ^ 8) % 256,
      v % 256
    )
  end
  msg = msg .. pad .. table.concat(tail)

  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local off = chunk + i * 4
      local a, b, c, d = msg:byte(off, off + 3)
      w[i] = bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)
    end
    for i = 16, 79 do
      w[i] = rol(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1)
    end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then
        f, k = bor(band(b, c), band(bnot(b), d)), 0x5A827999
      elseif i < 40 then
        f, k = bxor(b, c, d), 0x6ED9EBA1
      elseif i < 60 then
        f, k = bor(band(b, c), band(b, d), band(c, d)), 0x8F1BBCDC
      else
        f, k = bxor(b, c, d), 0xCA62C1D6
      end
      local temp = tobit(rol(a, 5) + f + e + k + w[i])
      e, d, c, b, a = d, c, rol(b, 30), a, temp
    end
    h0, h1, h2 = tobit(h0 + a), tobit(h1 + b), tobit(h2 + c)
    h3, h4 = tobit(h3 + d), tobit(h4 + e)
  end

  local out = {}
  for _, h in ipairs({ h0, h1, h2, h3, h4 }) do
    out[#out + 1] = string.char(
      band(rshift(h, 24), 0xFF),
      band(rshift(h, 16), 0xFF),
      band(rshift(h, 8), 0xFF),
      band(h, 0xFF)
    )
  end
  return table.concat(out)
end

---@param msg string
---@return string hex 40-char lowercase hex digest
function M.hex(msg)
  return (
    M.digest(msg):gsub(".", function(c)
      return string.format("%02x", string.byte(c))
    end)
  )
end

return M
