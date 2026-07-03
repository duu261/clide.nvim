.PHONY: test lint
DEPS := .deps
PLENARY := $(DEPS)/plenary.nvim

$(PLENARY):
	mkdir -p $(DEPS)
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git $(PLENARY)

test: $(PLENARY)
	@nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" 2>&1 | tee $(DEPS)/last-test.log
	@awk '{ gsub(/\033\[[0-9;]*m/, "") } /^Success:/ { s += $$2 } /^Failed :/ { f += $$3 } /^Errors :/ { e += $$3 } END { printf "\nTOTAL: %d passed, %d failed, %d errors\n", s, f, e; if (f + e > 0 || s == 0) exit 1 }' $(DEPS)/last-test.log

lint:
	stylua --check lua/ tests/
	luacheck lua/ tests/
