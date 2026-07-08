--- Quickfix bridge: bidirectional flow between nvim quickfix and Claude.
--- nvim → Claude: send quickfix contents as context.
--- Claude → nvim: Claude's edits land in quickfix for native :cn/:cp navigation.
--- VS Code has no quickfix equivalent — this is nvim-native advantage.
local M = {}

--- Edit log: { path, lnum, text } entries from Claude's tool calls.
--- Lazy-init on first track; survives across sessions within nvim lifetime.
M._edits = nil

--- Track a file edit by Claude. path = absolute, lnum = nil for whole-file.
function M.track_edit(path, lnum, text)
  if not M._edits then
    M._edits = {}
  end
  table.insert(M._edits, {
    filename = path,
    lnum = lnum or 1,
    col = 1,
    text = text or "Claude edited " .. vim.fn.fnamemodify(path, ":t"),
  })
end

--- Populate quickfix list from tracked Claude edits. Opens :cwindow.
function M.edits_to_qf()
  if not M._edits or #M._edits == 0 then
    vim.notify("clide: no edits tracked yet", vim.log.levels.INFO)
    return
  end
  vim.fn.setqflist({}, " ", { title = "Claude Edits", items = M._edits })
  vim.cmd.copen()
  vim.notify("clide: " .. #M._edits .. " edits in quickfix", vim.log.levels.INFO)
end

--- Read current quickfix list and format as context text for Claude.
--- Returns lines of text ready to send.
function M.format_qf()
  local qf = vim.fn.getqflist({ items = true, title = true })
  if not qf.items or #qf.items == 0 then
    return nil, "quickfix list is empty"
  end
  local lines = {}
  local title = qf.title and #qf.title > 0 and qf.title or "quickfix"
  table.insert(lines, title .. " (" .. #qf.items .. " entries):")
  table.insert(lines, "")
  for i, item in ipairs(qf.items) do
    local fname = vim.fn.fnamemodify(item.filename, ":.")
    local lnum = item.lnum or 1
    local col = item.col or 1
    local text = item.text or ""
    table.insert(lines, string.format("%d. %s:%d:%d: %s", i, fname, lnum, col, text))
  end
  return lines
end

--- Send current quickfix contents to Claude as selection_changed.
function M.send_qf()
  local clide = require("clide")
  if not clide.state.server or not clide.state.server.sessions then
    vim.notify("clide: server not running", vim.log.levels.WARN)
    return
  end

  local lines, err = M.format_qf()
  if not lines then
    vim.notify("clide: " .. err, vim.log.levels.WARN)
    return
  end

  local text = table.concat(lines, "\n")
  -- ponytail: single notify to first connected client — quickfix lists are
  -- small (<500 entries). Fan-out if multi-client throughput matters.
  for _, s in pairs(clide.state.server.sessions) do
    if s.rpc then
      pcall(s.rpc.notify, s.rpc, "selection_changed", {
        text = text,
        filePath = "[quickfix]",
        selection = {
          start = { line = 0, character = 0 },
          ["end"] = { line = #lines, character = 0 },
          isEmpty = false,
        },
      })
      break
    end
  end

  local count = #lines - 2 -- subtract header lines
  vim.notify("clide: sent quickfix (" .. count .. " entries) to Claude", vim.log.levels.INFO)
  return true
end

--- Populate quickfix from current buffer diagnostics.
--- Uses vim.diagnostic.get() — the same source Claude sees via getDiagnostics.
function M.diag_to_qf()
  local diags = vim.diagnostic.get()
  if #diags == 0 then
    vim.notify("clide: no diagnostics in current buffer", vim.log.levels.INFO)
    return
  end
  local items = {}
  for _, d in ipairs(diags) do
    local severity = ({ "Error", "Warning", "Info", "Hint" })[d.severity] or "Info"
    table.insert(items, {
      filename = vim.api.nvim_buf_get_name(d.bufnr),
      lnum = d.lnum + 1,
      col = d.col + 1,
      text = "[" .. severity .. "] " .. (d.message or ""),
    })
  end
  vim.fn.setqflist({}, " ", { title = "Clide Diagnostics", items = items })
  vim.cmd.copen()
  vim.notify("clide: " .. #items .. " diagnostics in quickfix", vim.log.levels.INFO)
end

return M
