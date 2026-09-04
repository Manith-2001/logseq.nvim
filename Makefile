test:
	nvim --headless --noplugin -u tests/minimal_init.lua \
	  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua', sequential=true}"

lint:
	stylua --check .

ci: test lint

.PHONY: test lint ci
