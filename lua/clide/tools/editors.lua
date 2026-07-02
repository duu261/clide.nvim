local tools = require("clide.tools")

tools.register({
  name = "getOpenEditors",
  description = "Get the list of currently open editor tabs",
  inputSchema = { type = "object", properties = vim.empty_dict() },
  handler = function()
    local current = vim.api.nvim_get_current_buf()
    local tabs = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(bufnr)
      if vim.bo[bufnr].buflisted and name ~= "" then
        table.insert(tabs, {
          uri = "file://" .. name,
          isActive = bufnr == current,
          label = vim.fn.fnamemodify(name, ":t"),
          languageId = vim.bo[bufnr].filetype,
          isDirty = vim.bo[bufnr].modified,
        })
      end
    end
    return tools.json_result({ tabs = tabs })
  end,
})

return {}
