# Dev toolchain (macOS): Lua 5.4 (lua@5.4) + --local LuaRocks bin, neither on PATH by
# default. Prefixed per-recipe (not a top-level `export PATH`) because GNU Make 3.81
# execs single-word recipes directly, bypassing an exported PATH. The inline PATH= form
# forces shell routing; on CI these dirs are absent and tools resolve from $PATH instead.
TOOLCHAIN_PATH := /opt/homebrew/opt/lua@5.4/bin:$(HOME)/.luarocks/bin
LUA_ROCKS_PATH := $(shell luarocks --lua-version 5.4 --lua-dir /opt/homebrew/opt/lua@5.4 path --lr-path 2>/dev/null)
export LUA_PATH := ./scripts/?.lua;./tools/?.lua;./spec/?.lua;$(LUA_ROCKS_PATH);;

.PHONY: deps lint test schema check merge-fixture clean

deps:
	luarocks --lua-version 5.4 --lua-dir /opt/homebrew/opt/lua@5.4 install --local busted
	luarocks --lua-version 5.4 --lua-dir /opt/homebrew/opt/lua@5.4 install --local luacheck
	luarocks --lua-version 5.4 --lua-dir /opt/homebrew/opt/lua@5.4 install --local dkjson
	npm install

lint:
	PATH="$(TOOLCHAIN_PATH):$$PATH" luacheck .

test:
	PATH="$(TOOLCHAIN_PATH):$$PATH" busted

merge-fixture:
	mkdir -p build
	PATH="$(TOOLCHAIN_PATH):$$PATH" lua tools/acm_merge.lua --root spec/fixtures/partials --out build/acm_export.json
	@echo "merged -> build/acm_export.json"

schema: merge-fixture
	node tools/validate_schemas.js schema/acm_shard.schema.json "spec/fixtures/partials/*.json"
	node tools/validate_schemas.js schema/acm_unified.schema.json build/acm_export.json

check: lint test schema
	@echo "ALL CHECKS PASSED"

clean:
	rm -rf build
