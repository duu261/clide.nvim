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
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local sel = {
    text = table.concat(lines, "\n"),
    filePath = file_path,
    fileUrl = "file://" .. file_path,
    selection = {
      start = { line = line1 - 1, character = 0 },
      ["end"] = { line = line2, character = 0 },
      isEmpty = false,
    },
  }
  M._latest = sel
  notify_fn("selection_changed", sel)
end

--- Get the most recent selection.
function M.latest()
  return M._latest
end

return M
