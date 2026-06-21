# Accomplishments Exporter — Production Deployment Runbook

This runbook is for **operators** deploying the `acm-exporter` mod on a real *Don't Starve Together* (DST) dedicated server (LinuxGSM-style cluster verified). Follow the steps in order.

`acm-exporter` is a **server-only** companion to the **Accomplishments** mod (Steam Workshop `2843097516`). It exports, per cluster, one JSON leaderboard (`acm_export.json`) listing each player's `klei_id`, name, prefab, days survived, and unlocked achievements. The base **Accomplishments** mod is never modified — data is read through the shared `_G` environment.

There are two distinct parts you will deploy:

- **In-game mod files** — run inside DST, on **every shard**. They write one partial JSON file per shard.
- **Host-side tools** — run on the cluster host (not in DST). They merge all shard partials into one unified `acm_export.json`.

---

## 1. Prerequisites

- **Base mod, load-ordered first.** The **Accomplishments** workshop mod (`2843097516`) must be installed and enabled. It must load **before** Accomplishments Exporter so that `_G.KaBroadcastAnnounceTrophy` exists when this mod hooks it. Accomplishments has `priority = 1024`; `acm-exporter` has `priority = 0`, so the load order is automatic — do not change these priorities.
- **`acm-exporter` is server-only** (`server_only_mod = true`). Clients do not need it (`all_clients_require_mod = false`).
- **Host (merger) requirements:**
  - `lua` — any version compatible with **5.1+**.
  - **`dkjson`** LuaRocks package: `luarocks install dkjson`.
  - For freshness monitoring (`check_fresh.sh`): `python3`.
  - `find` (used by the merger to glob partials recursively) — standard on any Linux host.

---

## 2. Where to get the files

Download the GitHub release zip:

```
dst-accomplishments-exporter-*.zip
```

It contains two functionally separate groups:

**In-game mod files** (these become the `acm-exporter` folder mod — install on every shard):

```
modinfo.lua
modmain.lua
scripts/
  acm_core.lua
  acm_server.lua
```

**Host-side tools** (these run on the cluster host only — **not** part of the in-game mod):

```
tools/
  acm_merge.lua          # the merger
  acm_merge_loop.sh      # shell-loop runner
  acm_merge.service      # systemd unit (oneshot)
  acm_merge.timer        # systemd timer (30s cadence)
  check_fresh.sh         # freshness/health check
schema/
  acm_shard.schema.json
  acm_unified.schema.json
```

A convenient layout is to unpack the whole release into one install dir on the host, e.g. `/opt/acm-exporter/`, so that `scripts/` and `tools/` sit side by side (the runner and systemd unit expect this — see §5).

---

## 3. Installing on the server

### 3.1 Install the base Accomplishments workshop mod

The base mod is a **workshop** mod, downloaded on server boot. Add it to your cluster's dedicated-server mod setup file:

`serverfiles/mods/dedicated_server_mods_setup.lua`

```lua
ServerModSetup("2843097516")
```

On the next server boot this downloads the Accomplishments mod into `serverfiles/mods/`.

### 3.2 Install acm-exporter as a LOCAL folder mod

`acm-exporter` is installed as a **local** folder mod (not a workshop mod). Copy the in-game mod files (§2) into:

```
serverfiles/mods/acm-exporter/
```

Resulting structure:

```
serverfiles/mods/acm-exporter/
  modinfo.lua
  modmain.lua
  scripts/acm_core.lua
  scripts/acm_server.lua
```

The folder name `acm-exporter` is the mod's identity for local mods — it must match exactly in `modoverrides.lua` below.

### 3.3 Enable BOTH mods in EVERY shard's modoverrides.lua

This is the most error-prone step. Each shard (Master **and** Caves) is a separate process with its own `modoverrides.lua`. **Both files must be edited** — enabling a mod on Master only will leave Caves silently un-exported.

Edit both:

```
~/.klei/DoNotStarveTogether/<Cluster>/Master/modoverrides.lua
~/.klei/DoNotStarveTogether/<Cluster>/Caves/modoverrides.lua
```

Each must contain (or merge into your existing `return { ... }`):

```lua
return {
  ["workshop-2843097516"] = { enabled = true },
  ["acm-exporter"] = {
    enabled = true,
    configuration_options = { interval = 30 },
  },
}
```

Key naming rules (get these exactly right or the mod will not load):

- **Workshop mods** key on `"workshop-<id>"` → `["workshop-2843097516"]`.
- **Local folder mods** key on the **exact folder name** → `["acm-exporter"]`.

Apply the same block to **every** shard's `modoverrides.lua`. Restart the cluster after editing.

---

## 4. In-game configuration option

One config option is exposed (`modinfo.lua` → `configuration_options`):

| Option | Values | Default | Controls |
|--------|--------|---------|----------|
| `interval` | `15` / `30` / `60` (seconds) | `30` | How often **each shard rewrites its partial file** |

Set it in each shard's `modoverrides.lua` via `configuration_options = { interval = 30 }`.

Besides this periodic timer, each shard also rewrites its partial on these in-game triggers (no configuration needed): `ms_save`, `ms_playerdespawn`, ~5 s after world load, and immediately on each fresh achievement unlock (the mod wraps `KaBroadcastAnnounceTrophy`).

**End-to-end freshness:** at the default 30 s interval, the unified file is refreshed within ~60 s end-to-end (in-game write ≤30 s + merger ≤30 s). The 15 s option tightens this; 60 s relaxes it proportionally. Match the merger's period (§5) to the chosen interval.

---

## 5. Running the merger on the host

The merger (`tools/acm_merge.lua`) runs on the cluster host. It recursively globs all `acm_export_shard_*.json` partials under `--root`, merges them by `klei_id`, and writes one unified `acm_export.json` to `--out`.

**Critical:** `--root` must be the **cluster storage root** — the directory that *contains* the shard subdirectories (`Master/`, `Caves/`, …), e.g. `~/.klei/DoNotStarveTogether/<Cluster>`. The merger searches **recursively** beneath it, so do not point it at a single shard's `Master/` directory.

Pick **one** of the three runners below.

### (a) Shell loop — simplest

```bash
tools/acm_merge_loop.sh <mod_dir> <cluster_root> <out_file> [period_seconds]
```

- `<mod_dir>` — the install dir containing `scripts/` and `tools/` (so `acm_core` and `dkjson` resolve on `LUA_PATH`; the script sets `LUA_PATH` for you and runs `eval "$(luarocks path)"`).
- `<cluster_root>` — the cluster storage root that contains the shard subdirectories.
- `<out_file>` — where to write the unified `acm_export.json`.
- `[period_seconds]` — loop cadence, default `30`.

On a failed merge the loop prints `[acm] merge failed` to stderr and keeps running.

Example:

```bash
tools/acm_merge_loop.sh \
  /opt/acm-exporter \
  ~/.klei/DoNotStarveTogether/MyCluster \
  /var/www/leaderboard/acm_export.json \
  30
```

### (b) systemd service + timer — recommended for Linux servers

Edit the paths marked **`# CONFIGURE`** in `tools/acm_merge.service`. The shipped `ExecStart` is:

```ini
ExecStart=/bin/sh -c 'eval "$(luarocks path)"; export LUA_PATH="/opt/acm-exporter/scripts/?.lua;/opt/acm-exporter/tools/?.lua;$LUA_PATH;;"; exec lua /opt/acm-exporter/tools/acm_merge.lua --root /path/to/cluster --out /path/to/cluster/acm_export.json'
```

Replace:
- `/opt/acm-exporter` → your install dir (must contain `scripts/` and `tools/`).
- `--root /path/to/cluster` → your **cluster storage root**.
- `--out /path/to/cluster/acm_export.json` → your output path.

Requirements: `luarocks` and `lua` must be on the **service user's PATH** (the unit evals `luarocks path` in `ExecStart` to put `dkjson` on `LUA_PATH`). The service is `Type=oneshot`; the timer (`tools/acm_merge.timer`) provides the cadence (`OnBootSec=30`, `OnUnitActiveSec=30`, `AccuracySec=5s` → fires every 30 s).

Install:

```bash
cp tools/acm_merge.service tools/acm_merge.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now acm_merge.timer
```

### (c) One-shot / cron

Single run (run from the install dir; `acm_core` and `dkjson` must be on `LUA_PATH`):

```bash
eval "$(luarocks path)"   # puts dkjson on LUA_PATH
LUA_PATH="./scripts/?.lua;./tools/?.lua;${LUA_PATH:-;;}" \
  lua tools/acm_merge.lua --root <cluster_root> --out <out_file>
```

As a cron entry (every minute is the finest cron granularity; use runner (a) or (b) for sub-minute cadence):

```cron
* * * * * cd /opt/acm-exporter && eval "$(luarocks path)" && LUA_PATH="./scripts/?.lua;./tools/?.lua;;" lua tools/acm_merge.lua --root /home/dst/.klei/DoNotStarveTogether/MyCluster --out /var/www/leaderboard/acm_export.json >/dev/null 2>&1
```

**Optional flag:** `--prev <path>` overrides the carry-forward store used to retain offline players (defaults to `--out`).

---

## 6. Output: where it lands and serving it

- The merger writes a single unified file to your `--out` path (e.g. `/var/www/leaderboard/acm_export.json`).
- Each shard writes its own partial `acm_export_shard_<shardid>.json` into that shard's persistent-storage folder (the same dir DST writes its save data, e.g. `~/.klei/DoNotStarveTogether/<Cluster>/Master/`). These partials are the merger's input; you do not serve them directly.

**Serving the file is the operator's job.** The mod and merger are **file-output only** — there is no built-in HTTP. Point an nginx location or any static file server at the directory containing `acm_export.json`. A common pattern is to merge directly into your web root (e.g. `--out /var/www/leaderboard/acm_export.json`).

Top-level output fields: `schema_version` (always `1`), `cluster_session` (master session id, or `null`), `generated_irl` (unix time of the merge run), `player_count`, and `players` (map of `klei_id` → record). Validate against `schema/acm_unified.schema.json` (JSON Schema draft 2020-12) if you build downstream tooling.

---

## 7. Multi-shard notes

- Each shard (Master, Caves, …) is a separate process and writes **its own** partial `acm_export_shard_<shardid>.json` into its own save dir, containing only the players currently online on that shard.
- The host-side merger globs **all** partials recursively under `--root` and merges them **by `klei_id`**:
  - **`achievements`** — union across shards.
  - **`days_survived`** — the **max** across all shards.
  - **`current_shard`** — the shard the player is currently on.
  - **`online`** — `true` if the player is online on any shard.
  - Offline players are carried forward from the previous unified output.
- This is why §3.3 insists on enabling the mod on **every** shard: a shard whose `modoverrides.lua` is missing the entries writes no partial, so its players never appear in the leaderboard.

---

## 8. Freshness / monitoring

Use `tools/check_fresh.sh` to verify the unified file is being updated. It reads `generated_irl` and compares it to now. Requires `python3`.

```bash
tools/check_fresh.sh <acm_export.json> [max_age_seconds]
```

- Exit `0` if `generated_irl` is within `max_age` seconds of now (default `90`); exit `1` otherwise (also exits `1` if the file is unreadable or missing `generated_irl`). It prints the measured age.

```bash
# Warn if the file is older than 90s
tools/check_fresh.sh /var/www/leaderboard/acm_export.json 90
```

Wire this into a cron healthcheck or systemd watchdog. A persistent non-zero exit means the merger is not running or is pointed at the wrong `--root` (see §10). The default 90 s threshold matches the default ~60 s end-to-end cadence with headroom; raise it if you use a 60 s `interval` / `period`.

---

## 9. Behavior & limits

- **Leaderboard resets on world regen (wipe).** The merger keys on the cluster's **master session id** (`cluster_session`). When that session id changes (a new world / regen), the merger **wipes** the leaderboard rather than merging old shard files into the new world. Stale partials from a previous world are not allowed to repopulate a freshly reset leaderboard.
- **No cross-wipe aggregation.** Carrying scores **across** world regens is intentionally **not** part of the mod or merger. It is planned as a future **external accumulator script** that sits on top of the per-session output.
- **File output only.** No HTTP export, no shard-RPC transport. Serving the file is the operator's responsibility (§6). Cross-shard data flow is handled by the external merger, not DST's shard RPC.
- **Exported achievement data** is limited to what `kaachievementmanager:OnSave()` records; in-progress / partial counter values are not exported.

---

## 10. Troubleshooting

**Mod not loading (no partials appear at all):**
- Verify load order: Accomplishments (`workshop-2843097516`, priority 1024) must be enabled and load **before** acm-exporter (priority 0). Do not alter the shipped priorities.
- Confirm `ServerModSetup("2843097516")` is in `dedicated_server_mods_setup.lua` and the workshop mod actually downloaded into `serverfiles/mods/` on boot.
- Confirm the local mod folder is exactly `serverfiles/mods/acm-exporter/` and the `modoverrides.lua` key is exactly `["acm-exporter"]` (folder-name match) and `["workshop-2843097516"]` (workshop match).
- Check the server log for in-game write-failure lines from the mod.

**Empty leaderboard (`acm_export.json` exists but `players` is `{}` / a shard is missing):**
- A shard's `modoverrides.lua` is missing the entries. Confirm **both** Master **and** Caves have both mods enabled (§3.3) — the most common cause.
- The merger is pointed at the wrong `--root`. It must be the **cluster storage root** that *contains* the shard dirs, not a single shard dir. The merger globs `acm_export_shard_*.json` **recursively**, so partials must live under `--root`.
- Confirm shard partials actually exist: look for `acm_export_shard_<shardid>.json` files under the cluster root.
- A recent world regen will reset the leaderboard by design (§9).

**Stale file (`acm_export.json` not updating / `check_fresh.sh` exits 1):**
- The merger is not running. Check `systemctl status acm_merge.timer` / `journalctl -u acm_merge.service`, or that the shell loop (look for `[acm] merge failed` on stderr) / cron is still alive.
- `dkjson` not found on the service user's `LUA_PATH`: ensure `luarocks install dkjson` ran for that user and that `luarocks`/`lua` are on the service user's PATH (the runners eval `luarocks path`).
- `--out` is on a read-only or wrong path; confirm the merger can write there.
- If only the **in-game** writes are stale, raise/inspect the shard `interval` and confirm the cluster is actually running.
