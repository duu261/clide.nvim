local config = require("clide.config")

local M = {}

local ns = vim.api.nvim_create_namespace("clide_review")

vim.api.nvim_set_hl(0, "ClideAdded", { link = "DiffAdd", default = true })
vim.api.nvim_set_hl(0, "ClideDeleted", { link = "DiffDelete", default = true })

--- Place one extmark per hunk: virt_lines preview additions, hl marks deletions.
function M.set_hint(review)
  local keys = config.get().review.keymaps
  local hint = ("clide review: %s accept  %s reject  %s all accept  %s all reject  %s next  %s prev"):format(
    keys.accept,
    keys.reject,
    keys.accept_all,
    keys.reject_all,
    keys.next_hunk,
    keys.prev_hunk
  )
  review.hint_extmark = vim.api.nvim_buf_set_extmark(review.bufnr, ns, 0, 0, {
    virt_lines = { { { hint, "Comment" } } },
    virt_lines_above = true,
    priority = 200,
  })
end

function M.attach(review, callbacks)
  callbacks = callbacks or {}
  if config.get().review.hint_line then
    M.set_hint(review)
  end
  for _, hunk in ipairs(review.hunks) do
    local line_count = vim.api.nvim_buf_line_count(review.bufnr)
    local row = math.max(hunk.start_a - 1, 0)
    if row > line_count then
      row = line_count
    end
    local virt_lines = {}
    for i = hunk.start_b, hunk.start_b + hunk.count_b - 1 do
      table.insert(virt_lines, { { "+ " .. review.new_lines[i], "ClideAdded" } })
    end
    local opts = {
      virt_lines = virt_lines,
      virt_lines_above = row == 0,
      sign_text = "\227\148\131",
      sign_hl_group = "ClideAdded",
      invalidate = true,
    }
    if hunk.count_a > 0 then
      opts.hl_group = "ClideDeleted"
      opts.end_row = math.min(row + hunk.count_a, vim.api.nvim_buf_line_count(review.bufnr))
      opts.hl_eol = true
    end
    hunk.extmark = vim.api.nvim_buf_set_extmark(review.bufnr, ns, row, 0, opts)
  end
  M.set_keymaps(review, callbacks)
end

--- Current 0-based row of a hunk's anchor extmark.
function M.hunk_row(review, hunk)
  local pos = vim.api.nvim_buf_get_extmark_by_id(review.bufnr, ns, hunk.extmark, {})
  return pos[1]
end

function M.clear_hunk(review, hunk)
  if hunk.extmark then
    vim.api.nvim_buf_del_extmark(review.bufnr, ns, hunk.extmark)
    hunk.extmark = nil
  end
end

function M.detach(review)
  for _, hunk in ipairs(review.hunks) do
    M.clear_hunk(review, hunk)
  end
  if review.hint_extmark then
    pcall(vim.api.nvim_buf_del_extmark, review.bufnr, ns, review.hint_extmark)
    review.hint_extmark = nil
  end
  local keys = config.get().review.keymaps
  for _, lhs in ipairs({ keys.accept, keys.reject, keys.accept_all, keys.reject_all }) do
    pcall(vim.keymap.del, "n", lhs, { buffer = review.bufnr })
  end
end

function M.set_keymaps(review, callbacks)
  callbacks = callbacks or {}
  local keys = config.get().review.keymaps
  local opts = function(desc)
    return { buffer = review.bufnr, desc = desc }
  end
  if callbacks.resolve_at_cursor then
    vim.keymap.set("n", keys.accept, function()
      callbacks.resolve_at_cursor(review, "accept")
    end, opts("clide: accept hunk"))
    vim.keymap.set("n", keys.reject, function()
      callbacks.resolve_at_cursor(review, "reject")
    end, opts("clide: reject hunk"))
  end
  if callbacks.resolve_all then
    vim.keymap.set("n", keys.accept_all, function()
      callbacks.resolve_all(review, "accept")
    end, opts("clide: accept all hunks"))
    vim.keymap.set("n", keys.reject_all, function()
      callbacks.resolve_all(review, "reject")
    end, opts("clide: reject all hunks"))
  end
end

return M
