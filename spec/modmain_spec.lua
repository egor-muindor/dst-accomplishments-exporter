-- Mock-GLOBAL harness (spec §7.2): load the REAL modmain.lua against a fake game
-- environment and assert it (a) is server-only, (b) writes a shard partial for online
-- players on a timer tick, and (c) wraps KaBroadcastAnnounceTrophy to write on unlock
-- while still calling the original. This exercises modmain's _G access + event wiring,
-- which the DI-tested acm_server/acm_core specs do not cover.
local dkjson = require("dkjson")

local function make_env()
  local writes, world_cbs, trophy_calls = {}, {}, {}

  local fake_player = {
    userid = "KU_a", name = "Alice", prefab = "wilson",
    components = {
      kaachievementmanager = {
        numKilledHound = 47, -- live counter: 47/100 -> progress (not yet completed)
        OnSave = function()
          return {
            completed_Boss_deerclops = { cycles = 5, seg = 0.1, irl = 99 },
            numKilledPig = 3, -- counter: must be filtered out of achievements
          }
        end,
      },
      age = { GetAgeInDays = function() return 12 end },
    },
  }

  local GLOBAL = {
    TheNet = { GetIsClient = function() return false end },
    TheShard = { GetShardId = function() return "2" end },
    TheWorld = { net = { components = { shardstate = {
      GetMasterSessionId = function() return "SESS" end,
    } } } },
    AllPlayers = { fake_player },
    os = { time = function() return 4242 end },
    TheSim = { SetPersistentString = function(_, fn, str)
      writes[#writes + 1] = { fn = fn, str = str }
    end },
    json = { encode = function(t) return dkjson.encode(t) end },
    pcall = pcall,
    GetTrophyTitle = function(c, n) return c .. ":" .. n end,
    GetKaAchievementLoader = function()
      return { entries = {
        Combat = { {
          name = "hound",
          Record = function(d) return d and d.numKilledHound end,
          Check  = function(d) return d and d.numKilledHound and d.numKilledHound >= 100 or false end,
        } },
        Activity = { {
          name = "eyebrella", -- boolean one-shot -> goal 1, no progress
          Record = function(d) return d and d.hasEyebrella end,
          Check  = function(d) return d and d.hasEyebrella or false end,
        } },
        Mastery = { {
          name = "allcombat", -- meta: Record({}) -> "n/13"
          Record = function(d) local n = (d and d.completed_Combat_hound) and 1 or 0
                               return string.format("%d/%d", n, 13) end,
          Check  = function(_) return false end,
        } },
      } }
    end,
    KaBroadcastAnnounceTrophy = function(...)
      trophy_calls[#trophy_calls + 1] = { ... }
    end,
  }

  return {
    GLOBAL = GLOBAL, writes = writes, world_cbs = world_cbs,
    trophy_calls = trophy_calls, player = fake_player,
    GetModConfigData = function(name) if name == "interval" then return 30 end end,
    AddPrefabPostInit = function(prefab, fn)
      if prefab == "world" then world_cbs[#world_cbs + 1] = fn end
    end,
  }
end

-- Inject modmain's chunk-scope globals, run the real modmain.lua, restore globals.
local function load_modmain(env)
  local s_glob, s_cfg, s_add, s_print = _G.GLOBAL, _G.GetModConfigData, _G.AddPrefabPostInit, _G.print
  _G.GLOBAL = env.GLOBAL
  _G.GetModConfigData = env.GetModConfigData
  _G.AddPrefabPostInit = env.AddPrefabPostInit
  _G.print = function() end
  local ok, err = pcall(function() assert(loadfile("modmain.lua"))() end)
  _G.GLOBAL, _G.GetModConfigData, _G.AddPrefabPostInit, _G.print = s_glob, s_cfg, s_add, s_print
  assert(ok, err)
end

describe("modmain (mock-GLOBAL harness)", function()
  it("is server-only: returns early on a client, registering nothing", function()
    local env = make_env()
    env.GLOBAL.TheNet.GetIsClient = function() return true end
    load_modmain(env)
    assert.are.equal(0, #env.world_cbs)
    assert.are.equal(0, #env.writes)
  end)

  it("writes a schema-shaped shard partial for online players on a timer tick", function()
    local env = make_env()
    load_modmain(env)
    assert.is_true(#env.world_cbs >= 1)
    local periodic
    local fake_world = {
      DoPeriodicTask = function(_, _interval, fn) periodic = fn end,
      ListenForEvent = function() end,
      DoTaskInTime = function() end,
    }
    for _, cb in ipairs(env.world_cbs) do cb(fake_world) end
    assert.is_function(periodic)
    periodic()
    assert.is_true(#env.writes >= 1)
    local w = env.writes[#env.writes]
    assert.are.equal("acm_export_shard_2.json", w.fn)
    local decoded = dkjson.decode(w.str)
    assert.are.equal("SESS", decoded.cluster_session)
    assert.are.equal("2", decoded.shard_id)
    assert.are.equal(4242, decoded.generated_irl)
    local p = decoded.players.KU_a
    assert.are.equal("Alice", p.name)
    assert.are.equal(12, p.days_survived)
    assert.is_table(p.achievements["Boss/deerclops"])
    assert.is_nil(p.achievements.numKilledPig)
    -- catalog: goal via acm_goals (counter), meta Record({}) parse, and default 1
    assert.are.equal(100, decoded.catalog["Combat/hound"].goal)
    assert.are.equal(13, decoded.catalog["Mastery/allcombat"].goal)
    assert.are.equal(1, decoded.catalog["Activity/eyebrella"].goal)
    assert.are.equal(3, decoded.catalog_count)
    -- progress: only the locked, non-zero counter (47); boolean + zero-meta omitted
    assert.are.equal(47, p.progress["Combat/hound"])
    assert.is_nil(p.progress["Activity/eyebrella"])
    assert.is_nil(p.progress["Mastery/allcombat"])
  end)

  it("wraps KaBroadcastAnnounceTrophy: writes on unlock AND calls the original", function()
    local env = make_env()
    load_modmain(env)
    local before = #env.writes
    env.GLOBAL.KaBroadcastAnnounceTrophy("KU_a", "Boss", "deerclops")
    assert.are.equal(1, #env.trophy_calls) -- original still invoked
    assert.is_true(#env.writes > before)   -- and a fresh write happened
  end)

  it("skips an entry whose Check throws (does not guess progress)", function()
    local env = make_env()
    env.GLOBAL.GetKaAchievementLoader = function()
      return { entries = { Combat = { {
        name = "boom",
        Check = function() error("boom") end,
        Record = function() return 5 end,
      } } } }
    end
    load_modmain(env)
    local periodic
    local fake_world = {
      DoPeriodicTask = function(_, _interval, fn) periodic = fn end,
      ListenForEvent = function() end,
      DoTaskInTime = function() end,
    }
    for _, cb in ipairs(env.world_cbs) do cb(fake_world) end
    periodic()
    local decoded = dkjson.decode(env.writes[#env.writes].str)
    assert.are.equal(1, decoded.catalog["Combat/boom"].goal)          -- catalog still lists it (goal 1)
    assert.is_nil((decoded.players.KU_a.progress or {})["Combat/boom"]) -- progress omitted: status unknown
  end)

  it("survives a throwing GetTrophyTitle and still writes the snapshot", function()
    local env = make_env()
    env.GLOBAL.GetTrophyTitle = function() error("title boom") end
    load_modmain(env)
    local periodic
    local fake_world = {
      DoPeriodicTask = function(_, _interval, fn) periodic = fn end,
      ListenForEvent = function() end,
      DoTaskInTime = function() end,
    }
    for _, cb in ipairs(env.world_cbs) do cb(fake_world) end
    periodic()
    assert.is_true(#env.writes >= 1)  -- snapshot still produced despite the title failure
    local decoded = dkjson.decode(env.writes[#env.writes].str)
    assert.is_table(decoded.players.KU_a.achievements["Boss/deerclops"]) -- achievement recorded (title nil)
  end)
end)
