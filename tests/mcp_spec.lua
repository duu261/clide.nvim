local mcp = require("clide.mcp")

describe("clide.mcp", function()
  describe("build_argv", function()
    it("builds a headless nvim command line with batched rtp", function()
      local argv = mcp.build_argv()
      assert.is_table(argv)
      assert.equals("nvim", argv[1])
      assert.equals("--headless", argv[2])
      assert.equals("-u", argv[3])
      assert.equals("NONE", argv[4])

      -- rtp entries are batched into --cmd/set rtp+= groups
      local has_rtp = false
      local has_detached_cmd = false
      for i, arg in ipairs(argv) do
        if arg == "--cmd" and argv[i + 1] and argv[i + 1]:match("^set rtp%+=") then
          has_rtp = true
        end
        if arg == "lua require('clide.server.detached').run()" then
          has_detached_cmd = true
        end
      end
      assert.is_true(has_rtp, "argv contains rtp setup via --cmd")
      assert.is_true(has_detached_cmd, "argv launches detached server")
    end)

    it("batches rtp into groups of 15 or fewer", function()
      local argv = mcp.build_argv()
      for i, arg in ipairs(argv) do
        if arg == "--cmd" and argv[i + 1] then
          local rtp_line = argv[i + 1]
          if rtp_line:match("^set rtp%+=") then
            -- Extract the rtp value and count entries
            local entries = rtp_line:gsub("^set rtp%+=", "")
            local count = 0
            for _ in entries:gmatch("[^,]+") do
              count = count + 1
            end
            assert.is_true(
              count <= 15,
              "rtp batch has " .. count .. " entries, should be <= 15"
            )
          end
        end
      end
    end)
  end)

  describe("reattach", function()
    it("returns true when child is listening on the port", function()
      -- Start a temporary TCP listener to simulate an MCP child
      local server = vim.uv.new_tcp()
      server:bind("127.0.0.1", 0)
      local port = server:getsockname().port
      server:listen(1, function() end)

      local ok, alive = pcall(mcp.reattach, port)
      assert.is_true(ok)
      assert.is_true(alive)

      server:close()
    end)

    it("returns false when nothing is listening", function()
      -- Use a high port that's unlikely to be in use
      -- We need a port where nothing actually listens.
      -- Create a server, get port, close it, then check reattach
      local tmp = vim.uv.new_tcp()
      tmp:bind("127.0.0.1", 0)
      local port = tmp:getsockname().port
      tmp:close()

      -- Give OS a tick to release
      vim.wait(50)

      local ok, alive = pcall(mcp.reattach, port)
      assert.is_true(ok)
      assert.is_false(alive)
    end)
  end)
end)
