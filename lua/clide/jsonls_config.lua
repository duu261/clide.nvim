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

local function has_vim_lsp_config()
  return type(vim.lsp) == "table" and type(vim.lsp.config) == "function"
end

function M.configure()
  if has_vim_lsp_config() then
    -- nvim >= 0.11: use vim.lsp.config — no lspconfig dependency
    local ok, current = pcall(vim.lsp.config, "jsonls")
    vim.lsp.config("jsonls", merge_schema(ok and current or {}))
    return true
  end

  -- nvim < 0.11: lspconfig is safe — no deprecation __index warning.
  -- Note: accessing lspconfig.jsonls triggers __index, so skip entirely on 0.11+.
  local ok, lspconfig = pcall(require, "lspconfig")
  if ok and lspconfig and lspconfig.jsonls then
    pcall(lspconfig.jsonls.setup, { settings = merge_schema({}) })
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
