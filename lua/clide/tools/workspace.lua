local tools = require("clide.tools")

tools.register({
  name = "getWorkspaceFolders",
  description = "Get the workspace folders currently open",
  inputSchema = { type = "object", properties = vim.empty_dict() },
  handler = function()
    local cwd = vim.fn.getcwd()
    return tools.json_result({
      success = true,
      folders = {
        {
          name = vim.fs.basename(cwd),
          uri = "file://" .. cwd,
          path = cwd,
        },
      },
      rootPath = cwd,
    })
  end,
})

return {}
