local _G = GLOBAL

-- Server-only: the kaachievementmanager component exists only on the server.
if _G.TheNet:GetIsClient() then return end

local acm_server = require("acm_server")
local json = _G.json
local interval = (GetModConfigData and GetModConfigData("interval")) or 30

local function build_ctx()
  return {
    shard_id = (_G.TheShard and _G.TheShard:GetShardId()) or "0",
    get_session = function()
      local w = _G.TheWorld
      local ss = w and w.net and w.net.components and w.net.components.shardstate
      return (ss and ss:GetMasterSessionId()) or "unknown"
    end,
    get_players = function()
      local out = {}
      for _, p in ipairs(_G.AllPlayers) do
        local mgr = p.components and p.components.kaachievementmanager
        if mgr then
          local days = (p.components.age and p.components.age:GetAgeInDays()) or 0
          out[#out + 1] = {
            klei_id = p.userid, name = p.name, prefab = p.prefab,
            days_survived = days, on_save = mgr:OnSave(),
          }
        end
      end
      return out
    end,
    now = function() return _G.os.time() end,
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
  world:DoTaskInTime(5, WriteNow) -- initial dump shortly after load
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
