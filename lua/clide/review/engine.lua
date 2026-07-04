local render = require("clide.review.render")
local queue = require("clide.review.queue")
local eol = require("clide.util.eol")

local M = {}

--- vim.diff indices quadruples -> hunk records.
--- start_a/count_a: old side (current buffer), start_b/count_b: new side.
function M.compute_hunks(old_lines, new_lines)
  local old_text = table.concat(old_lines, "\n") .. "\n"
  local new_text = table.concat(new_lines, "\n") .. "\n"
  local indices = vim.diff(old_text, new_text, { result_type = "indices" })
  local hunks = {}
  for _, h in ipairs(indices) do
    table.insert(hunks, {
      start_a = h[1],
      count_a = h[2],
      start_b = h[3],
      count_b = h[4],
      state = "pending",
    })
  end
  return hunks
end

--- Open a review for an openDiff request. Returns the review record.
--- respond: JSON-RPC responder — called once when all hunks resolved.
function M.open(args, respond)
  local bufnr = vim.fn.bufnr(args.new_file_path)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(args.new_file_path)
  end
  vim.fn.bufload(bufnr)

  local new_lines = vim.split(args.new_file_contents, "\n")
  if new_lines[#new_lines] == "" then
    table.remove(new_lines)
  end

  local old_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local hunks = M.compute_hunks(old_lines, new_lines)

  if #hunks == 0 then
    -- Content is identical; respond with current buffer content
    local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local final_content = eol.join(buffer_lines, bufnr)
    respond({
      content = {
        { type = "text", text = "FILE_SAVED" },
        { type = "text", text = final_content },
      },
    })
    return nil
  end

  local review = {
    bufnr = bufnr,
    tab_name = args.tab_name,
    hunks = hunks,
    new_lines = new_lines,
    respond = respond,
    resolved = 0,
    accepted = 0,
    done = false,
  }

  render.attach(review)
  queue.add(review)
  return review
end

--- Apply or discard one hunk, then finish if all resolved.
function M.resolve_hunk(review, hunk, verdict)
  if hunk.state ~= "pending" or review.done then
    return
  end
  hunk.state = verdict == "accept" and "accepted" or "rejected"
  review.resolved = review.resolved + 1

  local label = verdict == "accept" and "Accepted" or "Rejected"
  vim.notify(
    "clide: " .. label .. " hunk (" .. review.resolved .. "/" .. #review.hunks .. ")",
    vim.log.levels.INFO
  )

  if verdict == "accept" then
    review.accepted = review.accepted + 1
    -- current position via extmark (buffer may have shifted)
    local row = render.hunk_row(review, hunk) -- 0-based row of hunk anchor
    local first, last
    if hunk.count_a == 0 then
      -- pure insertion: extmark sits on the line the insert follows
      first = hunk.start_a == 0 and 0 or row + 1
      last = first
    else
      first = row
      last = row + hunk.count_a
    end
    local replacement = {}
    for i = hunk.start_b, hunk.start_b + hunk.count_b - 1 do
      table.insert(replacement, review.new_lines[i])
    end
    vim.api.nvim_buf_set_lines(review.bufnr, first, last, false, replacement)
  end

  render.clear_hunk(review, hunk)

  if review.resolved == #review.hunks then
    M.finish(review)
  end
end

function M.resolve_at_cursor(review, verdict)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local best, best_dist
  for _, hunk in ipairs(review.hunks) do
    if hunk.state == "pending" then
      local hrow = render.hunk_row(review, hunk)
      local dist = math.abs(hrow - row)
      if not best or dist < best_dist then
        best, best_dist = hunk, dist
      end
    end
  end
  if best then
    M.resolve_hunk(review, best, verdict)
  end
end

function M.resolve_all(review, verdict)
  -- reverse order so earlier row numbers stay valid as later hunks apply
  for i = #review.hunks, 1, -1 do
    local hunk = review.hunks[i]
    if hunk.state == "pending" then
      M.resolve_hunk(review, hunk, verdict)
    end
  end
end

function M.finish(review)
  if review.done then
    return
  end
  review.done = true

  if review.accepted > 0 then
    -- Do NOT write the file; the Claude CLI will do that after receiving FILE_SAVED.
    -- Get the current buffer content for the response.
    local buffer_lines = vim.api.nvim_buf_get_lines(review.bufnr, 0, -1, false)
    local final_content = eol.join(buffer_lines, review.bufnr)
    review.respond({
      content = {
        { type = "text", text = "FILE_SAVED" },
        { type = "text", text = final_content },
      },
    })
    -- CLI writes this exact content to disk; mark clean so the mtime bump
    -- autoreads silently instead of raising W12.
    vim.bo[review.bufnr].modified = false
  else
    review.respond({
      content = {
        { type = "text", text = "DIFF_REJECTED" },
        { type = "text", text = review.tab_name },
      },
    })
  end

  if review.accepted > 0 then
    vim.notify(
      "clide: review complete \xe2\x80\x94 "
        .. review.accepted
        .. "/"
        .. #review.hunks
        .. " accepted",
      vim.log.levels.INFO
    )
  else
    vim.notify("clide: review complete \xe2\x80\x94 all hunks rejected", vim.log.levels.INFO)
  end

  render.detach(review)
  queue.remove(review)
end

return M
