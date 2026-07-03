local engine = require("clide.review.engine")
local queue = require("clide.review.queue")
local tools = require("clide.tools")

local function make_review(lines, new_contents, name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "-" .. name .. ".txt")
  vim.api.nvim_set_current_buf(buf)
  return engine.open({
    new_file_path = vim.api.nvim_buf_get_name(buf),
    new_file_contents = new_contents,
    tab_name = name,
  }, function() end)
end

describe("review queue", function()
  it("counts pending hunks across reviews", function()
    local r1 = make_review({ "a" }, "A\n", "q1")
    local r2 = make_review({ "x", "y" }, "X\nY\n", "q2")
    local resolved, total = queue.counts()
    assert.is_true(total >= 2)
    assert.equals("review " .. resolved .. "/" .. total, queue.statusline())
    engine.resolve_all(r1, "reject")
    engine.resolve_all(r2, "reject")
  end)

  it("statusline is empty with no reviews", function()
    assert.equals("", queue.statusline())
  end)

  it("jump moves cursor to next pending hunk", function()
    local r = make_review({ "aaa", "bbb", "ccc", "ddd" }, "aaa\nBBB\nccc\nDDD\n", "q3")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    queue.jump(1)
    assert.equals(2, vim.api.nvim_win_get_cursor(0)[1])
    queue.jump(1)
    assert.equals(4, vim.api.nvim_win_get_cursor(0)[1])
    engine.resolve_all(r, "reject")
  end)
end)

describe("openDiff inline routing", function()
  before_each(function()
    -- Clear all tool modules and the tools registry
    package.loaded["clide.tools"] = nil
    package.loaded["clide.selection"] = nil
    for _, mod in ipairs({
      "open_file",
      "open_diff",
      "selection_tools",
      "editors",
      "workspace",
      "diagnostics",
      "documents",
      "tabs",
      "execute_code",
    }) do
      package.loaded["clide.tools." .. mod] = nil
    end
    tools = require("clide.tools")
    tools.setup()
  end)

  it("routes openDiff to the review engine when inline enabled", function()
    require("clide.config").setup({ review = { inline = true } })
    local tmp = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "old" }, tmp)
    vim.cmd.edit(tmp)
    local response
    tools.call("openDiff", {
      old_file_path = tmp,
      new_file_path = tmp,
      new_file_contents = "new\n",
      tab_name = "route-test",
    }, function(r)
      response = r
    end)
    assert.is_nil(response) -- deferred, inline review active
    assert.equals(0, #vim.api.nvim_list_tabpages() - 1) -- no diff tab opened
    local review = queue.find("route-test")
    assert.is_not_nil(review)
    engine.resolve_all(review, "reject")
    assert.equals("DIFF_REJECTED", response.content[1].text)
    vim.fn.delete(tmp)
  end)
end)
