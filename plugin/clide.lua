if vim.g.loaded_clide then
  return
end
vim.g.loaded_clide = true

-- commands available before setup(); setup() only adds config + autostart
require("clide.commands").setup()
