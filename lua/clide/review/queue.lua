local M = {}

local reviews = {}

local function set_global_maps()
  local keys = require("clide.config").get().review.keymaps
  vim.keymap.set("n", keys.next_hunk, function()
    M.jump(1)
  end, { desc = "clide: next review hunk" })
  vim.keymap.set("n", keys.prev_hunk, function()
    M.jump(-1)
  end, { desc = "clide: prev review hunk" })
end

local function del_global_maps()
  local keys = require("clide.config").get().review.keymaps
  pcall(vim.keymap.del, "n", keys.next_hunk)
  pcall(vim.keymap.del, "n", keys.prev_hunk)
end

function M.add(review)
  if #reviews == 0 then
    set_global_maps()
  end
  table.insert(reviews, review)
end

function M.remove(review)
  for i, r in ipairs(reviews) do
    if r == review then
      table.remove(reviews, i)
      break
    end
  end
  if #reviews == 0 then
    del_global_maps()
  end
end

function M.find(tab_name)
  for _, r in ipairs(reviews) do
    if r.tab_name == tab_name then
      return r
    end
  end
end

function M.current()
  local buf = vim.api.nvim_get_current_buf()
  for _, r in ipairs(reviews) do
    if r.bufnr == buf then
      return r
    end
  end
end

--- @return number resolved, number total (across all reviews)
function M.counts()
  local resolved, total = 0, 0
  for _, r in ipairs(reviews) do
    resolved = resolved + r.resolved
    total = total + #r.hunks
  end
  return resolved, total
end

function M.statusline()
  local resolved, total = M.counts()
  if total == 0 then
    return ""
  end
  return "review " .. resolved .. "/" .. total
end

--- Flat sorted list of pending hunks across all reviews: {review, hunk, row}.
local function pending()
  local render = require("clide.review.render")
  local out = {}
  for _, r in ipairs(reviews) do
    for _, h in ipairs(r.hunks) do
      if h.state == "pending" then
        table.insert(out, { review = r, hunk = h, row = render.hunk_row(r, h) })
      end
    end
  end
  table.sort(out, function(a, b)
    if a.review.bufnr ~= b.review.bufnr then
      return a.review.bufnr < b.review.bufnr
    end
    return a.row < b.row
  end)
  return out
end

--- dir = 1 next, -1 prev. Crosses buffer boundaries, wraps around.
function M.jump(dir)
  local items = pending()
  if #items == 0 then
    return
  end
  local cur_buf = vim.api.nvim_get_current_buf()
  local cur_row = vim.api.nvim_win_get_cursor(0)[1] - 1

  local target
  if dir > 0 then
    for _, item in ipairs(items) do
      if item.review.bufnr > cur_buf or (item.review.bufnr == cur_buf and item.row > cur_row) then
        target = item
        break
      end
    end
    target = target or items[1] -- wrap
  else
    for i = #items, 1, -1 do
      local item = items[i]
      if item.review.bufnr < cur_buf or (item.review.bufnr == cur_buf and item.row < cur_row) then
        target = item
        break
      end
    end
    target = target or items[#items] -- wrap
  end

  if target.review.bufnr ~= cur_buf then
    vim.api.nvim_set_current_buf(target.review.bufnr)
  end
  vim.api.nvim_win_set_cursor(0, { target.row + 1, 0 })
end

return M
