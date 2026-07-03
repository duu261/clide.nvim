describe("openDiff classic", function()
  local tools

  local function call_diff(new_contents)
    local tmp = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "old line 1", "old line 2" }, tmp)
    local response
    tools.call("openDiff", {
      old_file_path = tmp,
      new_file_path = tmp,
      new_file_contents = new_contents,
      tab_name = "test-diff",
    }, function(r, e)
      response = { result = r, err = e }
    end)
    return tmp, function()
      return response
    end
  end

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
    -- Disable inline mode to test classic openDiff
    require("clide.config").setup({ review = { inline = false } })
    tools = require("clide.tools")
    tools.setup()
  end)

  it("defers the response until user decision", function()
    local tmp, response = call_diff("new line 1\nnew line 2\n")
    assert.is_nil(response()) -- blocking: no response yet
    local open_diff_module = require("clide.tools.open_diff")
    assert.is_not_nil(open_diff_module.active["test-diff"])
    open_diff_module.finish("test-diff", "reject")
    assert.equals("DIFF_REJECTED", response().result.content[1].text)
    assert.equals("test-diff", response().result.content[2].text)
    vim.fn.delete(tmp)
  end)

  it("accept responds FILE_SAVED with final content, does not write file", function()
    local tmp, response = call_diff("accepted content\n")
    local file_content_before = vim.fn.readfile(tmp)
    local open_diff_module = require("clide.tools.open_diff")
    open_diff_module.finish("test-diff", "accept")
    assert.equals("FILE_SAVED", response().result.content[1].text)
    assert.equals("accepted content\n", response().result.content[2].text)
    -- File should NOT be written by clide; it should still have original content
    assert.same(file_content_before, vim.fn.readfile(tmp))
    vim.fn.delete(tmp)
  end)

  it("closeAllDiffTabs rejects all pending diffs", function()
    local tmp, response = call_diff("x\n")
    local result
    tools.call("closeAllDiffTabs", {}, function(r)
      result = r
    end)
    assert.equals("CLOSED_1_DIFF_TABS", result.content[1].text)
    assert.equals("DIFF_REJECTED", response().result.content[1].text)
    assert.equals("test-diff", response().result.content[2].text)
    vim.fn.delete(tmp)
  end)

  it("closeAllDiffTabs sweeps pending inline reviews", function()
    require("clide.config").setup({ review = { inline = true } })
    local tmp = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "old" }, tmp)
    local response
    tools.call("openDiff", {
      old_file_path = tmp,
      new_file_path = tmp,
      new_file_contents = "new\n",
      tab_name = "inline-sweep",
    }, function(r, e)
      response = { result = r, err = e }
    end)
    local queue = require("clide.review.queue")
    local _, total = queue.counts()
    assert.equals(1, total)
    local result
    tools.call("closeAllDiffTabs", {}, function(r)
      result = r
    end)
    assert.equals("CLOSED_1_DIFF_TABS", result.content[1].text)
    assert.equals("DIFF_REJECTED", response.result.content[1].text)
    _, total = queue.counts()
    assert.equals(0, total)
    vim.fn.delete(tmp)
  end)

  it("close_tab sweeps a matching inline review", function()
    require("clide.config").setup({ review = { inline = true } })
    local tmp = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "old" }, tmp)
    local response
    tools.call("openDiff", {
      old_file_path = tmp,
      new_file_path = tmp,
      new_file_contents = "new\n",
      tab_name = "inline-close",
    }, function(r, e)
      response = { result = r, err = e }
    end)
    local result
    tools.call("close_tab", { tab_name = "inline-close" }, function(r)
      result = r
    end)
    assert.equals("TAB_CLOSED", result.content[1].text)
    assert.equals("DIFF_REJECTED", response.result.content[1].text)
    local _, total = require("clide.review.queue").counts()
    assert.equals(0, total)
    vim.fn.delete(tmp)
  end)

  it("double-finish does not double-respond", function()
    local tmp, response = call_diff("y\n")
    local open_diff_module = require("clide.tools.open_diff")
    open_diff_module.finish("test-diff", "reject")
    assert.has_no.errors(function()
      open_diff_module.finish("test-diff", "accept")
    end)
    assert.equals("DIFF_REJECTED", response().result.content[1].text)
    vim.fn.delete(tmp)
  end)

  it("appends linematch:60 to diffopt when opening diff", function()
    local tmp, _ = call_diff("new content\n")

    -- Check that linematch:60 is in diffopt
    local diffopt_str = vim.o.diffopt
    assert.match("linematch:60", diffopt_str)

    -- Restore for cleanup
    vim.fn.delete(tmp)
  end)

  it("guards against duplicate linematch:60 in diffopt", function()
    local tmp, _ = call_diff("first diff\n")
    local open_diff_module = require("clide.tools.open_diff")
    open_diff_module.finish("test-diff", "reject")
    vim.fn.delete(tmp)

    -- Open a second diff
    local tmp2, _ = call_diff("second diff\n")
    local diffopt_str = vim.o.diffopt

    -- Count occurrences of linematch:60
    local count = 0
    for _ in diffopt_str:gmatch("linematch:60") do
      count = count + 1
    end
    assert.equals(1, count)

    open_diff_module.finish("test-diff", "reject")
    vim.fn.delete(tmp2)
  end)

  it("uses vertical split layout for diff windows", function()
    local tmp, _ = call_diff("vertical split test\n")

    -- Check window layout is vertical (should be 'row' type in winlayout)
    local layout = vim.fn.winlayout()
    -- layout[1] is the type, for vertical splits (side-by-side) it should be 'row'
    assert.equals("row", layout[1])

    local open_diff_module = require("clide.tools.open_diff")
    open_diff_module.finish("test-diff", "reject")
    vim.fn.delete(tmp)
  end)

  it("sets winhighlight on diff windows", function()
    local tmp, _ = call_diff("winhighlight test\n")

    -- Get current window (scratch buffer)
    local scratch_winid = vim.api.nvim_get_current_win()

    -- Check that winhighlight is set
    local winhighlight = vim.wo[scratch_winid].winhighlight
    assert.is_not_nil(winhighlight)
    assert.is_not_equal("", winhighlight)

    local open_diff_module = require("clide.tools.open_diff")
    open_diff_module.finish("test-diff", "reject")
    vim.fn.delete(tmp)
  end)
end)
