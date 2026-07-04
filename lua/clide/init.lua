local M = {}

--- { server, clients[{client, rpc}], connected, child_job, mcp_port }
M.state = {}

function M.setup(opts)
  require("clide.config").setup(opts)
  require("clide.commands").setup()
  local cfg = require("clide.config").get()

  -- Normal mode cmd mappings
  for cmd, lhs in pairs(cfg.cmd_keymaps) do
    if cmd ~= "send" and cmd ~= "send_toggle" then
      vim.keymap.set("n", lhs, "<Cmd>Clide" .. cmd:gsub("^.", string.upper) .. "<CR>", {
        desc = "clide: " .. cmd,
        silent = true,
      })
    end
  end

  -- Visual mode: send selection to Claude
  if cfg.cmd_keymaps.send then
    vim.keymap.set("x", cfg.cmd_keymaps.send, ":'<,'>ClideSend<CR>", {
      desc = "clide: send selection",
      silent = true,
    })
  end

  -- Visual mode: send selection + toggle terminal
  if cfg.cmd_keymaps.send_toggle then
    vim.keymap.set("x", cfg.cmd_keymaps.send_toggle, ":'<,'>ClideSend<CR>:ClideToggle<CR>", {
      desc = "clide: send selection + toggle",
      silent = true,
    })
  end

  if cfg.autostart then
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

  local server, err = ws.start({
    auth_token = token,
    on_message = function(client, text)
      if not M.state.clients then
        return
      end
      for _, s in pairs(M.state.clients) do
        if s.client == client then
          s.rpc:handle(text)
          return
        end
      end
    end,
    on_connect = function(client)
      M.state.clients = M.state.clients or {}
      local session = {
        client = client,
        rpc = rpc_mod.new(function(text)
          ws.send(client, text)
        end),
      }
      table.insert(M.state.clients, session)
      M.state.connected = true
      log.log("info", "claude connected")
      vim.schedule(function()
        vim.notify("clide: Claude connected", vim.log.levels.INFO)
      end)
    end,
    on_disconnect = function(client)
      if not M.state.clients then
        return
      end
      for id, s in pairs(M.state.clients) do
        if s.client == client then
          M.state.clients[id] = nil
          break
        end
      end
      M.state.connected = next(M.state.clients) ~= nil
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

  lockfile.write(server.port, token)
  selection.enable(function(method, params)
    if not M.state.clients then
      return
    end
    for _, s in pairs(M.state.clients) do
      if s.rpc then
        pcall(s.rpc.notify, s.rpc, method, params)
      end
    end
  end)

  require("clide.status").setup()

  M.state.server = server
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
  -- Batch rtp entries into few --cmd calls (nvim has a ~20-60 cap on -c/--cmd args).
  -- Comma-separated in one set rtp+= avoids blowing the limit.
  local rtp_batch = {}
  for _, p in ipairs(vim.opt.rtp:get()) do
    table.insert(rtp_batch, p)
    if #rtp_batch >= 15 then
      table.insert(argv, "--cmd")
      table.insert(argv, "set rtp+=" .. table.concat(rtp_batch, ","))
      rtp_batch = {}
    end
  end
  if #rtp_batch > 0 then
    table.insert(argv, "--cmd")
    table.insert(argv, "set rtp+=" .. table.concat(rtp_batch, ","))
  end
  table.insert(argv, "-c")
  table.insert(argv, "lua require('clide.server.detached').run()")

  M.state.child_job = vim.fn.jobstart(argv, {
    stdin = "pipe",
    stderr_buffered = true,
    on_exit = function(_, code, signal_or_stderr)
      vim.schedule(function()
        lockfile_mcp.remove()
        M.state.child_job = nil
        M.state.mcp_port = nil
        if code ~= 0 then
          local stderr_str = (type(signal_or_stderr) == "table" and #signal_or_stderr > 0)
              and table.concat(signal_or_stderr, "\n")
            or nil
          local msg = "clide: MCP server exited (" .. code .. ")"
          if stderr_str then
            msg = msg .. "\n" .. stderr_str
          end
          vim.notify(msg, vim.log.levels.WARN)
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
    pcall(function()
      vim.fn.chansend(vim.fn.jobgetchannel(M.state.child_job), "DIE\n")
    end)
  end

  local state = M.state
  if state.server then
    require("clide.selection").disable()
    require("clide.lockfile").remove(state.server.port)
    require("clide.server.ws").stop(state.server)
  end

  require("clide.terminal").close()
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
