describe("openFile", function()
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
    }) do
      package.loaded["clide.tools." .. mod] = nil
    end
    tools = require("clide.tools")
    tools.setup()
  end)

  it("opens a readable file and reports it", function()
    local result = call("openFile", { filePath = "tests/fixtures/sample.txt" })
    assert.matches("Opened file", result.content[1].text)
    assert.matches("sample%.txt$", vim.api.nvim_buf_get_name(0))
  end)

  it("fails for a missing file", function()
    local body = json_of(call("openFile", { filePath = "/nonexistent/nope.txt" }))
    assert.is_false(body.success)
  end)

  it("selects text between startText and endText", function()
    call("openFile", {
      filePath = "tests/fixtures/sample.txt",
      startText = "line one",
      endText = "line two",
    })
    -- selection was made and left in visual mode or marks set; cursor lands on match
    assert.equals(2, vim.api.nvim_win_get_cursor(0)[1])
    vim.cmd("normal! \27")
  end)

  it("returns structured info when makeFrontmost is false", function()
    local body = json_of(call("openFile", {
      filePath = "tests/fixtures/sample.txt",
      makeFrontmost = false,
    }))
    assert.is_true(body.success)
    assert.equals(3, body.lineCount)
  end)
end)

describe("getDiagnostics", function()
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
    }) do
      package.loaded["clide.tools." .. mod] = nil
    end
    tools = require("clide.tools")
    tools.setup()
  end)

  it("maps vim.diagnostic to protocol schema", function()
    vim.cmd.edit("tests/fixtures/sample.txt")
    local bufnr = vim.api.nvim_get_current_buf()
    local ns = vim.api.nvim_create_namespace("clide_test_diag")
    vim.diagnostic.set(ns, bufnr, {
      {
        lnum = 0,
        col = 0,
        end_lnum = 0,
        end_col = 4,
        severity = vim.diagnostic.severity.ERROR,
        message = "test error",
        source = "clide-test",
      },
    })
    local body = json_of(call("getDiagnostics"))
    local found
    for _, entry in ipairs(body) do
      for _, d in ipairs(entry.diagnostics) do
        if d.message == "test error" then
          found = d
        end
      end
    end
    assert.is_not_nil(found)
    assert.equals("Error", found.severity)
    assert.equals(0, found.range.start.line)
    vim.diagnostic.reset(ns, bufnr)
  end)

  it("returns a JSON array for a uri with no open buffer", function()
    local result = call("getDiagnostics", { uri = "file:///nonexistent/nowhere.txt" })
    -- protocol requires an array; empty table must encode as [] not {}
    assert.equals("[]", result.content[1].text)
  end)
end)
