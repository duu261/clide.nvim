local selection = require("clide.selection")

describe("selection", function()
  before_each(function()
    -- Clean up any existing test buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("selection_test") then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    vim.cmd.enew()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha beta", "gamma delta" })
    -- Use unique buffer name with timestamp
    local timestamp = vim.fn.reltimestr(vim.fn.reltime()):gsub("[^0-9]", ""):sub(1, 8)
    vim.api.nvim_buf_set_name(0, "/tmp/selection_test_" .. timestamp .. ".txt")
  end)

  it("builds an empty selection at the cursor in normal mode", function()
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    local sel = selection.build()
    assert.is_true(sel.selection.isEmpty)
    assert.equals("", sel.text)
    assert.equals(1, sel.selection.start.line) -- 0-based
    assert.equals(3, sel.selection.start.character)
    assert.matches("selection_test_[0-9]+%.txt$", sel.filePath)
  end)

  it("builds a charwise visual selection with 0-based positions", function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v4l") -- select "alpha"
    local sel = selection.build()
    assert.equals("alpha", sel.text)
    assert.is_false(sel.selection.isEmpty)
    assert.equals(0, sel.selection.start.line)
    assert.equals(0, sel.selection.start.character)
    vim.cmd("normal! \27") -- <Esc>
  end)

  it("builds a linewise selection", function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! Vj")
    local sel = selection.build()
    assert.matches("alpha beta", sel.text)
    assert.matches("gamma delta", sel.text)
    vim.cmd("normal! \27")
  end)

  it("emits selection_changed after leaving single-line visual mode", function()
    local captured = {}
    selection.enable(function(method, params)
      table.insert(captured, { method = method, params = params })
    end)
    -- Enter linewise visual on line 1, don't move, then leave
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! V") -- enter linewise visual mode on line 1
    vim.cmd("normal! \27") -- leave visual mode
    -- Wait for debounce timer (100ms + buffer)
    vim.wait(500, function()
      return #captured >= 1
    end)
    selection.disable()
    assert.equals(1, #captured, "exactly one notification fired")
    local notif = captured[1]
    assert.equals("selection_changed", notif.method)
    assert.is_false(notif.params.selection.isEmpty)
    assert.equals(0, notif.params.selection.start.line) -- line 1 → 0-based
    assert.equals(1, notif.params.selection["end"].line) -- single line, end exclusive
    assert.matches("alpha beta", notif.params.text)
  end)

  it("emits selection_changed after leaving single-line charwise visual mode", function()
    local captured = {}
    selection.enable(function(method, params)
      table.insert(captured, { method = method, params = params })
    end)
    -- Enter charwise visual on line 1, select a few chars, don't move lines, then leave
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v4l") -- select "alpha"
    vim.cmd("normal! \27") -- leave visual mode
    vim.wait(500, function()
      return #captured >= 1
    end)
    selection.disable()
    -- May have received one notification from CursorMoved in visual mode + one from leaving;
    -- at least one should have the correct selection content.
    local has_alpha = false
    for _, n in ipairs(captured) do
      if n.params.text == "alpha" and not n.params.selection.isEmpty then
        has_alpha = true
        break
      end
    end
    assert.is_true(has_alpha, "at least one notification contains 'alpha' selection")
  end)

  it("does not send duplicate notifications for the same selection", function()
    local captured = {}
    selection.enable(function(method, params)
      table.insert(captured, { method = method, params = params })
    end)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    -- Enter visual, stay, leave — all without moving cursor
    vim.cmd("normal! V\27")
    vim.wait(500, function()
      return #captured >= 1
    end)
    -- Trigger another ModeChanged by entering/leaving insert mode
    -- to ensure the previous selection isn't re-sent
    local count_before = #captured
    vim.cmd("normal! i\27") -- enter then leave insert mode
    vim.wait(500, function()
      return #captured > count_before
    end)
    selection.disable()
    -- After insert-mode toggle, we should not have received another
    -- copy of the same visual selection.
    local visual_notifs = 0
    for _, n in ipairs(captured) do
      if n.method == "selection_changed" and not n.params.selection.isEmpty then
        visual_notifs = visual_notifs + 1
      end
    end
    assert.equals(1, visual_notifs, "exactly one non-empty selection_changed")
  end)

  it("send_at_mention emits 0-based line range", function()
    local captured
    selection.enable(function(method, params)
      captured = { method = method, params = params }
    end)
    selection.send_at_mention(1, 2)
    assert.equals("at_mentioned", captured.method)
    assert.equals(0, captured.params.lineStart)
    assert.equals(1, captured.params.lineEnd)
    selection.disable()
  end)
end)
