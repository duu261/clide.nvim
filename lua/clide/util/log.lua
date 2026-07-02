local M = { lines = {}, max = 200 }

local levels = { debug = 1, info = 2, warn = 3, error = 4 }

function M.log(level, msg)
  table.insert(M.lines, string.format("[%s] %s %s", level, os.date("%H:%M:%S"), msg))
  if #M.lines > M.max then
    table.remove(M.lines, 1)
  end
  if levels[level] >= levels.warn then
    vim.schedule(function()
      vim.notify("clide: " .. msg, level == "error" and vim.log.levels.ERROR or vim.log.levels.WARN)
    end)
  end
end

function M.show()
  vim.cmd("botright new")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, M.lines)
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
end

return M
