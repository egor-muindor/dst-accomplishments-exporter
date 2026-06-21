export PATH := /opt/homebrew/opt/lua@5.4/bin:$(HOME)/.luarocks/bin:$(PATH)
LUA_ROCKS_PATH := $(shell luarocks --lua-version 5.4 path --lr-path 2>/dev/null)
export LUA_PATH := ./scripts/?.lua;./tools/?.lua;./spec/?.lua;$(LUA_ROCKS_PATH);;

.PHONY: deps lint test schema check merge-fixture clean

deps:
	luarocks --lua-version 5.4 --lua-dir /opt/homebrew/opt/lua@5.4 install --local busted
	luarocks --lua-version 5.4 --lua-dir /opt/homebrew/opt/lua@5.4 install --local luacheck
	luarocks --lua-version 5.4 --lua-dir /opt/homebrew/opt/lua@5.4 install --local dkjson
	npm install

lint:
	luacheck .

test:
	busted

merge-fixture:
	mkdir -p build
	lua tools/acm_merge.lua --root spec/fixtures/partials --out build/acm_export.json
	@echo "merged -> build/acm_export.json"

schema: merge-fixture
	npx ajv validate -s schema/acm_shard.schema.json -d "spec/fixtures/partials/*.json" --spec=draft2020
	npx ajv validate -s schema/acm_unified.schema.json -d build/acm_export.json --spec=draft2020

check: lint test schema
	@echo "ALL CHECKS PASSED"

clean:
	rm -rf build
