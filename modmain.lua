local _G = GLOBAL

-- Server-only: the kaachievementmanager component exists only on the server.
if _G.TheNet:GetIsClient() then return end

local acm_server = require("acm_server")
local acm_core = require("acm_core")
local acm_goals = require("acm_goals")
local json = _G.json
local interval = (GetModConfigData and GetModConfigData("interval")) or 30

-- Resolve an achievement's denominator (the "Y" in X/Y):
--   1) meta: Record({}) returns a "num/max" string  -> max;
--   2) counter: scripts/acm_goals.lua                -> goal;
--   3) boolean / one-shot                            -> 1.
local function compute_goal(category, name, entry)
  if entry.Record then
    local ok, r = _G.pcall(entry.Record, {})
    if ok then
      local _, max = acm_core.parse_fraction(r)
      if max then return max end
    end
  end
  return acm_goals[category .. "/" .. name] or 1
end

local function build_ctx()
  return {
    shard_id = (_G.TheShard and _G.TheShard:GetShardId()) or "0",
    get_session = function()
      local w = _G.TheWorld
      local ss = w and w.net and w.net.components and w.net.components.shardstate
      return (ss and ss:GetMasterSessionId()) or "unknown"
    end,
    get_catalog = function()
      local catalog = {}
      local loader = _G.GetKaAchievementLoader and _G.GetKaAchievementLoader()
      local entries = loader and loader.entries
      if type(entries) ~= "table" then return catalog end
      for category, list in pairs(entries) do
        for _, entry in ipairs(list) do
          if type(entry.name) == "string" then
            local id = category .. "/" .. entry.name
            local title
            local ok, t = _G.pcall(function()
              return _G.GetTrophyTitle and _G.GetTrophyTitle(category, entry.name) or nil
            end)
            if ok then title = t end
            catalog[id] = { title = title, goal = compute_goal(category, entry.name, entry) }
          end
        end
      end
      return catalog
    end,
    get_players = function()
      local out = {}
      local loader = _G.GetKaAchievementLoader and _G.GetKaAchievementLoader()
      local entries = loader and loader.entries
      for _, p in ipairs(_G.AllPlayers or {}) do
        local mgr = p.components and p.components.kaachievementmanager
        if mgr then
          local days = (p.components.age and p.components.age:GetAgeInDays()) or 0
          local progress = {}
          if type(entries) == "table" then
            for category, list in pairs(entries) do
              for _, entry in ipairs(list) do
                if type(entry.name) == "string" and entry.Record then
                  local id = category .. "/" .. entry.name
                  local done = false
                  if entry.Check then
                    local okc, c = _G.pcall(entry.Check, mgr)
                    done = (okc and c) and true or false
                  end
                  if not done then
                    local okr, raw = _G.pcall(entry.Record, mgr)
                    if okr then
                      local val = acm_core.normalize_record(raw)
                      if val ~= nil then progress[id] = val end
                    end
                  end
                end
              end
            end
          end
          out[#out + 1] = {
            klei_id = p.userid, name = p.name, prefab = p.prefab,
            days_survived = days, on_save = mgr:OnSave(), progress = progress,
          }
        end
      end
      return out
    end,
    now = function() return (_G.os and _G.os.time()) or 0 end,
    write = function(fn, str) _G.TheSim:SetPersistentString(fn, str, false) end,
    json_encode = function(t) return json.encode(t) end,
    title_of = function(cat, name)
      return _G.GetTrophyTitle and _G.GetTrophyTitle(cat, name) or nil
    end,
  }
end

local function WriteNow()
  local ok, err = _G.pcall(function() acm_server.write_snapshot(build_ctx()) end)
  if not ok then print("[ACM-Exporter] write failed: " .. tostring(err)) end
end

-- Periodic + lifecycle triggers on the world.
AddPrefabPostInit("world", function(world)
  world:DoPeriodicTask(interval, WriteNow)
  world:ListenForEvent("ms_save", WriteNow)
  world:ListenForEvent("ms_playerdespawn", WriteNow)
  -- Initial dump shortly after load; an early/empty snapshot self-heals via the
  -- merge step (max days + earliest unlock) on the next cycle.
  world:DoTaskInTime(5, WriteNow)
end)

-- Low-latency: rewrite immediately on a fresh unlock by wrapping the global.
local unlock_hooked = false
local function HookUnlock()
  if not unlock_hooked and _G.KaBroadcastAnnounceTrophy then
    local old = _G.KaBroadcastAnnounceTrophy
    _G.KaBroadcastAnnounceTrophy = function(...)
      old(...)
      WriteNow()
    end
    unlock_hooked = true
  end
end
HookUnlock()
AddPrefabPostInit("world", HookUnlock) -- fallback if not yet defined at modmain time
