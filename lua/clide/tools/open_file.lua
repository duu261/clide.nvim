local tools = require("clide.tools")

--- Find a window showing a normal file buffer to open into.
local function pick_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" then
      return win
    end
  end
  return vim.api.nvim_get_current_win()
end

tools.register({
  name = "openFile",
  description = "Open a file in the editor and optionally select text",
  inputSchema = {
    type = "object",
    properties = {
      filePath = { type = "string" },
      startText = { type = "string" },
      endText = { type = "string" },
      selectToEndOfLine = { type = "boolean" },
      makeFrontmost = { type = "boolean" },
      preview = { type = "boolean" },
    },
    required = { "filePath" },
  },
  handler = function(args)
    if vim.fn.filereadable(args.filePath) == 0 then
      return tools.json_result({
        success = false,
        message = "File not found: " .. args.filePath,
      })
    end

    local win = pick_window()
    vim.api.nvim_set_current_win(win)
    vim.cmd.edit(vim.fn.fnameescape(args.filePath))
    local bufnr = vim.api.nvim_get_current_buf()

    if args.startText and args.startText ~= "" then
      -- \V very nomagic + escape backslashes: literal search
      local spat = "\\V" .. vim.fn.escape(args.startText, "\\")
      local spos = vim.fn.searchpos(spat, "w")
      if spos[1] > 0 then
        vim.api.nvim_win_set_cursor(0, { spos[1], spos[2] - 1 })
        if args.endText and args.endText ~= "" then
          local epat = "\\V" .. vim.fn.escape(args.endText, "\\")
          local epos = vim.fn.searchpos(epat, "W")
          if epos[1] > 0 then
            vim.cmd("normal! v")
            vim.api.nvim_win_set_cursor(0, { epos[1], epos[2] - 1 })
            if args.selectToEndOfLine then
              vim.cmd("normal! $")
            end
          end
        end
      end
    end

    if args.makeFrontmost == false then
      return tools.json_result({
        success = true,
        filePath = args.filePath,
        languageId = vim.bo[bufnr].filetype,
        lineCount = vim.api.nvim_buf_line_count(bufnr),
      })
    end
    return tools.text_result("Opened file: " .. args.filePath)
  end,
})

return {}
