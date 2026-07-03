vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/.deps/plenary.nvim")
-- specs run in parallel nvim processes and share fixtures; swapfiles collide (E325)
vim.o.swapfile = false

-- Stub snacks.terminal for provider tests (optional dep)
if not pcall(require, "snacks.terminal") then
  package.preload["snacks.terminal"] = function()
    return {
      open = function() end,
      get = function()
        return nil
      end,
      toggle = function() end,
    }
  end
end
