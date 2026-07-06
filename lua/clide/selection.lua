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
        ["end"] = { line = epos[2], character = epos[3] }, -- end exclusive
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

--- Build a selection from the '< '> marks, for use right after leaving
--- visual mode (when "v"/"." marks are already gone but the marks persist).
function M.build_from_marks()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local spos = vim.fn.getpos("'<")
  local epos = vim.fn.getpos("'>")
  if spos[2] > epos[2] or (spos[2] == epos[2] and spos[3] > epos[3]) then
    spos, epos = epos, spos
  end
  local vmode = vim.fn.visualmode()
  local lines = vim.fn.getregion(spos, epos, { type = vmode })
  return {
    text = table.concat(lines, "\n"),
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = spos[2] - 1, character = spos[3] - 1 },
      ["end"] = { line = epos[2], character = epos[3] }, -- end exclusive
      isEmpty = false,
    },
  }
end

local function emit()
  if not notify_fn then
    return
  end
  local mode = vim.fn.mode()
  local ok, sel
  if mode == "v" or mode == "V" or mode == "\22" then
    -- Still in visual mode: build fresh selection
    ok, sel = pcall(M.build)
  elseif M._pending_selection then
    -- Just left visual mode: use the selection captured on ModeChanged
    sel = M._pending_selection
    M._pending_selection = nil
    ok = true
  else
    ok, sel = pcall(M.build)
  end
  if not ok or not sel then
    return
  end
  -- Deduplicate: skip if identical to the last sent selection
  local ls = M._last_sent
  if
    ls
    and ls.text == sel.text
    and ls.selection.start.line == sel.selection.start.line
    and ls.selection["end"].line == sel.selection["end"].line
    and ls.selection.isEmpty == sel.selection.isEmpty
    and ls.filePath == sel.filePath
  then
    return
  end
  if not sel.selection.isEmpty then
    M._latest = sel
  end
  M._last_sent = sel
  notify_fn("selection_changed", sel)
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
      -- Capture visual selection synchronously while still in visual mode,
      -- so that when emit() fires after the debounce window we still have
      -- the visual region even if the mode has already changed to normal.
      local mode = vim.fn.mode()
      if mode == "v" or mode == "V" or mode == "\22" then
        local ok, sel = pcall(M.build)
        if ok and not sel.selection.isEmpty then
          M._pending_selection = sel
        end
      else
        -- ModeChanged fires AFTER the mode has already flipped, so a
        -- single-line visual selection (no CursorMoved in between) never
        -- hits the branch above. If we just left visual mode, rebuild the
        -- selection from the '< '> marks instead of the (now gone) "v" mark.
        local old_mode = vim.v.event.old_mode or ""
        local first = old_mode:sub(1, 1)
        if first == "v" or first == "V" or first == "\22" then
          local ok, sel = pcall(M.build_from_marks)
          if ok and sel and not sel.selection.isEmpty then
            M._pending_selection = sel
          end
        end
      end
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
