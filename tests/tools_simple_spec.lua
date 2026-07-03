describe("simple tools", function()
  local tools

  local function call(name, args)
    local result, err
    tools.call(name, args or {}, function(r, e)
      result, err = r, e
    end)
    return result, err
  end

  local function json_of(result)
    return vim.json.decode(result.content[1].text)
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
      "vim_edit",
      "lua_eval",
      "search",
      "grep",
      "diagnose",
    }) do
      package.loaded["clide.tools." .. mod] = nil
    end
    tools = require("clide.tools")
    tools.setup()
    -- Verify tools are registered
    local tool_list = tools.list()
    assert.is_true(#tool_list > 0, "No tools registered after setup()")
  end)

  it("getWorkspaceFolders returns cwd", function()
    local body = json_of(call("getWorkspaceFolders"))
    assert.is_true(body.success)
    assert.equals(vim.fn.getcwd(), body.folders[1].path)
    assert.matches("^file://", body.folders[1].uri)
  end)

  it("getOpenEditors lists a loaded buffer", function()
    vim.cmd.edit("tests/fixtures/sample.txt")
    local body = json_of(call("getOpenEditors"))
    local found = false
    for _, tab in ipairs(body.tabs) do
      if tab.label == "sample.txt" then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("checkDocumentDirty reports a modified buffer", function()
    vim.cmd.edit("tests/fixtures/sample.txt")
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { "dirty" })
    local body = json_of(call("checkDocumentDirty", { filePath = vim.fn.expand("%:p") }))
    assert.is_true(body.success)
    assert.is_true(body.isDirty)
    vim.cmd("edit!") -- discard
  end)

  it("checkDocumentDirty fails for unopened path", function()
    local body = json_of(call("checkDocumentDirty", { filePath = "/nonexistent/x.txt" }))
    assert.is_false(body.success)
    assert.matches("Document not open", body.message)
  end)

  it("saveDocument writes the buffer", function()
    local tmp = vim.fn.tempname() .. ".txt"
    vim.cmd.edit(tmp)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "saved" })
    local body = json_of(call("saveDocument", { filePath = tmp }))
    assert.is_true(body.success)
    assert.equals("saved", vim.fn.readfile(tmp)[1])
    vim.fn.delete(tmp)
  end)

  it("close_tab deletes the buffer by label", function()
    vim.cmd.edit("tests/fixtures/sample.txt")
    local result = call("close_tab", { tab_name = "sample.txt" })
    assert.equals("TAB_CLOSED", result.content[1].text)
  end)

  it("executeCode evaluates Lua in Neovim", function()
    local result = call("executeCode", { code = "1+1" })
    assert.equals("2", result.content[1].text)
  end)

  it("executeCode returns errors for bad syntax", function()
    local result = call("executeCode", { code = "1++1" })
    local body = vim.json.decode(result.content[1].text)
    assert.is_false(body.success)
    assert.is_not_nil(body.error)
  end)

  it("vim_grep does not execute shell metacharacters", function()
    local sentinel = vim.fn.tempname()
    -- With the old external :grep, these would reach a shell and create the file.
    -- Internal :vimgrep must treat them as literal pattern/glob text.
    call("vim_grep", { pattern = "x", filePattern = "z; touch " .. sentinel })
    call("vim_grep", { pattern = "$(touch " .. sentinel .. ")", filePattern = "**" })
    assert.equals(0, vim.fn.filereadable(sentinel), "shell metacharacters were executed")
  end)

  it("vim_search returns error for invalid regex instead of throwing", function()
    local result = call("vim_search", { pattern = "\\(" })
    local body = vim.json.decode(result.content[1].text)
    assert.is_not_nil(body.error)
  end)
end)
