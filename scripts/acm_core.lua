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

return M
