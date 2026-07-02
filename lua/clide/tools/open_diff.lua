local tools = require("clide.tools")

local M = {}

--- tab_name -> { new_path, new_contents, respond, tab, scratch_buf, done }
M.active = {}

local function open_tab(rec)
  vim.cmd("tabnew " .. vim.fn.fnameescape(rec.new_path))
  rec.tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("diffthis")

  vim.cmd("vnew")
  local scratch = vim.api.nvim_get_current_buf()
  rec.scratch_buf = scratch
  vim.bo[scratch].buftype = "acwrite"
  vim.bo[scratch].bufhidden = "wipe"
  vim.api.nvim_buf_set_name(scratch, "clide://" .. rec.tab_name)
  local lines = vim.split(rec.new_contents, "\n")
  if lines[#lines] == "" then
    table.remove(lines) -- trailing newline artifact of split
  end
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  vim.bo[scratch].modified = false
  vim.cmd("diffthis")

  local group =
    vim.api.nvim_create_augroup("ClideDiff_" .. rec.tab_name:gsub("%W", "_"), { clear = true })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = scratch,
    callback = function()
      local ok, err = pcall(function()
        M.finish(rec.tab_name, "accept")
      end)
      if not ok then
        vim.notify("clide: error accepting diff: " .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = scratch,
    callback = function()
      local ok, err = pcall(function()
        M.finish(rec.tab_name, "reject")
      end)
      if not ok then
        vim.notify("clide: error rejecting diff: " .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  })
  vim.keymap.set("n", "ga", function()
    local ok, err = pcall(function()
      M.finish(rec.tab_name, "accept")
    end)
    if not ok then
      vim.notify("clide: error accepting diff: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, { buffer = scratch, desc = "clide: accept diff" })
  vim.keymap.set("n", "gr", function()
    local ok, err = pcall(function()
      M.finish(rec.tab_name, "reject")
    end)
    if not ok then
      vim.notify("clide: error rejecting diff: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, { buffer = scratch, desc = "clide: reject diff" })
end

function M.finish(tab_name, verdict)
  local rec = M.active[tab_name]
  if not rec or rec.done then
    return
  end
  rec.done = true
  M.active[tab_name] = nil

  if verdict == "accept" then
    -- take current scratch content (user may have edited on top)
    local lines = rec.scratch_buf
        and vim.api.nvim_buf_is_valid(rec.scratch_buf)
        and vim.api.nvim_buf_get_lines(rec.scratch_buf, 0, -1, false)
      or vim.split(rec.new_contents, "\n")
    if lines[#lines] == "" then
      table.remove(lines)
    end
    vim.fn.writefile(lines, rec.new_path)
    vim.cmd("silent! checktime")
    rec.respond(tools.text_result("FILE_SAVED"))
  else
    rec.respond(tools.text_result("DIFF_REJECTED"))
  end

  if rec.tab and vim.api.nvim_tabpage_is_valid(rec.tab) and #vim.api.nvim_list_tabpages() > 1 then
    vim.api.nvim_set_current_tabpage(rec.tab)
    vim.cmd("tabclose")
  end
end

tools.register({
  name = "openDiff",
  description = "Open a diff view comparing a file with proposed new contents",
  inputSchema = {
    type = "object",
    properties = {
      old_file_path = { type = "string" },
      new_file_path = { type = "string" },
      new_file_contents = { type = "string" },
      tab_name = { type = "string" },
    },
    required = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" },
  },
  handler = function(args, respond)
    local rec = {
      tab_name = args.tab_name,
      new_path = args.new_file_path,
      new_contents = args.new_file_contents,
      respond = respond,
      done = false,
    }
    M.active[args.tab_name] = rec
    local ok, err = pcall(open_tab, rec)
    if not ok then
      rec.done = true
      M.active[args.tab_name] = nil
      respond(nil, { code = -32603, message = tostring(err) })
      return
    end
    return tools.DEFER
  end,
})

tools.register({
  name = "closeAllDiffTabs",
  description = "Close all open diff tabs",
  inputSchema = { type = "object", properties = vim.empty_dict() },
  handler = function()
    local names = vim.tbl_keys(M.active)
    for _, name in ipairs(names) do
      M.finish(name, "reject")
    end
    return tools.text_result("CLOSED_" .. #names .. "_DIFF_TABS")
  end,
})

return M
