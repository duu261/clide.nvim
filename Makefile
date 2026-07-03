.PHONY: test lint
DEPS := .deps
PLENARY := $(DEPS)/plenary.nvim

$(PLENARY):
	mkdir -p $(DEPS)
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git $(PLENARY)

# Quiet by design: full output goes to $(DEPS)/last-test.log; stdout shows only
# the TOTAL line on success. On failure the whole log is dumped (for CI and for
# a human/agent debugging). This keeps the common green run to ~1 line instead of
# ~3000 tokens of per-test spam.
test: $(PLENARY)
	@nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" > $(DEPS)/last-test.log 2>&1 || true
	@awk '{ gsub(/\033\[[0-9;]*m/, "") } /^Success:/ { s += $$2 } /^Failed :/ { f += $$3 } /^Errors :/ { e += $$3 } END { printf "TOTAL: %d passed, %d failed, %d errors\n", s, f, e; exit (f + e > 0 || s == 0) }' $(DEPS)/last-test.log || { echo "── FAILED — full log below ($(DEPS)/last-test.log) ──"; cat $(DEPS)/last-test.log; exit 1; }

lint:
	stylua --check lua/ tests/
	luacheck lua/ tests/
