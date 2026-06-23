local acm_core = require("acm_core")

local M = {}
local PREFIX = "acm_export_shard_"

function M.filename(ctx) return PREFIX .. tostring(ctx.shard_id) .. ".json" end

function M.snapshot(ctx)
  local now = ctx.now()
  local players = {}
  for _, p in ipairs(ctx.get_players()) do
    players[p.klei_id] = acm_core.build_record(p.on_save, {
      klei_id = p.klei_id, name = p.name, prefab = p.prefab,
      days_survived = p.days_survived, last_seen_irl = now,
      title_of = ctx.title_of,
    })
  end
  return {
    schema_version = 2,
    cluster_session = ctx.get_session(),
    shard_id = tostring(ctx.shard_id),
    generated_irl = now,
    players = players,
  }
end

function M.write_snapshot(ctx)
  local snap = M.snapshot(ctx)
  ctx.write(M.filename(ctx), ctx.json_encode(snap))
  return snap
end

return M
