.PHONY: test lint
DEPS := .deps
PLENARY := $(DEPS)/plenary.nvim

$(PLENARY):
	mkdir -p $(DEPS)
	git clone https://github.com/nvim-lua/plenary.nvim.git $(PLENARY)

test: $(PLENARY)
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

lint:
	stylua --check .
