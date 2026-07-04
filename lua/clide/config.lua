local M = {}

local defaults = {
  autostart = false,
  sse_port = 42069,
  follow = false,
  auto_install_mcp = true,
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
      accept = "ga",
      reject = "gr",
      accept_all = "gA",
      reject_all = "gR",
      next_hunk = "]h",
      prev_hunk = "[h",
    },
  },
}

local current = vim.deepcopy(defaults)

function M.setup(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.get()
  return current
end

return M
