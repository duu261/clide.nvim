local M = {}

function M.setup()
  local clide = require("clide")

  vim.api.nvim_create_user_command(
    "ClideStart",
    clide.start,
    { desc = "Start clide server + claude" }
  )
  vim.api.nvim_create_user_command("ClideStop", clide.stop, { desc = "Stop clide server" })
  vim.api.nvim_create_user_command("ClideRestart", clide.restart, { desc = "Restart clide server" })
  vim.api.nvim_create_user_command("ClideToggle", clide.toggle, { desc = "Toggle claude terminal" })
  vim.api.nvim_create_user_command("ClideFocus", function()
    if not clide.state.server then
      vim.notify("clide: server not running", vim.log.levels.WARN)
      return
    end
    require("clide.terminal").toggle({
      CLAUDE_CODE_SSE_PORT = tostring(clide.state.server.port),
      ENABLE_IDE_INTEGRATION = "true",
    })
  end, { desc = "Focus the Claude terminal pane" })
  vim.api.nvim_create_user_command(
    "ClideSpawn",
    clide.spawn,
    { desc = "Spawn another claude terminal pane" }
  )
  vim.api.nvim_create_user_command("ClideSend", function(cmd)
    require("clide.selection").send_at_mention(cmd.line1, cmd.line2)
    vim.notify(
      "clide: sent lines " .. cmd.line1 .. "-" .. cmd.line2 .. " to Claude",
      vim.log.levels.INFO
    )
    if require("clide.config").get().focus_on_send then
      require("clide.terminal").toggle({
        CLAUDE_CODE_SSE_PORT = tostring(require("clide").state.server.port),
        ENABLE_IDE_INTEGRATION = "true",
      })
    end
  end, { range = true, desc = "Send selection to claude as at-mention" })
  vim.api.nvim_create_user_command("ClideSendBuffer", function(cmd)
    require("clide.selection").send_buffer(cmd.args)
  end, { nargs = 1, complete = "buffer", desc = "Send entire buffer to claude" })
  vim.api.nvim_create_user_command("ClideLog", function()
    require("clide.util.log").show()
  end, { desc = "Show clide log" })
  vim.api.nvim_create_user_command("ClideReviewTab", function()
    local queue = require("clide.review.queue")
    local review = queue.current()
    if not review then
      vim.notify("clide: no active review in this buffer", vim.log.levels.WARN)
      return
    end
    if review.resolved > 0 then
      vim.notify("clide: review partially resolved — finish inline", vim.log.levels.WARN)
      return
    end
    -- hand the pending respond over to the classic diff tab
    local open_diff = require("clide.tools.open_diff")
    local engine = require("clide.review.engine")
    local respond = review.respond
    review.respond = function() end -- neutralize; classic tab owns the response now
    engine.resolve_all(review, "reject")
    open_diff.open_classic({
      tab_name = review.tab_name,
      new_path = vim.api.nvim_buf_get_name(review.bufnr),
      new_contents = table.concat(review.new_lines, "\n") .. "\n",
      respond = respond,
    })
  end, { desc = "Reopen current review as side-by-side diff tab" })
  vim.api.nvim_create_user_command("ClideReviewList", function()
    require("clide.review.queue").quickfix()
  end, { desc = "List all pending review hunks in quickfix" })
  vim.api.nvim_create_user_command("ClideInstallHooks", function()
    require("clide.status").install_hooks()
  end, { desc = "Install Claude Code status hooks into project settings" })
  vim.api.nvim_create_user_command("ClideContinue", function()
    require("clide.session").continue()
  end, { desc = "Continue most recent Claude session" })
  vim.api.nvim_create_user_command("ClideSessions", function()
    require("clide.session").pick_session()
  end, { desc = "Browse and resume past Claude sessions" })
  vim.api.nvim_create_user_command("ClideWorktree", function(cmd)
    local args = cmd.args
    local path = args and #args > 0 and vim.fn.expand(args)
      or vim.fn.expand("~/worktrees/" .. os.date("%Y-%m-%d-%H%M%S"))
    vim.notify("clide: creating worktree at " .. path, vim.log.levels.INFO)
    vim.cmd("terminal git worktree add " .. path .. " HEAD")
  end, { nargs = "?", complete = "dir", desc = "Create git worktree for isolation" })
  vim.api.nvim_create_user_command("ClideSetup", function()
    require("clide.setup_wizard").run()
  end, { desc = "Interactive setup wizard (VS Code walkthrough equivalent)" })
  vim.api.nvim_create_user_command("ClideSendQf", function()
    require("clide.qf_bridge").send_qf()
  end, { desc = "Send quickfix list contents to Claude" })
  vim.api.nvim_create_user_command("ClideEditsToQf", function()
    require("clide.qf_bridge").edits_to_qf()
  end, { desc = "Populate quickfix with files Claude edited" })
  vim.api.nvim_create_user_command("ClideDiagToQf", function()
    require("clide.qf_bridge").diag_to_qf()
  end, { desc = "Populate quickfix with diagnostics (Claude-visible lints)" })
  vim.api.nvim_create_user_command("ClideBufferPick", function()
    local bufs = vim.fn.getbufinfo({ buflisted = true })
    local items = {}
    for _, b in ipairs(bufs) do
      local name = vim.fn.fnamemodify(b.name, ":~:.")
      if b.name ~= "" then
        table.insert(items, {
          label = string.format("%s%s", name, b.changed == 1 and " [+]" or ""),
          bufnr = b.bufnr,
          name = b.name,
        })
      end
    end
    if #items == 0 then
      vim.notify("clide: no listed buffers", vim.log.levels.WARN)
      return
    end
    vim.ui.select(items, {
      prompt = "Send buffer to Claude",
      kind = "clide",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        require("clide.selection").send_buffer(choice.bufnr)
      end
    end)
  end, { desc = "Pick a buffer to send to Claude (nvim-native picker)" })
  vim.api.nvim_create_user_command("ClideSendFile", function(cmd)
    local path = cmd.args and #cmd.args > 0 and vim.fn.expand(cmd.args) or vim.fn.expand("%")
    local lines = vim.fn.readfile(path)
    if #lines == 0 then
      vim.notify("clide: file is empty", vim.log.levels.WARN)
      return
    end
    require("clide.selection").send_buffer(vim.fn.bufadd(path))
    vim.notify("clide: sent " .. path .. " (" .. #lines .. " lines)", vim.log.levels.INFO)
  end, { nargs = "?", complete = "file", desc = "Send file to Claude (clide @-mention)" })
end

return M
