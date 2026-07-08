local M = {}

local VALID_FOLLOW = {
  off = true,
  jump = true,
  notify = true,
  both = true,
}

local defaults = {
  autostart = false,
  autosave = true, -- bool - save dirty buffers before tool dispatch
  execute_code = true, -- bool - set false to disable executeCode tool
  -- min severity pushed via diagnostics_changed: "error" | "warn" | "info" | "hint" | false (off)
  -- default "error": every push lands in Claude's context and costs tokens;
  -- style warnings rarely change what Claude does mid-edit
  diagnostics_push = "error",
  follow = "off",
  log_level = "info",
  terminal = {
    provider = "auto", -- auto | native | snacks | tmux | none
    cmd = "claude",
    split_side = "right",
    split_width = 0.35,
  },
  review = {
    inline = true,
    hint_line = true,
    keymaps = {
      accept = "<Leader>ma",
      reject = "<Leader>mr",
      accept_all = "<Leader>mA",
      reject_all = "<Leader>mR",
      next_hunk = "]h",
      prev_hunk = "[h",
    },
  },
  cmd_keymaps = {
    toggle = "<Leader>mt",
    start = "<Leader>ms",
    stop = "<Leader>mq",
    log = "<Leader>ml",
    send = "<Leader>me", -- visual mode: send selection
    send_toggle = "<Leader>mz", -- visual mode: send + toggle terminal
  },
}

local current = vim.deepcopy(defaults)

function M.setup(opts)
  if opts and opts.follow ~= nil and not VALID_FOLLOW[opts.follow] then
    error("invalid follow mode: " .. tostring(opts.follow))
  end
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.get()
  return current
end

return M
