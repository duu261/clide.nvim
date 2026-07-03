local M = {}

function M.setup()
  local clide = require("clide")

  vim.api.nvim_create_user_command(
    "ClideStart",
    clide.start,
    { desc = "Start clide server + claude" }
  )
  vim.api.nvim_create_user_command("ClideStop", clide.stop, { desc = "Stop clide server" })
  vim.api.nvim_create_user_command("ClideToggle", clide.toggle, { desc = "Toggle claude terminal" })
  vim.api.nvim_create_user_command("ClideSend", function(cmd)
    require("clide.selection").send_at_mention(cmd.line1, cmd.line2)
  end, { range = true, desc = "Send selection to claude as at-mention" })
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
  vim.api.nvim_create_user_command("ClideInstallHooks", function()
    require("clide.status").install_hooks()
  end, { desc = "Install Claude Code status hooks into project settings" })

  vim.api.nvim_create_user_command("ClideInstallMCP", function()
    local state = require("clide").state
    if not state.sse_server then
      vim.notify("clide: SSE server not running — start clide first", vim.log.levels.WARN)
      return
    end
    require("clide.mcp_config").install(state.sse_server.port)
    vim.notify("clide: MCP config written to .claude/settings.local.json", vim.log.levels.INFO)
  end, { desc = "Write clide MCP server config for Claude Code" })
end

return M
