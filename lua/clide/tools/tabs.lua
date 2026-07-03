local tools = require("clide.tools")

tools.register({
  name = "close_tab",
  description = "Close a tab by name",
  inputSchema = {
    type = "object",
    properties = { tab_name = { type = "string" } },
    required = { "tab_name" },
  },
  handler = function(args)
    local review = require("clide.review.queue").find(args.tab_name)
    if review then
      require("clide.review.engine").resolve_all(review, "reject")
      return tools.text_result("TAB_CLOSED")
    end
    local open_diff = require("clide.tools.open_diff")
    if open_diff.active[args.tab_name] then
      open_diff.finish(args.tab_name, "reject")
      return tools.text_result("TAB_CLOSED")
    end
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if vim.fn.fnamemodify(name, ":t") == args.tab_name then
        vim.api.nvim_buf_delete(bufnr, { force = false })
        return tools.text_result("TAB_CLOSED")
      end
    end
    return tools.json_result({
      success = false,
      message = "Tab not found: " .. args.tab_name,
    })
  end,
})

return {}
