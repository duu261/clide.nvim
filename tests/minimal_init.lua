vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/.deps/plenary.nvim")
-- specs run in parallel nvim processes and share fixtures; swapfiles collide (E325)
vim.o.swapfile = false
