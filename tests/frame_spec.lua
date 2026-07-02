-- tests/frame_spec.lua
local frame = require("clide.server.frame")

describe("frame codec", function()
  it("decodes the RFC 6455 masked 'Hello' fixture", function()
    -- RFC 6455 §5.7: single-frame masked text message "Hello"
    local buf = string.char(0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58)
    local f, rest = frame.decode(buf)
    assert.is_not_nil(f)
    assert.equals(frame.TEXT, f.opcode)
    assert.is_true(f.fin)
    assert.equals("Hello", f.payload)
    assert.equals("", rest)
  end)

  it("returns nil on incomplete buffer and preserves it", function()
    local buf = string.char(0x81, 0x85, 0x37, 0xfa)
    local f, rest = frame.decode(buf)
    assert.is_nil(f)
    assert.equals(buf, rest)
  end)

  it("encodes server frames unmasked with FIN set", function()
    local out = frame.encode(frame.TEXT, "Hello")
    assert.equals(string.char(0x81, 0x05) .. "Hello", out)
  end)

  it("roundtrips a large payload through 16-bit length form", function()
    local payload = string.rep("x", 300)
    local encoded = frame.encode(frame.TEXT, payload)
    -- re-mask it as a client would, using a zero mask key (no-op mask)
    local header = string.char(0x81, 0x80 + 126, 1, 44, 0, 0, 0, 0)
    local f = frame.decode(header .. payload)
    assert.is_not_nil(f)
    assert.equals(payload, f.payload)
    assert.equals(#payload + 4, #encoded) -- 2 header + 2 extlen + payload, unmasked
  end)

  it("decodes two frames from one buffer", function()
    local one = string.char(0x81, 0x85, 0, 0, 0, 0) .. "Hello"
    local two = string.char(0x89, 0x80, 0, 0, 0, 0) -- masked PING, empty
    local f1, rest = frame.decode(one .. two)
    assert.equals("Hello", f1.payload)
    local f2, rest2 = frame.decode(rest)
    assert.equals(frame.PING, f2.opcode)
    assert.equals("", rest2)
  end)
end)
