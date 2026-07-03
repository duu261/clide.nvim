local tools = require("clide.tools")

tools.register({
  name = "vim_grep",
  description = "Project-wide search using vimgrep with quickfix list",
  inputSchema = {
    type = "object",
    properties = {
      pattern = { type = "string", description = "Search pattern (Vim regex)" },
      filePattern = { type = "string", description = "File glob pattern (e.g. **/*.lua)" },
    },
    required = { "pattern" },
  },
  handler = function(args)
    local fp = args.filePattern or "**"
    vim.cmd("silent noautocmd grep! " .. args.pattern .. " " .. fp)
    local qf = vim.fn.getqflist({ items = true, size = true })
    local results = {}
    for _, item in ipairs(qf.items or {}) do
      table.insert(results, {
        file = vim.api.nvim_buf_get_name(item.bufnr),
        line = item.lnum,
        col = item.col,
        text = item.text,
      })
    end
    return tools.json_result(results)
  end,
})

return {}
