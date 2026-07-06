local tools = require("clide.tools")
local follow = require("clide.follow")

local pending_follow_path
local follow_scheduled = false

local function queue_follow(path)
  pending_follow_path = path
  if follow_scheduled then
    return
  end
  follow_scheduled = true
  vim.schedule(function()
    follow_scheduled = false
    local path_to_follow = pending_follow_path
    pending_follow_path = nil
    if path_to_follow then
      follow.handle(path_to_follow)
    end
  end)
end

local function find_buf(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end
  return bufnr
end

tools.register({
  name = "checkDocumentDirty",
  description = "Check if a document has unsaved changes",
  inputSchema = {
    type = "object",
    properties = { filePath = { type = "string" } },
    required = { "filePath" },
  },
  handler = function(args)
    local bufnr = find_buf(args.filePath)
    if not bufnr then
      return tools.json_result({
        success = false,
        message = "Document not open: " .. args.filePath,
      })
    end
    return tools.json_result({
      success = true,
      filePath = args.filePath,
      isDirty = vim.bo[bufnr].modified,
      isUntitled = false,
    })
  end,
})

tools.register({
  name = "saveDocument",
  description = "Save a document with unsaved changes",
  inputSchema = {
    type = "object",
    properties = { filePath = { type = "string" } },
    required = { "filePath" },
  },
  handler = function(args)
    local bufnr = find_buf(args.filePath)
    if not bufnr then
      return tools.json_result({
        success = false,
        message = "Document not open: " .. args.filePath,
      })
    end
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write")
    end)
    queue_follow(args.filePath)
    return tools.json_result({
      success = true,
      filePath = args.filePath,
      saved = true,
      message = "Document saved successfully",
    })
  end,
})

return {}
