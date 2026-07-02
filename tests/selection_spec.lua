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
