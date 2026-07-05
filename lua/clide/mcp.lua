local M = {}

--- Build the headless nvim argv for detached MCP server.
--- Batches rtp entries into --cmd calls to avoid the ~20-60 -c/--cmd cap.
--- @return string[]
function M.build_argv()
  local argv = { "nvim", "--headless", "-u", "NONE" }
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
  return argv
end

--- Check whether a child MCP server is listening on the given port.
--- @param port integer
--- @return boolean
function M.reattach(port)
  local ok = pcall(function()
    local chan = vim.fn.sockconnect(
      "tcp",
      "127.0.0.1:" .. port,
      { mode = "json", timeout = 50 }
    )
    vim.fn.chanclose(chan)
  end)
  return ok
end

--- Ensure an MCP child server is running, reattaching or spawning as needed.
--- Stores state in M.state (child_job, mcp_port).
--- @param state table shared clide state table
function M.ensure_running(state)
  local lockfile_mcp = require("clide.lockfile_mcp")

  local lock_data = lockfile_mcp.read()
  if lock_data then
    if M.reattach(lock_data.ssePort) then
      state.mcp_port = lock_data.ssePort
      vim.notify(
        "clide: reattached to MCP server on port " .. lock_data.ssePort,
        vim.log.levels.INFO
      )
      return
    end
    lockfile_mcp.remove()
  end

  local argv = M.build_argv()

  state.child_job = vim.fn.jobstart(argv, {
    stdin = "pipe",
    stderr_buffered = true,
    on_exit = function(_, code, signal_or_stderr)
      vim.schedule(function()
        lockfile_mcp.remove()
        state.child_job = nil
        state.mcp_port = nil
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

  state.mcp_port = lock_data.ssePort
  vim.notify("clide: MCP server started on port " .. lock_data.ssePort, vim.log.levels.INFO)

  if require("clide.config").get().auto_install_mcp then
    require("clide.mcp_config").install(lock_data.ssePort)
  end
end

--- Stop a running MCP child process.
--- @param state table shared clide state table
function M.stop(state)
  if state.child_job then
    pcall(function()
      vim.fn.chansend(vim.fn.jobgetchannel(state.child_job), "DIE\n")
    end)
  end
end

return M