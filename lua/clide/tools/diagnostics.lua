local tools = require("clide.tools")

local severity_map = { "Error", "Warning", "Information", "Hint" }

tools.register({
  name = "getDiagnostics",
  description = "Get language diagnostics from the editor",
  inputSchema = {
    type = "object",
    properties = { uri = { type = "string" } },
  },
  handler = function(args)
    local opts = {}
    if args.uri and args.uri ~= "" then
      local path = args.uri:gsub("^file://", "")
      local bufnr = vim.fn.bufnr(path)
      if bufnr == -1 then
        return tools.json_result({})
      end
      opts.bufnr = bufnr
    end

    local by_file = {}
    local diags = opts.bufnr and vim.diagnostic.get(opts.bufnr) or vim.diagnostic.get()
    for _, d in ipairs(diags) do
      local name = vim.api.nvim_buf_get_name(d.bufnr)
      if name ~= "" then
        by_file[name] = by_file[name] or {}
        table.insert(by_file[name], {
          message = d.message,
          severity = severity_map[d.severity] or "Information",
          source = d.source,
          range = {
            start = { line = d.lnum, character = d.col },
            ["end"] = { line = d.end_lnum or d.lnum, character = d.end_col or d.col },
          },
        })
      end
    end

    local out = {}
    for name, list in pairs(by_file) do
      table.insert(out, { uri = "file://" .. name, diagnostics = list })
    end
    return tools.json_result(out)
  end,
})

return {}
