local tools = require("clide.tools")

tools.register({
  name = "executeCode",
  description = "Execute code in a Jupyter kernel (not supported in Neovim)",
  inputSchema = {
    type = "object",
    properties = { code = { type = "string" } },
    required = { "code" },
  },
  handler = function()
    return tools.json_result({
      success = false,
      message = "executeCode is not supported in Neovim",
    })
  end,
})

return {}
