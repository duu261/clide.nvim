local M = {}

function M.setup()
  local clide = require("clide")

  vim.api.nvim_create_user_command("ClideStart", clide.start, { desc = "Start clide server + claude" })
  vim.api.nvim_create_user_command("ClideStop", clide.stop, { desc = "Stop clide server" })
  vim.api.nvim_create_user_command("ClideToggle", clide.toggle, { desc = "Toggle claude terminal" })
  vim.api.nvim_create_user_command("ClideSend", function(cmd)
    require("clide.selection").send_at_mention(cmd.line1, cmd.line2)
  end, { range = true, desc = "Send selection to claude as at-mention" })
  vim.api.nvim_create_user_command("ClideLog", function()
    require("clide.util.log").show()
  end, { desc = "Show clide log" })
end

return M
