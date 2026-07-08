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
      local sessions = M.state.server and M.state.server.sessions
      if not sessions then
        return
      end
      for _, s in pairs(sessions) do
        if s.client == client then
          s.rpc:handle(text)
          return
        end
      end
    end,
    on_connect = function(client)
      if not M.state.server then
        return
      end
      M.state._next_client_id = (M.state._next_client_id or 0) + 1
      local cid = tostring(M.state._next_client_id)
      local session = {
        client = client,
        rpc = rpc_mod.new(function(text)
          ws.send(client, text)
        end, cid),
        id = cid,
      }
      table.insert(M.state.server.sessions, session)
      M.state.connected = true
      M.state.client_count = (M.state.client_count or 0) + 1
      log.log("info", "claude connected [client " .. cid .. "]")
      require("clide.events").emit("ClideConnected", { client_id = cid })
      vim.schedule(function()
        vim.notify("clide: Claude " .. cid .. " connected", vim.log.levels.INFO)
      end)
    end,
    on_disconnect = function(client)
      local sessions = M.state.server and M.state.server.sessions
      if not sessions then
        log.log("warn", "on_disconnect after state wipe: session table gone")
        return
      end
      local dc_id = "?"
      for idx, s in ipairs(sessions) do
        if s.client == client then
          dc_id = s.id or "?"
          sessions[idx] = nil
          break
        end
      end
      M.state.connected = next(sessions) ~= nil
      M.state.client_count = math.max(0, (M.state.client_count or 1) - 1)
      log.log("info", "claude disconnected [client " .. dc_id .. "]")
      require("clide.events").emit("ClideDisconnected", { client_id = dc_id })
      vim.schedule(function()
        vim.notify("clide: Claude " .. dc_id .. " disconnected", vim.log.levels.WARN)
      end)
    end,
  })
  if not server then
    vim.notify("clide: " .. err, vim.log.levels.ERROR)
    return
  end

  lockfile.write(server.port, token)
  M.state.server = server
  server.sessions = {}
  selection.enable(function(method, params)
    if not server.sessions then
      -- should never fire: sessions is set right above and survives until GC
      log.log("warn", "dropping " .. method .. ": server.sessions is nil")
      return
    end
    for _, s in pairs(server.sessions) do
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
  require("clide.events").setup()
  -- Auto-register with which-key.nvim for discoverability
  pcall(function()
    local wk_ok, wk = pcall(require, "which-key")
    if wk_ok and wk.add then
      wk.add({
        { "<Leader>m", group = "clide" },
        { "<Leader>mt", desc = "Toggle Terminal" },
        { "<Leader>ms", desc = "Start Server" },
        { "<Leader>mq", desc = "Stop Server" },
        { "<Leader>ml", desc = "View Log" },
        { "<Leader>me", desc = "Send Selection", mode = "x" },
        { "<Leader>mz", desc = "Send + Toggle", mode = "x" },
        { "<Leader>mf", desc = "Send File" },
        { "<Leader>mb", desc = "Send Buffer (pick)" },
        { "<Leader>mC", desc = "Continue Session" },
        { "<Leader>mh", desc = "Browse Sessions" },
        { "<Leader>mw", desc = "Create Worktree" },
        { "<Leader>mqf", desc = "Send Quickfix" },
        { "<Leader>meq", desc = "Edits to Quickfix" },
        { "<Leader>mdq", desc = "Diags to Quickfix" },
      })
    end
  end)
  -- Auto-configure jsonls for settings schema validation (non-fatal)
  pcall(function()
    require("clide.jsonls_config").configure()
  end)

  -- ponytail: global debounce timer, single diag push across buffers.
  -- Per-buffer timers if collision proves measurable in practice.
  local diag_group = vim.api.nvim_create_augroup("ClideDiagnostics", { clear = true })
  local diag_timer = nil
  local severity_map = { "Error", "Warning", "Information", "Hint" }
  -- every push lands in Claude's context window; filter to what changes behavior
  local push_cfg = require("clide.config").get().diagnostics_push
  local min_severity = push_cfg
    and ({ error = "ERROR", warn = "WARN", info = "INFO", hint = "HINT" })[push_cfg]
  local diag_filter = min_severity
      and { severity = { min = vim.diagnostic.severity[min_severity] } }
    or nil
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = diag_group,
    callback = function(args)
      if not push_cfg then
        return
      end
      if diag_timer then
        diag_timer:stop()
        diag_timer:close()
      end
      diag_timer = vim.uv.new_timer()
      diag_timer:start(
        500,
        0,
        vim.schedule_wrap(function()
          diag_timer:stop()
          diag_timer:close()
          diag_timer = nil
          if not server.sessions then
            log.log("warn", "dropping diagnostics_changed: server.sessions is nil")
            return
          end
          local by_file = {}
          local diags = args.buf and vim.diagnostic.get(args.buf, diag_filter)
            or vim.diagnostic.get(nil, diag_filter)
          for _, d in ipairs(diags) do
            local name = vim.api.nvim_buf_get_name(d.bufnr)
            if name ~= "" then
              by_file[name] = by_file[name] or {}
              table.insert(by_file[name], {
                message = d.message,
                severity = severity_map[d.severity] or "Information",
                source = d.source,
                range = {
                  start = { line = d.lnum, character = d.col },
                  ["end"] = { line = d.end_lnum or d.lnum, character = d.end_col or d.col },
                },
              })
            end
          end
          local out = {}
          for name, list in pairs(by_file) do
            table.insert(out, { uri = "file://" .. name, diagnostics = list })
          end
          for _, s in ipairs(server.sessions) do
            if s.rpc then
              pcall(s.rpc.notify, s.rpc, "diagnostics_changed", { files = out })
            end
          end
        end)
      )
    end,
  })
  M.state._diag_group = diag_group
  M.state._diag_timer_ref = diag_timer -- ponytail: ref captured for stop() cleanup, timer may be replaced by callback

  M.state.server = server
  log.log("info", "server ready on port " .. server.port)
  require("clide.events").emit("ClideServerReady", { port = server.port })
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
  if state._diag_group then
    pcall(vim.api.nvim_del_augroup_by_id, state._diag_group)
  end
  if state._diag_timer_ref then
    pcall(function()
      state._diag_timer_ref:stop()
      state._diag_timer_ref:close()
    end)
  end

  require("clide.terminal").close()
  require("clide.status").teardown()
  require("clide.follow").teardown()
  require("clide.events").emit("ClideServerStop", {})
  require("clide.events").teardown()
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

function M.spawn()
  if not M.state.server then
    M.start()
    return
  end
  require("clide.terminal").spawn({
    CLAUDE_CODE_SSE_PORT = tostring(M.state.server.port),
    ENABLE_IDE_INTEGRATION = "true",
  })
  vim.notify("clide: spawned new claude pane", vim.log.levels.INFO)
end

return M
