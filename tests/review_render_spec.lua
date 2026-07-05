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
    local resolve_called = nil

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
      resolve_at_cursor = function(r, verdict)
        resolve_called = { fn = "resolve_at_cursor", verdict = verdict }
      end,
      resolve_all = function(r, verdict)
        resolve_called = { fn = "resolve_all", verdict = verdict }
      end,
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
end)
