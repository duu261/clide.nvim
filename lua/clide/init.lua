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
    return -- already running
  end

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
    end,
    on_disconnect = function()
      M.state.client = nil
      M.state.connected = false
      log.log("info", "claude disconnected")
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

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ClideLifecycle", { clear = true }),
    callback = M.stop,
  })

  require("clide.terminal").open({
    CLAUDE_CODE_SSE_PORT = tostring(server.port),
    ENABLE_IDE_INTEGRATION = "true",
  })
end

function M.stop()
  local state = M.state
  if state.server then
    require("clide.selection").disable()
    require("clide.lockfile").remove(state.server.port)
    require("clide.server.ws").stop(state.server)
  end
  require("clide.status").teardown()
  M.state = {}
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
