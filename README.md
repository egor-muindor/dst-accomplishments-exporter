# Accomplishments Exporter

A **server-only** companion mod for *Don't Starve Together* that exports, per cluster, a single JSON leaderboard of every player's achievements.

Depends on the [Accomplishments](https://steamcommunity.com/sharedfiles/filedetails/?id=2843097516) mod (Steam Workshop `2843097516`). The original mod is **never modified** — data is read through the shared `_G` environment.

---

## Overview

Each player entry in the output records:

- Klei ID (`klei_id`, e.g. `KU_xxxx`)
- Display name and character prefab
- In-game days survived
- All unlocked Accomplishments achievements, keyed as `"<Category>/<name>"`, each with unlock day and wall-clock timestamp

At the default 30 s write interval, the unified leaderboard file (`acm_export.json`) is refreshed within ~60 s end-to-end (in-game write ≤30 s + external merger ≤30 s). Selecting the 60 s interval option relaxes this bound proportionally.

---

## How it works

DST runs each shard (Master/Forest, Caves, …) as a separate OS process with its own save folder. Because `TheSim:SetPersistentString` only writes into the calling shard's storage, there is no way to share data between shards inside the game.

**Approach (per-shard files + external merger):**

1. The mod runs on every shard. Each shard writes a partial file `acm_export_shard_<shardid>.json` into its persistent-storage folder using `TheSim:SetPersistentString`. The file contains only the players currently online on that shard.

2. An external Lua merger (`tools/acm_merge.lua`) runs on the cluster host. It globs all `acm_export_shard_*.json` files under the cluster storage root, merges them, carries offline players forward from the previous unified output, and writes a single `acm_export.json`.

3. Session tracking prevents stale data from polluting a reset world: the merger keys on the cluster's master session id. A changed session id wipes the leaderboard rather than merging old shard files into a new world.

**Write triggers (in-game):**

- Periodic task every `interval` seconds (15/30/60, default 30)
- `ms_save` event
- `ms_playerdespawn` event
- ~5 s after world load
- Immediately on each fresh achievement unlock (wraps `KaBroadcastAnnounceTrophy`)

**Architecture:**

- `scripts/acm_core.lua` — pure transforms, no `_G` dependencies, fully unit-tested
- `scripts/acm_server.lua` — dependency-injection orchestration, thin wrapper over core
- `modmain.lua` — glue: reads game globals, wires events, calls `acm_server`
- `tools/acm_merge.lua` — external merger (runs on the host, not in-game)

---

## Installation

### Mod (every server shard)

Copy these files into the mod's folder on **every shard that runs DST**:

```
modinfo.lua
modmain.lua
scripts/
  acm_core.lua
  acm_server.lua
```

The mod is server-only (`server_only_mod = true`). Clients do **not** need it.

The Accomplishments mod must be installed and active; load order must place it before Accomplishments Exporter (Accomplishments has priority 1024; this mod has priority 0).

### Merger tools (cluster host only)

The `tools/` and `schema/` directories are **not** part of the in-game mod. They run on the machine hosting the cluster. Requirements:

- `lua` (any version compatible with 5.1+)
- `dkjson` LuaRocks package: `luarocks install dkjson`

### Configuration

One option is exposed in the mod's in-game config:

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `interval` | 15 / 30 / 60 | 30 | How often (seconds) each shard rewrites its partial file |

---

## Where files land

Each shard writes `acm_export_shard_<shardid>.json` into that shard's persistent-storage folder — the same location DST writes save data for that shard (e.g. `~/.klei/DoNotStarveTogether/<cluster>/Master/` for the master shard).

Pass the **cluster storage root** (the directory that contains the shard subdirectories) to the merger via `--root`.

---

## Running the merger

### Shell loop (simplest)

```bash
tools/acm_merge_loop.sh <mod_dir> <cluster_root> <out_file> [period_seconds]
```

- `<mod_dir>` — directory containing `scripts/` and `tools/` (so the script can put `acm_core` and `dkjson` on `LUA_PATH`)
- `<cluster_root>` — storage root with the shard subdirectories (the merger globs `acm_export_shard_*.json` recursively under this path)
- `<out_file>` — where to write the unified `acm_export.json`
- `[period_seconds]` — default 30

Example:

```bash
tools/acm_merge_loop.sh \
  /opt/acm-exporter \
  ~/.klei/DoNotStarveTogether/MyCluster \
  /var/www/leaderboard/acm_export.json \
  30
```

### Direct invocation (one shot)

```bash
# Run from the mod dir; acm_core (scripts/) and dkjson must be on LUA_PATH:
eval "$(luarocks path)"   # puts dkjson on LUA_PATH
LUA_PATH="./scripts/?.lua;./tools/?.lua;${LUA_PATH:-;;}" \
  lua tools/acm_merge.lua --root <cluster_root> --out <out_file>
```

Optional `--prev <path>` overrides the file used as the persistent carry-forward store (defaults to `--out`). The `acm_merge_loop.sh` loop and the systemd unit both set `LUA_PATH` for you (the unit evals `luarocks path` in its `ExecStart`, so `luarocks` must be on the service user's PATH).

### systemd (Linux servers)

Edit the paths marked `# CONFIGURE` in `tools/acm_merge.service`, then install it alongside `tools/acm_merge.timer` (fires every 30 s). The service is `Type=oneshot`; the timer provides the cadence.

```bash
# After editing the paths:
cp tools/acm_merge.service tools/acm_merge.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now acm_merge.timer
```

**Cadence:** at the default 30 s settings, shard writes (≤30 s) + merger (≤30 s) keep the unified file updated within ~60 s end-to-end. Larger `interval` / `period_seconds` values raise this bound.

---

## Output format

The merger writes a single `acm_export.json`. Top-level fields:

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | integer | Always `1` |
| `cluster_session` | string \| null | Master session id; changes on world regen |
| `generated_irl` | number | Unix timestamp of this merge run |
| `player_count` | integer | Number of tracked players |
| `players` | object | Map of `klei_id` → player record |

Each player record:

| Field | Type | Description |
|-------|------|-------------|
| `klei_id` | string | e.g. `"KU_xxxx"` |
| `name` | string | Display name at last seen |
| `prefab` | string \| null | Character prefab |
| `online` | boolean | Currently online on any shard |
| `current_shard` | string \| null | Shard id if online |
| `days_survived` | number | Max days across all shards |
| `last_seen_irl` | number | Unix timestamp of last shard write that included this player |
| `achievements_count` | integer | Count of unlocked achievements |
| `achievements` | object | Map of `"<Category>/<name>"` → achievement record |

Each achievement record:

| Field | Type | Description |
|-------|------|-------------|
| `title` | string \| null | Human-readable title (best-effort; may be null) |
| `day` | number \| null | In-game day of unlock |
| `unlocked_irl` | number \| null | Unix timestamp of unlock |

`achievements` is a JSON **object** (not an array), so merging is a stable key-union and empty maps encode unambiguously as `{}`.

### Example

Given two shard partials (`spec/fixtures/partials/`), the merged output looks like:

```json
{
  "schema_version": 1,
  "cluster_session": "S1",
  "generated_irl": 1200,
  "player_count": 2,
  "players": {
    "KU_a": {
      "klei_id": "KU_a",
      "name": "Alice",
      "prefab": "wilson",
      "online": true,
      "current_shard": "2",
      "days_survived": 9,
      "last_seen_irl": 1100,
      "achievements_count": 2,
      "achievements": {
        "Boss/deerclops": { "title": "Death Perception", "day": 5, "unlocked_irl": 900 },
        "Time/firstnight": { "title": "The Beginning",   "day": 1, "unlocked_irl": 800 }
      }
    },
    "KU_b": {
      "klei_id": "KU_b",
      "name": "Bob",
      "prefab": "wendy",
      "online": true,
      "current_shard": "2",
      "days_survived": 2,
      "last_seen_irl": 1100,
      "achievements_count": 0,
      "achievements": {}
    }
  }
}
```

### Schemas

- Shard partial: [`schema/acm_shard.schema.json`](schema/acm_shard.schema.json)
- Unified output: [`schema/acm_unified.schema.json`](schema/acm_unified.schema.json)

Both use JSON Schema draft 2020-12.

---

## Quality gate / development

No DST game install is needed to run the quality gate.

```bash
make deps    # install toolchain (busted + luacheck + dkjson via LuaRocks; ajv via npm)
make check   # lint + unit tests + schema validation → prints ALL CHECKS PASSED
```

`make check` runs three steps in sequence:

1. **`make lint`** — `luacheck .` (static analysis)
2. **`make test`** — `busted` (unit tests in `spec/`: core, server, merger)
3. **`make schema`** — builds `build/acm_export.json` from the fixture partials, then validates all `spec/fixtures/partials/*.json` against `schema/acm_shard.schema.json` and `build/acm_export.json` against `schema/acm_unified.schema.json` using `ajv` (via `tools/validate_schemas.js`)

**Lua version note:** The Makefile is wired for a macOS Homebrew **Lua 5.4** toolchain (`lua@5.4`), because luacheck is incompatible with Lua 5.5. The mod code itself is **Lua 5.1**-compatible (DST's runtime). CI (`.github/workflows/ci.yml`) runs the full suite on **Lua 5.1** to match the real runtime.

---

## Monitoring

`tools/check_fresh.sh <acm_export.json> [max_age_seconds]`

Exits 0 if `generated_irl` is within `max_age` seconds of now (default 90 s), exits 1 otherwise. Suitable for a cron or systemd healthcheck. Requires `python3`.

```bash
# Example: warn if file is older than 90 s
tools/check_fresh.sh /var/www/leaderboard/acm_export.json 90
```

---

## Out of scope (v1)

- **HTTP export** — the mod writes files only; serving them over HTTP is left to the operator (nginx, a static file server, etc.)
- **In-progress counter variables** — only values recorded in `kaachievementmanager:OnSave()` are exported; partial/counter fields are not
- **Shard-RPC transport** — cross-shard data flow is handled externally by the merger, not via DST's shard RPC API
- **Headless dedicated-server integration smoke test** — a future appendix
