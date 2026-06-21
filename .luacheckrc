std = "lua51"
files["modmain.lua"] = {
  globals = { "GLOBAL", "Assets", "modinfo" },
  read_globals = { "GetModConfigData", "AddPrefabPostInit", "AddPrefabPostInitAny",
                   "AddModRPCHandler", "modimport", "env", "json" },
}
files["modinfo.lua"] = {
  globals = { "name","description","author","version","api_version","dst_compatible",
              "all_clients_require_mod","client_only_mod","server_only_mod","priority",
              "server_filter_tags","configuration_options","icon","icon_atlas" },
  max_line_length = false,
}
files["spec/**/*.lua"] = { std = "+busted" }
-- ".luarocks"/".lua" are created in-workspace by gh-actions-luarocks/-lua on CI;
-- exclude them so "luacheck ." lints our code, not the dependency tree.
exclude_files = { "lua_modules", "node_modules", "build", ".luarocks", ".lua" }
max_line_length = 140
