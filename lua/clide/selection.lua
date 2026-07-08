local M = {}

local notify_fn
local poll_timer

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

--- Track current selection for tool queries (getCurrentSelection /
--- getLatestSelection). No auto-push: explicit send is the only delivery
--- path (M.send_at_mention, wired to the send keymap). ModeChanged/FocusLost
--- proved unreliable on tmux (see CLAUDE.md); poll is pull-only now, never
--- pushes over the wire.
--- notify: function(method, params) — kept for send_at_mention's use.
function M.enable(notify)
  notify_fn = notify
  M._latest = nil
  if poll_timer then
    pcall(function()
      poll_timer:stop()
      poll_timer:close()
    end)
  end
  local prev_in_visual = false
  poll_timer = vim.uv.new_timer()
  poll_timer:start(
    200,
    200,
    vim.schedule_wrap(function()
      local m = vim.fn.mode()
      local in_visual = (m == "v" or m == "V" or m == "\22")
      if in_visual then
        local ok, sel = pcall(M.build)
        if ok and not sel.selection.isEmpty then
          M._latest = sel
        end
      elseif prev_in_visual then
        -- Just left visual mode without an explicit send: drop the stale
        -- selection so getLatestSelection doesn't hand out phantom data
        -- from a selection the user chose not to send (Esc = discard).
        M._latest = nil
      end
      prev_in_visual = in_visual
    end)
  )
end

--- Disable selection tracking.
function M.disable()
  if poll_timer then
    pcall(function()
      poll_timer:stop()
      poll_timer:close()
    end)
    poll_timer = nil
  end
  notify_fn = nil
end

--- Push a selection to all connected clients.
--- Sends selection_changed (text + range) for live content and
--- at_mentioned (filePath + range) for CLI's ide_opened_file attachment.
local function push_selection(sel)
  M._latest = sel
  notify_fn("selection_changed", sel)
  notify_fn("at_mentioned", {
    filePath = sel.filePath,
    lineStart = sel.selection.start.line,
    lineEnd = sel.selection["end"].line,
  })
end

--- Explicit send for lines (1-based, inclusive). Pushes selection_changed
--- with live buffer text rather than at_mentioned's filePath+range (which
--- only works if the buffer is saved — Claude re-reads from disk on that
--- path). Reading nvim_buf_get_lines instead of disk means unsaved edits
--- are sent as-is.
function M.send_at_mention(line1, line2)
  if not notify_fn then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  -- Prefer visual marks for column-accurate selection when available
  local mark_start = vim.fn.getpos("'<")
  local mark_end = vim.fn.getpos("'>")
  if mark_start[2] == line1 and mark_end[2] == line2 then
    local vmode = vim.fn.visualmode()
    if not vmode or vmode == "" then
      vmode = (mark_start[2] == mark_end[2]) and "v" or "V"
    end
    local ok, lines = pcall(vim.fn.getregion, mark_start, mark_end, { type = vmode })
    if ok and lines and #lines > 0 then
      push_selection({
        text = table.concat(lines, "\n"),
        filePath = file_path,
        fileUrl = "file://" .. file_path,
        selection = {
          start = { line = mark_start[2] - 1, character = mark_start[3] - 1 },
          ["end"] = { line = mark_end[2], character = mark_end[3] },
          isEmpty = false,
        },
      })
      return
    end
  end

  -- Fallback: send full lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  push_selection({
    text = table.concat(lines, "\n"),
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = line1 - 1, character = 0 },
      ["end"] = { line = line2, character = 0 },
      isEmpty = false,
    },
  })
end

--- Send an entire buffer's content (number or name) as a selection.
--- Handles any loaded buffer: scratch, terminal output, fugitive, oil, help, etc.
function M.send_buffer(bufnr_or_name)
  if not notify_fn then
    return
  end
  local bufnr = type(bufnr_or_name) == "number" and bufnr_or_name or vim.fn.bufnr(bufnr_or_name)
  if bufnr < 0 or not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.notify("clide: buffer " .. tostring(bufnr_or_name) .. " not loaded", vim.log.levels.WARN)
    return
  end
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- Remove trailing empty line trim from nvim_buf_get_lines
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end
  push_selection({
    text = table.concat(lines, "\n"),
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = 0, character = 0 },
      ["end"] = { line = #lines, character = 0 },
      isEmpty = false,
    },
  })
  vim.notify(
    "clide: sent buffer " .. tostring(bufnr) .. " (" .. #lines .. " lines)",
    vim.log.levels.INFO
  )
end

--- Get the most recent selection.
function M.latest()
  return M._latest
end

return M
