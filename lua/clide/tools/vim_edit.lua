local tools = require("clide.tools")

tools.register({
  name = "vim_edit",
  description = "Edit a file: insert, replace, or delete lines. Applies immediately and saves.",
  inputSchema = {
    type = "object",
    properties = {
-- ponytail: one tool, three ops
      filePath = { type = "string", description = "Path to the file" },
      action = {
        type = "string",
        enum = { "insert", "replace", "delete" },
        description = "insert: add text at line. replace: overwrite range. delete: remove range.",
      },
      line = { type = "integer", description = "1-based start line" },
      endLine = { type = "integer", description = "1-based end line (replace/delete only)" },
      text = { type = "string", description = "Text content for insert/replace" },
    },
    required = { "filePath", "action", "line" },
  },
  handler = function(args)
    if args.action ~= "insert" and vim.fn.filereadable(args.filePath) == 0 then
      return tools.json_result({
        success = false,
        message = "File not found: " .. args.filePath,
      })
    end

    local bufnr = vim.fn.bufadd(args.filePath)
    vim.fn.bufload(bufnr)

    local line0 = math.max(0, args.line - 1)

    if args.action == "insert" then
      if not args.text or args.text == "" then
        return tools.json_result({ success = false, message = "text required for insert" })
      end
      local new_lines = vim.split(args.text, "\n")
      vim.api.nvim_buf_set_lines(bufnr, line0, line0, false, new_lines)

    elseif args.action == "replace" then
      local end0 = (args.endLine and args.endLine - 1) or line0
      local new_lines = (args.text and args.text ~= "") and vim.split(args.text, "\n") or {}
      vim.api.nvim_buf_set_lines(bufnr, line0, end0 + 1, false, new_lines)

    elseif args.action == "delete" then
      local end0 = (args.endLine and args.endLine - 1) or line0
      vim.api.nvim_buf_set_lines(bufnr, line0, end0 + 1, false, {})
    end

    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("write")
    end)

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    return tools.json_result({
      success = true,
      lineCount = line_count,
    })
  end,
})

return {}
