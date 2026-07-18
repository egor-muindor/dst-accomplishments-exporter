local M = {}
local PREFIX = "acm_world_shard_"

function M.filename(ctx) return PREFIX .. tostring(ctx.shard_id) .. ".json" end

-- Enabled only for a non-empty array: modinfo's declared default is `false`, and an
-- empty list would serialize counts as the ambiguous {}-vs-[] empty table.
function M.is_enabled(world_prefabs)
  return type(world_prefabs) == "table" and #world_prefabs > 0
end

-- prefab_iter: iterator function yielding prefab-name strings (nil terminates).
-- Every configured prefab is present in the result, zeros included (zero is signal).
-- Config names are normalized to lowercase; live prefab names are lowercase already.
function M.count_prefabs(prefab_iter, prefab_list)
  local counts = {}
  for _, name in ipairs(prefab_list or {}) do
    if type(name) == "string" then counts[string.lower(name)] = 0 end
  end
  for name in prefab_iter do
    if counts[name] then counts[name] = counts[name] + 1 end
  end
  return counts
end

function M.snapshot(ctx)
  return {
    schema_version = 1,
    cluster_session = ctx.get_session(),
    shard_id = tostring(ctx.shard_id),
    is_master = ctx.is_master,
    generated_irl = ctx.now(),
    worldstate = ctx.get_worldstate(),
    counts = M.count_prefabs(ctx.iterate_prefabs(), ctx.world_prefabs),
  }
end

function M.write_snapshot(ctx)
  local snap = M.snapshot(ctx)
  ctx.write(M.filename(ctx), ctx.json_encode(snap))
  return snap
end

return M
