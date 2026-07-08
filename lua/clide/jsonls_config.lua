--- Auto-configure jsonls for Claude Code settings schema validation.
--- Matches VS Code extension's bundled schema support.
local M = {}

--- Configure jsonls to validate .claude/settings.json against the official schema.
--- Called automatically during setup() if jsonls is detected.
function M.configure()
  local ok, lspconfig = pcall(require, "lspconfig")
  if not ok then
    return false
  end
  if not lspconfig.jsonls then
    return false
  end

  local ok2, jsonls_config = pcall(lspconfig.jsonls.get_default_config)
  if not ok2 then
    return false
  end

  -- Use schemastore.org URL (official, same as CLI references)
  local schema = {
    fileMatch = { "/.claude/settings.json", "/.claude/settings.local.json" },
    url = "https://json.schemastore.org/claude-code-settings.json",
  }

  -- Merge with existing schemas, avoiding duplicates
  local current_settings = vim.deepcopy(lspconfig.jsonls.settings or {})
  if not current_settings.Lua then
    current_settings = vim.tbl_deep_extend("keep", current_settings, jsonls_config.settings or {})
  end
  local json_settings = current_settings.json or {}
  local schemas = json_settings.schemas or {}

  -- Check if already configured
  for _, s in ipairs(schemas) do
    if s.url == schema.url then
      return true -- already set up
    end
  end

  schemas[#schemas + 1] = schema
  json_settings.schemas = schemas
  current_settings.json = json_settings

  lspconfig.jsonls.setup({
    settings = current_settings,
  })

  return true
end

--- Bundle the schema locally for offline validation.
--- Returns path to the bundled schema file.
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
