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
    vim.fn.delete(tmp)
  end)

  it("accept writes new contents and responds FILE_SAVED", function()
    local tmp, response = call_diff("accepted content\n")
    local open_diff_module = require("clide.tools.open_diff")
    open_diff_module.finish("test-diff", "accept")
    assert.equals("FILE_SAVED", response().result.content[1].text)
    assert.equals("accepted content", vim.fn.readfile(tmp)[1])
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
end)
