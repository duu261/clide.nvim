local M = {}

--- { server, rpc, client, connected }
M.state = {}

function M.setup(opts)
  require("clide.config").setup(opts)
  require("clide.commands").setup()
  if require("clide.config").get().autostart then
    M.start()
  end
end

function M.start()
  if M.state.server then
    vim.notify("clide: already running", vim.log.levels.INFO)
    return
  end
  vim.notify("clide: starting server...", vim.log.levels.INFO)

  local config = require("clide.config")
  local tools = require("clide.tools")
  local lockfile = require("clide.lockfile")
  local ws = require("clide.server.ws")
  local rpc_mod = require("clide.server.rpc")
  local selection = require("clide.selection")
  local log = require("clide.util.log")

  tools.setup()
  lockfile.clean_stale()

  local token = lockfile.generate_token()
  local rpc

  local server, err = ws.start({
    auth_token = token,
    on_message = function(_, text)
      rpc:handle(text)
    end,
    on_connect = function(client)
      M.state.client = client
      M.state.connected = true
      log.log("info", "claude connected")
      vim.schedule(function()
        vim.notify("clide: Claude connected", vim.log.levels.INFO)
      end)
    end,
    on_disconnect = function()
      M.state.client = nil
      M.state.connected = false
      log.log("info", "claude disconnected")
      vim.schedule(function()
        vim.notify("clide: Claude disconnected", vim.log.levels.WARN)
      end)
    end,
  })
  if not server then
    vim.notify("clide: " .. err, vim.log.levels.ERROR)
    return
  end

  rpc = rpc_mod.new(function(text)
    if M.state.client then
      ws.send(M.state.client, text)
    end
  end)

  lockfile.write(server.port, token)
  selection.enable(function(method, params)
    rpc:notify(method, params)
  end)

  require("clide.status").setup()

  M.state.server = server
  M.state.rpc = rpc
  vim.notify("clide: server ready on port " .. server.port, vim.log.levels.INFO)

  -- Start SSE MCP server (non-fatal: WS continues if this fails)
  local sse_ok, sse_err = pcall(function()
    local sse = require("clide.server.sse")
    local sse_server = sse.start({
      port = config.get().sse_port,
      on_message = function(text)
        if M.state.sse_rpc then
          M.state.sse_rpc:handle(text)
        end
      end,
    })
    if sse_server then
      M.state.sse_rpc = rpc_mod.new(function(text)
        sse.send(sse_server, text)
      end)
      M.state.sse_server = sse_server

      if config.get().auto_install_mcp then
        require("clide.mcp_config").install(sse_server.port)
      end
    else
      vim.notify("clide: SSE MCP server failed to start", vim.log.levels.WARN)
    end
  end)
  if not sse_ok then
    vim.notify("clide: SSE MCP server error: " .. tostring(sse_err), vim.log.levels.WARN)
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ClideLifecycle", { clear = true }),
    callback = M.stop,
  })

  require("clide.terminal").open({
    CLAUDE_CODE_SSE_PORT = tostring(server.port),
    ENABLE_IDE_INTEGRATION = "true",
  })
  vim.notify("clide: Claude launched in terminal", vim.log.levels.INFO)
end

function M.stop()
  local state = M.state
  if state.server then
    require("clide.selection").disable()
    require("clide.lockfile").remove(state.server.port)
    require("clide.server.ws").stop(state.server)
  end
  if state.sse_server then
    require("clide.server.sse").stop(state.sse_server)
  end
  require("clide.status").teardown()
  M.state = {}
end

function M.restart()
  M.stop()
  vim.schedule(M.start)
end

function M.toggle()
  if M.state.server then
    require("clide.terminal").toggle({
      CLAUDE_CODE_SSE_PORT = tostring(M.state.server.port),
      ENABLE_IDE_INTEGRATION = "true",
    })
  else
    M.start()
  end
end

return M
