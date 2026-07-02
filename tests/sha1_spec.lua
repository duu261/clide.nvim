local sha1 = require("clide.util.sha1")

describe("sha1", function()
  it("hashes known vectors", function()
    assert.equals("da39a3ee5e6b4b0d3255bfef95601890afd80709", sha1.hex(""))
    assert.equals("a9993e364706816aba3e25717850c26c9cd0d89d", sha1.hex("abc"))
    assert.equals(
      "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12",
      sha1.hex("The quick brown fox jumps over the lazy dog")
    )
    -- 56 bytes: exercises two-block padding
    assert.equals(
      "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
      sha1.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
    )
  end)

  it("produces the RFC 6455 handshake accept key", function()
    local key = "dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    assert.equals("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", vim.base64.encode(sha1.digest(key)))
  end)
end)
