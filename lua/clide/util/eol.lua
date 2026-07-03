local M = {}

--- Join lines into text, appending a trailing newline when the source's
--- line-ending state calls for one.
--- @param lines string[] already-split content lines (no trailing empty artifact)
--- @param bufnr integer|nil buffer to check 'eol' on, if still valid
--- @param fallback_text string|nil original unsplit text, used when bufnr is nil/invalid
--- @return string
function M.join(lines, bufnr, fallback_text)
  local text = table.concat(lines, "\n")
  if #lines == 0 then
    return text
  end
  local has_eol
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    has_eol = vim.bo[bufnr].eol
  elseif fallback_text then
    has_eol = fallback_text:sub(-1) == "\n"
  end
  if has_eol then
    text = text .. "\n"
  end
  return text
end

return M
