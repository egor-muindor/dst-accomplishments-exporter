local M = {}

-- Returns (Category, name) for keys shaped "completed_<Category>_<name>", else nil.
-- Category has no underscores; name keeps them (split on the first underscore after the
-- prefix). nil for non-string input and for malformed keys (empty category/name), so
-- callers can treat it as a total filter.
function M.parse_completed_key(varname)
  if type(varname) ~= "string" then return nil end
  local rest = string.match(varname, "^completed_(.+)$")
  if not rest then return nil end
  local cat, name = string.match(rest, "^([^_]+)_(.+)$")
  if not cat then return nil end
  return cat, name
end

-- Parse a "num/max" progress string (what meta achievements' Record returns).
-- Returns (num, max) as numbers, or nil for any input that is not "%d+/%d+".
function M.parse_fraction(s)
  if type(s) ~= "string" then return nil end
  local num, max = string.match(s, "^(%d+)/(%d+)$")
  if not num then return nil end
  return tonumber(num), tonumber(max)
end

-- Normalize an achievement Record value to a progress numerator, or nil to omit it.
--   number -> itself (but 0 -> nil); "X/Y" -> X (but 0 -> nil); boolean/nil/other -> nil.
function M.normalize_record(r)
  local t = type(r)
  if t == "number" then
    if r == 0 then return nil end
    return r
  elseif t == "string" then
    local num = M.parse_fraction(r)
    if not num or num == 0 then return nil end
    return num
  end
  return nil
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

-- Drop progress keys that are already completed (present in achievements); return nil
-- for an empty result so an empty map is never serialized. Mutates `progress` in place.
local function prune_progress(progress, achievements)
  if type(progress) ~= "table" then return nil end
  for key in pairs(achievements or {}) do progress[key] = nil end
  if next(progress) == nil then return nil end
  return progress
end

-- merge_snapshot/merge_player take ownership of snapshot records and alias their
-- achievement entries into db (no deep copy: snapshots are read fresh each cycle and
-- discarded, so this is safe and keeps per-tick cost low). Do not reuse a snapshot
-- table after merging it.
local function merge_player(existing, incoming, shard_id)
  if not existing then
    incoming.online = true
    incoming.current_shard = shard_id
    incoming.achievements = incoming.achievements or {}
    incoming.progress = prune_progress(incoming.progress, incoming.achievements)
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
    -- Earliest unlock wins: a missing unlocked_irl counts as +inf ("unknown = latest"),
    -- so a known timestamp replaces an unknown one and re-merging identical data is a
    -- no-op (strict <).
    if not cur or (ach.unlocked_irl or math.huge) < (cur.unlocked_irl or math.huge) then
      existing.achievements[key] = ach
    end
  end
  -- Union progress across shards taking the max numerator; completed achievements win.
  local progress = existing.progress or {}
  for key, val in pairs(incoming.progress or {}) do
    if type(val) == "number" then
      local cur = progress[key]
      if not cur or val > cur then progress[key] = val end
    end
  end
  existing.progress = prune_progress(progress, existing.achievements)
  return existing
end

function M.merge_snapshot(db, snapshot)
  for uid, incoming in pairs(snapshot.players or {}) do
    db[uid] = merge_player(db[uid], incoming, snapshot.shard_id)
  end
  return db
end

-- current_shard is only meaningful while online; clear it so offline records don't
-- advertise a stale shard (online players get it re-set by merge_snapshot).
function M.mark_all_offline(db)
  for _, p in pairs(db) do
    p.online = false
    p.current_shard = nil
  end
  return db
end

-- Returns prev_unified.players BY REFERENCE when the session matches (it becomes the new
-- db, mutated in place by merge_snapshot), else {} for a world-regen reset.
function M.select_seed(prev_unified, cur_session)
  if prev_unified and prev_unified.cluster_session and cur_session
     and prev_unified.cluster_session == cur_session then
    return prev_unified.players or {}
  end
  return {}
end

-- Builds the JSON-able export. Does NOT mutate db: each player is shallow-copied and
-- stamped with achievements_count (the achievements sub-table is shared, read-only).
function M.build_export(db, meta)
  meta = meta or {}
  local players, count = {}, 0
  for uid, p in pairs(db) do
    count = count + 1
    local acount = 0
    for _ in pairs(p.achievements or {}) do acount = acount + 1 end
    local out = {}
    for k, v in pairs(p) do out[k] = v end
    out.achievements_count = acount
    players[uid] = out
  end
  return {
    schema_version = 2,
    cluster_session = meta.cluster_session,
    generated_irl = meta.generated_irl,
    player_count = count,
    catalog = meta.catalog,
    catalog_count = meta.catalog_count,
    players = players,
  }
end

-- True iff (now - generated_irl) <= max_age. Returns false (not error) when any argument
-- is not a number, so a missing/garbage timestamp reads as "stale". Exposed for specs and
-- external callers; the live healthcheck is tools/check_fresh.sh (kept consistent: <=, 90s).
function M.is_fresh(generated_irl, now, max_age)
  if type(generated_irl) ~= "number" or type(now) ~= "number"
     or type(max_age) ~= "number" then
    return false
  end
  return (now - generated_irl) <= max_age
end

return M
