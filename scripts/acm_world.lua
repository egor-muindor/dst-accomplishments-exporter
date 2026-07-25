local M = {}
local PREFIX = "acm_world_shard_"

function M.filename(ctx) return PREFIX .. tostring(ctx.shard_id) .. ".json" end

-- The string entries of the configured list, lowercased. Shared by is_enabled and
-- count_prefabs so they can never disagree on degenerate input. Iterates with pairs
-- rather than ipairs/1..# because a nil hole (e.g. an unquoted prefab name in
-- modoverrides.lua) makes # undefined in Lua 5.1 and would silently drop valid
-- entries; order does not matter — the names only ever become set keys.
local function normalized_names(prefab_list)
  local names = {}
  if type(prefab_list) ~= "table" then return names end
  for _, name in pairs(prefab_list) do
    if type(name) == "string" then names[#names + 1] = string.lower(name) end
  end
  return names
end

-- Enabled only for an array with >=1 string entry: modinfo's declared default is
-- `false`, and a list yielding zero usable names would serialize counts as the
-- ambiguous {}-vs-[] empty table (the schema requires a non-empty object).
function M.is_enabled(world_prefabs)
  return #normalized_names(world_prefabs) > 0
end

-- prefab_iter: iterator function yielding prefab-name strings (nil terminates).
-- Every configured prefab is present in the result, zeros included (zero is signal).
-- Config names are normalized to lowercase; live prefab names are lowercase already.
function M.count_prefabs(prefab_iter, prefab_list)
  local counts = {}
  for _, name in ipairs(normalized_names(prefab_list)) do
    counts[name] = 0
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
