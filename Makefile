# Prefer the user LuaRocks launcher when present; otherwise resolve from PATH.
# BUSTED can still be set explicitly on the command line or in the environment.
BUSTED ?= $(if $(wildcard $(HOME)/.luarocks/bin/busted),$(HOME)/.luarocks/bin/busted,busted)
# nlua runs Neovim as a Lua interpreter, which lets busted run inside it.
NLUA ?= $(if $(wildcard $(HOME)/.luarocks/bin/nlua),$(HOME)/.luarocks/bin/nlua,nlua)
LUAROCKS ?= luarocks
SELENE ?= selene
STYLUA ?= stylua

# mini.doc generates doc/rfc.txt from the annotation blocks scripts/minidoc.lua
# names: the standalone nvim-mini/mini.doc beside this checkout (CI), or the
# mini.nvim lazy installed, which carries it.
MINIDOC ?= $(firstword $(wildcard ../mini.doc $(HOME)/.local/share/nvim/lazy/mini.doc $(HOME)/.local/share/nvim/lazy/mini.nvim))

.PHONY: check test test-nvim lint fmt fmt-check doc doc-check

check: test test-nvim lint fmt-check doc-check

# The house library, cds-lua, is a dependency: lazy.lua names the dependency the
# editor loads, and .busted finds the same modules in ../cds-lua, the
# checkout beside this one, for both spec tiers (CI checks it out there).
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
	$(STYLUA) lua plugin spec scripts

fmt-check:
	$(STYLUA) --check lua plugin spec scripts

# The help file, generated in place; the tags file it leaves behind is
# ignored, since the plugin manager builds it on install.
doc:
	nvim --headless -u NONE -i NONE --cmd "set rtp+=$(MINIDOC)" -l scripts/minidoc.lua

# A stale help file fails: regenerate and commit it.
doc-check: doc
	git diff --exit-code -- doc/rfc.txt
