local engine = require("clide.review.engine")

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".txt")
  vim.api.nvim_set_current_buf(buf)
  return buf
end

describe("review engine", function()
  it("computes hunks from old/new line lists", function()
    local hunks = engine.compute_hunks({ "a", "b", "c" }, { "a", "B", "c", "d" })
    assert.equals(2, #hunks) -- change b->B, add d
    assert.equals("pending", hunks[1].state)
  end)

  it("responds FILE_SAVED immediately when contents identical", function()
    make_buf({ "same" })
    local response
    engine.open({
      new_file_path = vim.api.nvim_buf_get_name(0),
      new_file_contents = "same\n",
      tab_name = "t0",
    }, function(r)
      response = r
    end)
    assert.equals("FILE_SAVED", response.content[1].text)
    assert.equals("same\n", response.content[2].text)
  end)

  it("accepting all hunks rewrites buffer and responds FILE_SAVED", function()
    local buf = make_buf({ "keep", "old", "keep2" })
    local response
    local review = engine.open({
      new_file_path = vim.api.nvim_buf_get_name(buf),
      new_file_contents = "keep\nnew\nkeep2\nadded\n",
      tab_name = "t1",
    }, function(r)
      response = r
    end)
    assert.is_nil(response) -- deferred
    engine.resolve_all(review, "accept")
    assert.equals("FILE_SAVED", response.content[1].text)
    assert.equals("keep\nnew\nkeep2\nadded\n", response.content[2].text)
    assert.same({ "keep", "new", "keep2", "added" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("rejecting all hunks leaves buffer untouched and responds DIFF_REJECTED", function()
    local buf = make_buf({ "one", "two" })
    local response
    local review = engine.open({
      new_file_path = vim.api.nvim_buf_get_name(buf),
      new_file_contents = "changed\ntwo\n",
      tab_name = "t2",
    }, function(r)
      response = r
    end)
    engine.resolve_all(review, "reject")
    assert.equals("DIFF_REJECTED", response.content[1].text)
    assert.equals("t2", response.content[2].text)
    assert.same({ "one", "two" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("partial accept applies only accepted hunks and responds FILE_SAVED", function()
    local buf = make_buf({ "aaa", "bbb", "ccc" })
    local response
    local review = engine.open({
      new_file_path = vim.api.nvim_buf_get_name(buf),
      new_file_contents = "AAA\nbbb\nCCC\n",
      tab_name = "t3",
    }, function(r)
      response = r
    end)
    assert.equals(2, #review.hunks)
    engine.resolve_hunk(review, review.hunks[1], "accept")
    engine.resolve_hunk(review, review.hunks[2], "reject")
    assert.equals("FILE_SAVED", response.content[1].text)
    assert.equals("AAA\nbbb\nccc\n", response.content[2].text)
    assert.same({ "AAA", "bbb", "ccc" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("accepting all hunks leaves buffer unmodified (no W12 on CLI write)", function()
    local buf = make_buf({ "keep", "old" })
    vim.bo[buf].modified = false -- simulate freshly loaded buffer
    local review = engine.open({
      new_file_path = vim.api.nvim_buf_get_name(buf),
      new_file_contents = "keep\nnew\n",
      tab_name = "t-w12",
    }, function() end)
    engine.resolve_all(review, "accept")
    assert.is_false(vim.bo[buf].modified)
  end)

  it("handles pure insertion at top of file", function()
    local buf = make_buf({ "body" })
    local review = engine.open({
      new_file_path = vim.api.nvim_buf_get_name(buf),
      new_file_contents = "header\nbody\n",
      tab_name = "t4",
    }, function() end)
    engine.resolve_all(review, "accept")
    assert.same({ "header", "body" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)
end)
