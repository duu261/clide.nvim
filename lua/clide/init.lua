local M = {}

--- { server, rpc, client, connected, child_job, mcp_port }
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

  -- Spawn or reattach to persistent MCP child process
  M.ensure_mcp_server()

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

--- Reattach to existing child or spawn headless nvim process.
function M.ensure_mcp_server()
  local lockfile_mcp = require("clide.lockfile_mcp")

  local lock_data = lockfile_mcp.read()
  if lock_data then
    local ok = pcall(function()
      local chan = vim.fn.sockconnect(
        "tcp",
        "127.0.0.1:" .. lock_data.ssePort,
        { mode = "json", timeout = 50 }
      )
      vim.fn.chanclose(chan)
    end)
    if ok then
      M.state.mcp_port = lock_data.ssePort
      vim.notify(
        "clide: reattached to MCP server on port " .. lock_data.ssePort,
        vim.log.levels.INFO
      )
      return
    end
    lockfile_mcp.remove()
  end

  local argv = { "nvim", "--headless", "-u", "NONE" }
  for _, p in ipairs(vim.opt.rtp:get()) do
    table.insert(argv, "--cmd")
    table.insert(argv, ("set rtp+=%s"):format(p))
  end
  table.insert(argv, "-c")
  table.insert(argv, "lua require('clide.server.detached').run()")

  M.state.child_job = vim.fn.jobstart(argv, {
    stdin = "pipe",
    on_exit = function(_, code)
      vim.schedule(function()
        lockfile_mcp.remove()
        M.state.child_job = nil
        M.state.mcp_port = nil
        if code ~= 0 then
          vim.notify("clide: MCP server exited (" .. code .. ")", vim.log.levels.WARN)
        end
      end)
    end,
  })

  local ok = vim.wait(5000, function()
    return vim.fn.filereadable(lockfile_mcp.path()) == 1
  end, 100)

  if not ok then
    vim.notify("clide: timeout waiting for MCP server", vim.log.levels.WARN)
    return
  end

  lock_data = lockfile_mcp.read()
  if not lock_data then
    vim.notify("clide: failed to read MCP server lockfile", vim.log.levels.WARN)
    return
  end

  M.state.mcp_port = lock_data.ssePort
  vim.notify("clide: MCP server started on port " .. lock_data.ssePort, vim.log.levels.INFO)

  if require("clide.config").get().auto_install_mcp then
    require("clide.mcp_config").install(lock_data.ssePort)
  end
end

function M.stop()
  if M.state.child_job then
    local channel = vim.fn.jobgetchannel(M.state.child_job)
    if channel then
      pcall(vim.fn.chansend, channel, "DIE\n")
    end
  end

  local state = M.state
  if state.server then
    require("clide.selection").disable()
    require("clide.lockfile").remove(state.server.port)
    require("clide.server.ws").stop(state.server)
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
