local dkjson = require("dkjson")
local merge = require("acm_merge")

local TMP = os.getenv("TMPDIR") or "/tmp"
local function write(path, tbl)
  local f = assert(io.open(path, "w")); f:write(dkjson.encode(tbl)); f:close()
end
local function read(path)
  local f = assert(io.open(path, "r")); local s = f:read("*a"); f:close()
  return dkjson.decode(s)
end

describe("acm_merge.run", function()
  it("merges shard partials into one unified file", function()
    local out = TMP .. "/acm_unified_test.json"
    os.remove(out)
    local res = merge.run({ root = "spec/fixtures/partials", out = out, prev = out })
    assert.are.equal(2, res.player_count)
    assert.are.equal(9, res.players.KU_a.days_survived)          -- max across shards
    assert.is_table(res.players.KU_a.achievements["Boss/deerclops"])
    assert.is_table(res.players.KU_a.achievements["Time/firstnight"])
    assert.is_true(res.players.KU_a.online)
    local disk = read(out)
    assert.are.equal("S1", disk.cluster_session)
  end)

  it("carries offline players forward from the previous unified output", function()
    local dir = TMP .. "/acm_carry"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    -- seed previous output with an offline player not present in any partial
    write(out, { schema_version = 1, cluster_session = "S1", generated_irl = 1,
      player_count = 1, players = { KU_z = { klei_id = "KU_z", name = "Zoe",
        days_survived = 99, last_seen_irl = 1, online = true, achievements = {} } } })
    -- one current partial (different player)
    write(dir .. "/acm_export_shard_1.json", { schema_version = 1, cluster_session = "S1",
      shard_id = "1", generated_irl = 2000,
      players = { KU_a = { klei_id = "KU_a", name = "Al", prefab = "wilson",
        days_survived = 1, last_seen_irl = 2000, achievements = {} } } })
    local res = merge.run({ root = dir, out = out, prev = out })
    assert.is_false(res.players.KU_z.online)   -- retained but offline
    assert.is_true(res.players.KU_a.online)
    assert.are.equal(2, res.player_count)
  end)

  it("resets the leaderboard when the session changes (world regen)", function()
    local dir = TMP .. "/acm_regen"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    write(out, { schema_version = 1, cluster_session = "OLD", generated_irl = 1,
      player_count = 1, players = { KU_z = { klei_id = "KU_z", achievements = {} } } })
    write(dir .. "/acm_export_shard_1.json", { schema_version = 1, cluster_session = "NEW",
      shard_id = "1", generated_irl = 2000,
      players = { KU_a = { klei_id = "KU_a", name = "Al", days_survived = 1,
        last_seen_irl = 2000, achievements = {} } } })
    local res = merge.run({ root = dir, out = out, prev = out })
    assert.is_nil(res.players.KU_z)            -- old session wiped
    assert.is_table(res.players.KU_a)
    assert.are.equal("NEW", res.cluster_session)
  end)
end)
