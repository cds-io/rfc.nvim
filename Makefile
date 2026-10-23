# Prefer the user LuaRocks launcher when present; otherwise resolve from PATH.
# BUSTED can still be set explicitly on the command line or in the environment.
BUSTED ?= $(if $(wildcard $(HOME)/.luarocks/bin/busted),$(HOME)/.luarocks/bin/busted,busted)
# nlua runs Neovim as a Lua interpreter, which lets busted run inside it.
NLUA ?= $(if $(wildcard $(HOME)/.luarocks/bin/nlua),$(HOME)/.luarocks/bin/nlua,nlua)
LUAROCKS ?= luarocks
SELENE ?= selene
STYLUA ?= stylua

.PHONY: check test test-nvim lint fmt fmt-check vendor vendor-check

check: vendor-check test test-nvim lint fmt-check

# The house library lives in ../cds, its one source, with its own specs;
# these files are copies of it. `make vendor` refreshes them and
# `vendor-check` refuses a copy that differs. A checkout without ../cds
# (CI) skips the check.
CDS_SRC ?= ../cds
CDS_FILES := lua/cds/task.lua lua/cds/async.lua lua/cds/proc.lua lua/cds/http.lua lua/cds/activity.lua lua/cds/rfc.lua \
	lua/cds/eip.lua lua/cds/bip.lua lua/cds/simd.lua lua/cds/mentions.lua lua/cds/fp.lua lua/cds/result.lua lua/cds/csv.lua lua/cds/subjects.lua lua/cds/w3c.lua lua/cds/images.lua \
	lua/cds/html/init.lua lua/cds/html/tokens.lua lua/cds/html/tree.lua lua/cds/html/inline.lua lua/cds/html/blocks.lua

vendor:
	@for f in $(CDS_FILES); do mkdir -p "$$(dirname $$f)"; cp "$(CDS_SRC)/$$f" "$$f"; done

vendor-check:
	@if [ -d "$(CDS_SRC)" ]; then \
		for f in $(CDS_FILES); do \
			cmp -s "$(CDS_SRC)/$$f" "$$f" || { echo "$$f differs from $(CDS_SRC)/$$f: run make vendor"; exit 1; }; \
		done; \
	else echo "vendor-check: $(CDS_SRC) absent, skipped"; fi

test:
	$(BUSTED)

# The *_nvim_spec.lua files: busted, with Neovim as its interpreter. busted
# starts under plain Lua and runs itself again under nlua, which finds
# busted's modules through the paths luarocks names. nlua runs whatever is
# on a stdin that is no terminal as Lua once the specs are done, so it gets
# an empty one. Each file gets a Neovim of its own, so a spec that opens
# help windows leaves nothing behind for the next file. The cache directory
# is a temporary one as a second guard behind the spec's own cache_dir, so
# a spec never touches the reader's own RFC store. The existence test keeps
# the target green when the tier is empty, since an unmatched glob is a
# literal path.
test-nvim:
	@eval "$$($(LUAROCKS) --lua-version 5.1 path)" && \
	export XDG_CACHE_HOME="$$(mktemp -d)" && \
	for spec in spec/*_nvim_spec.lua; do \
		[ -e "$$spec" ] || continue; \
		echo "$$spec"; \
		$(BUSTED) --run=nvim --lua=$(NLUA) "$$spec" </dev/null || exit 1; \
	done

# Lints lua/ and the plugin entry point. spec/ is
# excluded: it uses busted's describe/it/assert DSL, which selene's
# lua/neovim std library does not model.
lint:
	$(SELENE) lua plugin

# Formats the Lua tree with stylua (stylua.toml).
fmt:
	$(STYLUA) lua plugin spec

fmt-check:
	$(STYLUA) --check lua plugin spec
