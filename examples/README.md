# Example output

`acm_export.json` is a **real unified export** captured from the integration
test cluster (Master + Caves), not a hand-written fixture. It validates against
[`../schema/acm_unified.schema.json`](../schema/acm_unified.schema.json)
(`schema_version: 2`).

Captured 2026-06-28 from a live DST dedicated server running the base
**Accomplishments** mod (`workshop-2843097516`) + this exporter. It exercises
the schema v2 additions end-to-end:

- **`catalog` / `catalog_count`** — the player-independent achievement catalog
  (`"Category/name" → {title, goal}`), 243 entries, identical across shards and
  carried into the unified output by the merger.
- **`players[*].progress`** — per-player in-progress counters for *locked*
  achievements (`id → numerator`); completed ones live in `achievements`.
  Frontends render `progress[id] / catalog[id].goal`. The captured player has
  both unlocked `achievements` and a non-empty `progress` map (counter goals
  from `scripts/acm_goals.lua`, plus meta achievements whose goal is parsed live
  from `Record({})`).

Regenerate with the production merger (see [`../DEPLOYMENT.md`](../DEPLOYMENT.md)).
