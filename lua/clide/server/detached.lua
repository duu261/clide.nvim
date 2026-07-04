--- Headless Neovim child process entry point.
--- Spawned by init.lua via jobstart. Runs the SSE MCP server.
--- Stdin watchdog: parent death → EOF → exit. "DIE" → graceful shutdown.

local M = {}

local log

local function stdin_watchdog()
  local ok, pipe = pcall(vim.uv.new_pipe, false)
  if not ok then
    return
  end
  local ok2 = pipe:open(0)
  if not ok2 then
    return
  end
  pipe:read_start(function(err, data)
    if err or not data then
      os.exit(0)
    end
    if data:match("DIE") then
      local sse = require("clide.server.sse")
      if M.server then
        sse.stop(M.server)
      end
      os.exit(0)
    end
  end)
end

function M.run()
  log = require("clide.util.log")
  stdin_watchdog()

  local tools = require("clide.tools")
  local sse = require("clide.server.sse")
  local rpc_mod = require("clide.server.rpc")

  tools.setup()

  M.server = sse.start({
    on_message = function(text, respond)
      if respond then
        local one_off = rpc_mod.new(respond)
        one_off:handle(text)
      elseif M.rpc then
        M.rpc:handle(text)
      end
    end,
  })

  if not M.server then
    log.log("error", "child: sse.start() returned nil")
    os.exit(1)
  end

  log.log("info", "child: sse bound to port " .. M.server.port)

  M.rpc = rpc_mod.new(function(text)
    sse.send(M.server, text)
  end)

  local lockfile_mcp = require("clide.lockfile_mcp")
  lockfile_mcp.write_child(M.server.port, vim.uv.os_getpid())

  -- Child stays alive via libuv event loop (SSE server keeps it running).
  -- stdin_watchdog handles exit conditions.
end

return M
