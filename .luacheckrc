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
exclude_files = { "lua_modules", "node_modules", "build" }
max_line_length = 140
