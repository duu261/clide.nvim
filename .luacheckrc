globals = { "vim" }
std = "luajit"
ignore = { "212" }

-- W143 fires on the `unpack or table.unpack` portability shim; the global
-- exists on LuaJIT (5.1), so the table.unpack fallback is never reached.
files["lua/clide/server/frame.lua"] = { ignore = { "143" } }

-- Busted test globals — provided by test runner at runtime
files["tests/"] = { globals = { "describe", "it", "before_each", "after_each", "assert" } }
