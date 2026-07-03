local tools = require("clide.tools")

tools.register({
  name = "vim_search",
  description = "Search within current buffer with regex support",
  inputSchema = {
    type = "object",
    properties = {
      pattern = { type = "string", description = "Search pattern (Vim regex)" },
      ignoreCase = { type = "boolean", description = "Case insensitive" },
      wholeWord = { type = "boolean", description = "Match whole word only" },
    },
    required = { "pattern" },
  },
  handler = function(args)
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local pattern = args.pattern
    if args.ignoreCase then
      pattern = "\\c" .. pattern
    end
    if args.wholeWord then
      pattern = "\\<" .. pattern .. "\\>"
    end
    local ok, re = pcall(vim.regex, pattern)
    if not ok or not re then
      return tools.json_result({ error = "invalid regex: " .. pattern })
    end

    local results = {}
    for i, line in ipairs(lines) do
      local s = re:match_str(line)
      if s then
        table.insert(results, { line = i, col = s + 1, text = line })
      end
    end
    return tools.json_result(results)
  end,
})

return {}
