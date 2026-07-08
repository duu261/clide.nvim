--- Autocommand events: nvim-native hook points for clide lifecycle.
--- Users hook in via: vim.api.nvim_create_autocmd("User", { pattern = "Clide*", ... })
--- VS Code has no equivalent — this is nvim-native extension model.
local M = {}

local group = nil

--- Emit a User autocommand event. data passed as vim.v.event.
function M.emit(name, data)
  if not group then
    return
  end
  -- ponytail: vim.schedule so events fire after caller's state settles.
  -- Prevents race where user's autocmd fires before clide's own setup completes.
  vim.schedule(function()
    vim.api.nvim_exec_autocmds("User", {
      group = group,
      pattern = name,
      data = data,
    })
  end)
end

function M.setup()
  if group then
    return
  end
  group = vim.api.nvim_create_augroup("ClideEvents", { clear = true })
end

function M.teardown()
  if group then
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
  group = nil
end

return M
