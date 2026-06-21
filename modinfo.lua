name = "Accomplishments Exporter"
description = "Server-only companion to Accomplishments. Exports klei_id + nickname + unlocked achievements + in-game days survived to a JSON file, refreshed at least once per minute."
author = "egor"
version = "1.0.0"

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
}
