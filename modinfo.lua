name = "Accomplishments Exporter"
description = "Server-only companion to Accomplishments. Exports klei_id + nickname + unlocked achievements + in-game days survived to a JSON file, refreshed at least once per minute."
author = "egor"
version = "1.2.0"

api_version = 10
dst_compatible = true

all_clients_require_mod = false
client_only_mod = false
server_only_mod = true

-- Load AFTER Accomplishments (priority 1024) so _G.KaBroadcastAnnounceTrophy exists.
priority = 0

server_filter_tags = { "Accomplishments", "Achievements", "Exporter" }

configuration_options = {
  {
    name = "interval",
    label = "Write interval",
    hover = "How often each shard rewrites its partial file.",
    options = {
      { description = "15s", data = 15 },
      { description = "30s", data = 30 },
      { description = "60s", data = 60 },
    },
    default = 30,
  },
  {
    name = "world_interval",
    label = "World write interval",
    hover = "How often each shard rewrites its world snapshot (prefab counts + worldstate).",
    options = {
      { description = "30s", data = 30 },
      { description = "60s", data = 60 },
      { description = "120s", data = 120 },
    },
    default = 60,
  },
  -- Real value is a Lua array of prefab names, set per shard via modoverrides.lua;
  -- the declared default keeps the feature off until an operator opts in.
  {
    name = "world_prefabs",
    label = "World prefab counts",
    hover = "List of prefab names to count; set via modoverrides.lua. Off by default.",
    options = {
      { description = "Off (set via modoverrides.lua)", data = false },
    },
    default = false,
  },
}
