local render = require("clide.review.render")

describe("review render", function()
  local function make_buf(lines)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".txt")
    return buf
  end

  it("sets keymaps on buffer via callbacks without requiring engine", function()
    local buf = make_buf({ "line" })
    vim.api.nvim_set_current_buf(buf)

    local review = {
      bufnr = buf,
      hunks = {
        { start_a = 1, count_a = 1, start_b = 1, count_b = 1, state = "pending" },
      },
      new_lines = { "line" },
      resolved = 0,
      accepted = 0,
      done = false,
      tab_name = "test",
    }

    render.attach(review, {
      resolve_at_cursor = function(_, _) end,
      resolve_all = function(_, _) end,
    })

    -- Keymaps are registered on the buffer
    local maps = vim.api.nvim_buf_get_keymap(buf, "n")
    local found = {}
    for _, m in ipairs(maps) do
      if m.desc and m.desc:match("^clide:") then
        found[m.desc] = true
      end
    end
    assert.is_true(found["clide: accept hunk"], "accept keymap set")
    assert.is_true(found["clide: reject hunk"], "reject keymap set")
    assert.is_true(found["clide: accept all hunks"], "accept_all keymap set")
    assert.is_true(found["clide: reject all hunks"], "reject_all keymap set")
  end)

  it("delegates to callbacks when keymaps fire", function()
    local buf = make_buf({ "old line" })
    vim.api.nvim_set_current_buf(buf)
    local calls = {}

    local review = {
      bufnr = buf,
      hunks = {
        { start_a = 1, count_a = 1, start_b = 1, count_b = 1, state = "pending" },
      },
      new_lines = { "new" },
      resolved = 0,
      accepted = 0,
      done = false,
      tab_name = "delegate",
    }

    render.set_keymaps(review, {
      resolve_at_cursor = function(r, v)
        table.insert(calls, { fn = "cursor", verdict = v })
      end,
      resolve_all = function(r, v)
        table.insert(calls, { fn = "all", verdict = v })
      end,
    })

    -- First test: resolve_all fires. Use the keymap key directly.
    -- Default accept_all is <Leader>mA. In headless tests <Leader> is \ by default.
    local keys = require("clide.config").get().review.keymaps
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(keys.accept_all, true, false, true),
      "x",
      false
    )
    assert.equals("all", calls[1].fn)
    assert.equals("accept", calls[1].verdict)
  end)

  it("detach removes keymaps and extmarks", function()
    local buf = make_buf({ "old line" })
    vim.api.nvim_set_current_buf(buf)
    local review = {
      bufnr = buf,
      hunks = {
        { start_a = 1, count_a = 1, start_b = 1, count_b = 1, state = "pending" },
      },
      new_lines = { "new line" },
      resolved = 0,
      accepted = 0,
      done = false,
      tab_name = "test-detach",
    }
    render.attach(review, {
      resolve_at_cursor = function() end,
      resolve_all = function() end,
    })
    render.detach(review)

    -- Keymaps removed
    local maps = vim.api.nvim_buf_get_keymap(buf, "n")
    for _, m in ipairs(maps) do
      assert.is_not_true(
        m.desc and m.desc:match("^clide:"),
        "clide keymap should be removed: " .. (m.desc or "")
      )
    end

    -- Extmark cleared
    assert.is_nil(review.hunks[1].extmark)
  end)

  it("hunk at first line uses virt_lines_above on row 0", function()
    local buf = make_buf({ "first", "second" })
    vim.api.nvim_set_current_buf(buf)
    local review = {
      bufnr = buf,
      hunks = {
        { start_a = 1, count_a = 1, start_b = 1, count_b = 1, state = "pending" },
      },
      new_lines = { "FIRST" },
      resolved = 0,
      accepted = 0,
      done = false,
      tab_name = "top-hunk",
    }
    render.attach(review)
    local ns = vim.api.nvim_get_namespaces()["clide_review"]
    assert.is_not_nil(ns, "clide_review namespace exists")
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    -- Find the hunk extmark (not the hint line)
    local hunk_mark = nil
    for _, mark in ipairs(extmarks) do
      local det = mark[4]
      if det and det.sign_text then
        hunk_mark = mark
        break
      end
    end
    assert.is_not_nil(hunk_mark, "hunk extmark found")
    local det = hunk_mark[4]
    assert.equals(0, hunk_mark[2], "extmark at row 0")
    assert.is_true(det.virt_lines_above, "virt_lines_above is true for row 0 hunk")
    assert.equals(1, #det.virt_lines, "one virtual line for new content")
    render.detach(review)
  end)

  it("hunk at last line places valid extmark with virt_lines below", function()
    local buf = make_buf({ "line1", "line2", "line3" })
    vim.api.nvim_set_current_buf(buf)
    local review = {
      bufnr = buf,
      hunks = {
        { start_a = 3, count_a = 1, start_b = 3, count_b = 1, state = "pending" },
      },
      new_lines = { "line1", "line2", "LINE3" },
      resolved = 0,
      accepted = 0,
      done = false,
      tab_name = "bottom-hunk",
    }
    render.attach(review)
    local ns = vim.api.nvim_get_namespaces()["clide_review"]
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local hunk_mark = nil
    for _, mark in ipairs(extmarks) do
      local det = mark[4]
      if det and det.sign_text then
        hunk_mark = mark
        break
      end
    end
    assert.is_not_nil(hunk_mark, "hunk extmark found at last line")
    local det = hunk_mark[4]
    -- row should be the line before the change (start_a - 1 = 2 → 0-based row 2)
    assert.equals(2, hunk_mark[2], "extmark row is on the line before the last")
    assert.is_false(det.virt_lines_above, "virt_lines_above is false for non-top hunk")
    assert.equals(1, #det.virt_lines, "one virtual line for new content")
    -- The extmark end_row should cover the last line
    assert.is_not_nil(det.end_row, "end_row is set for deletion HL")
    render.detach(review)
  end)

  it("pure insertion at end of file places valid extmark", function()
    local buf = make_buf({ "alpha", "beta" })
    vim.api.nvim_set_current_buf(buf)
    local review = {
      bufnr = buf,
      hunks = {
        { start_a = 2, count_a = 0, start_b = 3, count_b = 1, state = "pending" },
      },
      new_lines = { "alpha", "beta", "gamma" },
      resolved = 0,
      accepted = 0,
      done = false,
      tab_name = "end-insert",
    }
    render.attach(review)
    local ns = vim.api.nvim_get_namespaces()["clide_review"]
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local hunk_mark = nil
    for _, mark in ipairs(extmarks) do
      local det = mark[4]
      if det and det.sign_text then
        hunk_mark = mark
        break
      end
    end
    assert.is_not_nil(hunk_mark, "hunk extmark found for end insertion")
    local det = hunk_mark[4]
    -- start_a=2 (after line 2) → row = 1 (last real line, 0-based)
    assert.equals(1, hunk_mark[2], "extmark on last real row")
    assert.is_false(det.virt_lines_above, "virt_lines below for end insertion")
    -- No end_row for pure insertions (count_a == 0)
    assert.is_nil(det.end_row, "no end_row for pure insertion")
    render.detach(review)
  end)
end)
