local M = { name = "none" }

function M.is_available()
  return true
end

function M.open(_, env)
  local parts = {}
  for k, v in pairs(env or {}) do
    table.insert(parts, k .. "=" .. v)
  end
  table.sort(parts)
  vim.notify(
    "clide: run claude manually with:\n  " .. table.concat(parts, " ") .. " claude",
    vim.log.levels.INFO
  )
end

function M.close() end

function M.toggle(cmd, env)
  M.open(cmd, env)
end

return M
