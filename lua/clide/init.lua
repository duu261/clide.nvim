local M = {}

--- { server, clients[{client, rpc}], connected }
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
        local pok, perr = pcall(s.rpc.notify, s.rpc, method, params)
        if not pok then
          log.log("error", "selection notify error: " .. tostring(perr))
        end
      end
    end
  end)

  require("clide.status").setup()
  require("clide.follow").setup()

  M.state.server = server
  log.log("info", "server ready on port " .. server.port)
  vim.notify("clide: server ready on port " .. server.port, vim.log.levels.INFO)

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

  require("clide.terminal").close()
  require("clide.status").teardown()
  require("clide.follow").teardown()
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
