--- Auto-configure jsonls for Claude Code settings schema validation.
--- Matches VS Code extension's bundled schema support.
--- No lspconfig calls on nvim >= 0.11 — avoids deprecation warnings.
local M = {}

local SCHEMA = {
  fileMatch = { "/.claude/settings.json", "/.claude/settings.local.json" },
  url = "https://json.schemastore.org/claude-code-settings.json",
}

local function merge_schema(settings)
  settings = vim.deepcopy(settings)
  settings.json = settings.json or {}
  settings.json.schemas = settings.json.schemas or {}
  for _, s in ipairs(settings.json.schemas) do
    if s.url == SCHEMA.url then
      return settings
    end
  end
  table.insert(settings.json.schemas, SCHEMA)
  return settings
end

function M.configure()
  -- nvim >= 0.11: vim.lsp.config. No require('lspconfig') — zero deprecation warns.
  local ok, current = pcall(function()
    return vim.lsp.config("jsonls")
  end)
  if ok then
    pcall(vim.lsp.config, "jsonls", merge_schema(current or {}))
    return true
  end

  return false
end

function M.schema_path()
  return vim.fn.fnamemodify(
    vim.fn.globpath(
      vim.fn.stdpath("config"),
      "**/clide.nvim/schemas/claude-code-settings.schema.json"
    ),
    ":p"
  )
end

return M
