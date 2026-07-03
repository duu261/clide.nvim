globals = { "vim" }
std = "luajit"
ignore = { "212" }

files["lua/clide/init.lua"] = { ignore = { "211" } }
-- W143 fires on the `unpack or table.unpack` portability shim; the global
-- exists on LuaJIT (5.1), so the table.unpack fallback is never reached.
files["lua/clide/server/frame.lua"] = { ignore = { "143" } }
files["lua/clide/status.lua"] = { ignore = { "231" } }
