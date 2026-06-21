local M = {}

function M.parse_completed_key(varname)
  local rest = string.match(varname, "^completed_(.+)$")
  if not rest then return nil end
  local cat, name = string.match(rest, "^([^_]+)_(.+)$")
  if not cat then return nil end
  return cat, name
end

function M.build_record(on_save, meta)
  meta = meta or {}
  local achievements = {}
  for k, v in pairs(on_save or {}) do
    if type(v) == "table" then
      local cat, name = M.parse_completed_key(k)
      if cat then
        local entry = { day = v.cycles, unlocked_irl = v.irl }
        if meta.title_of then entry.title = meta.title_of(cat, name) end
        achievements[cat .. "/" .. name] = entry
      end
    end
  end
  return {
    klei_id = meta.klei_id,
    name = meta.name,
    prefab = meta.prefab,
    days_survived = meta.days_survived or 0,
    last_seen_irl = meta.last_seen_irl,
    achievements = achievements,
  }
end

local function merge_player(existing, incoming, shard_id)
  if not existing then
    incoming.online = true
    incoming.current_shard = shard_id
    incoming.achievements = incoming.achievements or {}
    return incoming
  end
  existing.online = true
  existing.current_shard = shard_id
  existing.name = incoming.name or existing.name
  existing.prefab = incoming.prefab or existing.prefab
  existing.days_survived = math.max(existing.days_survived or 0, incoming.days_survived or 0)
  existing.last_seen_irl = math.max(existing.last_seen_irl or 0, incoming.last_seen_irl or 0)
  existing.achievements = existing.achievements or {}
  for key, ach in pairs(incoming.achievements or {}) do
    local cur = existing.achievements[key]
    if not cur or (ach.unlocked_irl or math.huge) < (cur.unlocked_irl or math.huge) then
      existing.achievements[key] = ach
    end
  end
  return existing
end

function M.merge_snapshot(db, snapshot)
  for uid, incoming in pairs(snapshot.players or {}) do
    db[uid] = merge_player(db[uid], incoming, snapshot.shard_id)
  end
  return db
end

function M.mark_all_offline(db)
  for _, p in pairs(db) do p.online = false end
  return db
end

return M
