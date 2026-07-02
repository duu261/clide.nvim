local M = {}

local notify_fn
local timer
local augroup

--- Build a selection object from the current buffer/mode.
--- Returns: { text, filePath, fileUrl, selection = { start, end, isEmpty } }
function M.build()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local mode = vim.fn.mode()

  -- Handle visual mode (charwise, linewise, blockwise)
  if mode == "v" or mode == "V" or mode == "\22" then
    local spos = vim.fn.getpos("v")
    local epos = vim.fn.getpos(".")
    -- normalize direction: start comes before end
    if spos[2] > epos[2] or (spos[2] == epos[2] and spos[3] > epos[3]) then
      spos, epos = epos, spos
    end
    local lines = vim.fn.getregion(spos, epos, { type = mode })
    return {
      text = table.concat(lines, "\n"),
      filePath = file_path,
      fileUrl = "file://" .. file_path,
      selection = {
        start = { line = spos[2] - 1, character = spos[3] - 1 },
        ["end"] = { line = epos[2] - 1, character = epos[3] }, -- end exclusive
        isEmpty = false,
      },
    }
  end

  -- Normal mode: cursor position as empty selection
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = { line = cursor[1] - 1, character = cursor[2] }
  return {
    text = "",
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = { start = pos, ["end"] = pos, isEmpty = true },
  }
end

local function emit()
  if not notify_fn then
    return
  end
  local ok, sel = pcall(M.build)
  if ok and sel.filePath ~= "" then
    M._latest = sel
    notify_fn("selection_changed", sel)
  end
end

--- Enable debounced selection_changed notifications.
--- notify: function(method, params)
function M.enable(notify)
  if timer then
    pcall(function()
      timer:stop()
      timer:close()
    end)
    timer = nil
  end
  notify_fn = notify
  timer = vim.uv.new_timer()
  augroup = vim.api.nvim_create_augroup("ClideSelection", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = augroup,
    callback = function()
      timer:stop()
      timer:start(100, 0, vim.schedule_wrap(emit))
    end,
  })
end

--- Disable selection tracking.
function M.disable()
  if timer then
    pcall(function()
      timer:stop()
      timer:close()
    end)
    timer = nil
  end
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
    augroup = nil
  end
  notify_fn = nil
end

--- Send an at_mention notification for lines (1-based, converted to 0-based).
function M.send_at_mention(line1, line2)
  if notify_fn then
    notify_fn("at_mentioned", {
      filePath = vim.api.nvim_buf_get_name(0),
      lineStart = line1 - 1,
      lineEnd = line2 - 1,
    })
  end
end

--- Get the most recent selection.
function M.latest()
  return M._latest
end

return M
