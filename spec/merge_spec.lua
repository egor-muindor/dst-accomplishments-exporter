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

  it("merges only the current session's partials (ignores stale old-world shards)", function()
    local dir = TMP .. "/acm_mixed"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    write(dir .. "/acm_export_shard_old.json", { schema_version = 1, cluster_session = "OLD", shard_id = "old",
      generated_irl = 1000, players = { KU_old = { klei_id = "KU_old", name = "Old",
        days_survived = 50, last_seen_irl = 1000, achievements = {} } } })
    write(dir .. "/acm_export_shard_new.json", { schema_version = 1, cluster_session = "NEW", shard_id = "new",
      generated_irl = 2000, players = { KU_new = { klei_id = "KU_new", name = "New",
        days_survived = 1, last_seen_irl = 2000, achievements = {} } } })
    local res = merge.run({ root = dir, out = out })
    assert.are.equal("NEW", res.cluster_session)
    assert.is_table(res.players.KU_new)
    assert.is_nil(res.players.KU_old)
    assert.are.equal(1, res.player_count)
  end)

  it("parses real DST partials carrying the KLEI persistent-string header", function()
    -- TheSim:SetPersistentString writes the payload on disk prefixed with a
    -- "KLEI     1 " header (4-char magic, version, padding). The merger reads the
    -- raw file, so it must strip that header before JSON-decoding it.
    local dir = TMP .. "/acm_klei"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    local payload = dkjson.encode({ schema_version = 1, cluster_session = "S1", shard_id = "0",
      generated_irl = 2000, players = { KU_a = { klei_id = "KU_a", name = "A",
        days_survived = 3, last_seen_irl = 2000, achievements = {} } } })
    local f = assert(io.open(dir .. "/acm_export_shard_0.json", "w"))
    f:write("KLEI     1 " .. payload); f:close()
    local res = merge.run({ root = dir, out = out })
    assert.are.equal("S1", res.cluster_session)
    assert.are.equal(1, res.player_count)
    assert.is_table(res.players.KU_a)
  end)

  it("skips malformed partials (torn JSON and wrong-typed fields) without crashing", function()
    local dir = TMP .. "/acm_torn"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    write(dir .. "/acm_export_shard_1.json", { schema_version = 1, cluster_session = "S1", shard_id = "1",
      generated_irl = 1000, players = { KU_a = { klei_id = "KU_a", name = "A",
        days_survived = 1, last_seen_irl = 1000, achievements = {} } } })
    local f = assert(io.open(dir .. "/acm_export_shard_2.json", "w")); f:write('{ "players": { "KU_b"'); f:close()
    local f2 = assert(io.open(dir .. "/acm_export_shard_3.json", "w"))
    f2:write('{"schema_version":1,"cluster_session":"S1","shard_id":"3","generated_irl":1200,"players":"nope"}')
    f2:close()
    local res = merge.run({ root = dir, out = out })
    assert.are.equal(1, res.player_count)
    assert.is_table(res.players.KU_a)
  end)

  it("encodes empty players/achievements as JSON objects ({}) not arrays ([])", function()
    local dir = TMP .. "/acm_obj"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    merge.run({ root = dir, out = out })
    local fh = assert(io.open(out)); local raw = fh:read("*a"); fh:close()
    assert.is_truthy(raw:find('"players"%s*:%s*{%s*}'))
    assert.is_truthy(raw:find('"cluster_session"'))
    write(out, { schema_version = 1, cluster_session = "S1", generated_irl = 1, player_count = 1,
      players = { KU_z = { klei_id = "KU_z", name = "Z", days_survived = 1, last_seen_irl = 1, online = true, achievements = {} } } })
    write(dir .. "/acm_export_shard_1.json", { schema_version = 1, cluster_session = "S1", shard_id = "1",
      generated_irl = 2000, players = { KU_a = { klei_id = "KU_a", name = "A",
        days_survived = 1, last_seen_irl = 2000, achievements = {} } } })
    merge.run({ root = dir, out = out })
    local fh2 = assert(io.open(out)); local raw2 = fh2:read("*a"); fh2:close()
    assert.is_nil(raw2:find("%[%]"))
  end)

  it("carries catalog/catalog_count and unions per-player progress (max)", function()
    local out = TMP .. "/acm_unified_cat.json"
    os.remove(out)
    local res = merge.run({ root = "spec/fixtures/partials", out = out, prev = out })
    -- catalog carried from the only partial that has one (shard 1)
    assert.are.equal(2, res.catalog_count)
    assert.are.equal(100, res.catalog["Combat/hound"].goal)
    -- progress unioned by max across shards (47 vs 60)
    assert.are.equal(60, res.players.KU_a.progress["Combat/hound"])
  end)

  it("encodes catalog and progress as JSON objects, never []", function()
    local out = TMP .. "/acm_unified_obj2.json"
    os.remove(out)
    merge.run({ root = "spec/fixtures/partials", out = out, prev = out })
    local fh = assert(io.open(out)); local raw = fh:read("*a"); fh:close()
    assert.is_truthy(raw:find('"catalog"%s*:%s*{'))
    assert.is_truthy(raw:find('"progress"%s*:%s*{'))
    assert.is_nil(raw:find('"catalog"%s*:%s*%['))
    assert.is_nil(raw:find('"progress"%s*:%s*%['))
  end)

  it("uses the catalog from the newest current-session partial (newest wins)", function()
    local dir = TMP .. "/acm_catnew"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    write(dir .. "/acm_export_shard_1.json", { schema_version = 2, cluster_session = "S1", shard_id = "1",
      generated_irl = 1000, catalog_count = 1, catalog = { ["Combat/hound"] = { title = "Old", goal = 50 } },
      players = { KU_a = { klei_id = "KU_a", name = "A", days_survived = 1, last_seen_irl = 1000, achievements = {} } } })
    write(dir .. "/acm_export_shard_2.json", { schema_version = 2, cluster_session = "S1", shard_id = "2",
      generated_irl = 2000, catalog_count = 1, catalog = { ["Combat/hound"] = { title = "New", goal = 100 } },
      players = { KU_b = { klei_id = "KU_b", name = "B", days_survived = 1, last_seen_irl = 2000, achievements = {} } } })
    local res = merge.run({ root = dir, out = out })
    assert.are.equal(100, res.catalog["Combat/hound"].goal)   -- newest (shard 2) wins
    assert.are.equal("New", res.catalog["Combat/hound"].title)
  end)

  it("falls back to the previous output's catalog (same session) when no partial has one", function()
    local dir = TMP .. "/acm_catfb"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    write(out, { schema_version = 2, cluster_session = "S1", generated_irl = 1, player_count = 0,
      catalog_count = 1, catalog = { ["Time/twenty"] = { title = "Not Dead Yet", goal = 20 } }, players = {} })
    write(dir .. "/acm_export_shard_1.json", { schema_version = 2, cluster_session = "S1", shard_id = "1",
      generated_irl = 2000,
      players = { KU_a = { klei_id = "KU_a", name = "A", days_survived = 1, last_seen_irl = 2000, achievements = {} } } })
    local res = merge.run({ root = dir, out = out, prev = out })
    assert.are.equal(20, res.catalog["Time/twenty"].goal)
    assert.are.equal(1, res.catalog_count)
  end)

  it("drops a stale catalog on session change (does not carry across world regen)", function()
    local dir = TMP .. "/acm_catregen"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    write(out, { schema_version = 2, cluster_session = "OLD", generated_irl = 1, player_count = 0,
      catalog_count = 1, catalog = { ["Combat/hound"] = { title = "Stale", goal = 100 } }, players = {} })
    write(dir .. "/acm_export_shard_1.json", { schema_version = 2, cluster_session = "NEW", shard_id = "1",
      generated_irl = 2000,
      players = { KU_a = { klei_id = "KU_a", name = "A", days_survived = 1, last_seen_irl = 2000, achievements = {} } } })
    local res = merge.run({ root = dir, out = out, prev = out })
    assert.are.equal("NEW", res.cluster_session)
    assert.is_nil(res.catalog)   -- old-session catalog not carried
  end)

  it("recomputes catalog_count when a partial omits it", function()
    local dir = TMP .. "/acm_catcount"; os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)
    local out = dir .. "/acm_export.json"
    write(dir .. "/acm_export_shard_1.json", { schema_version = 2, cluster_session = "S1", shard_id = "1",
      generated_irl = 1000, catalog = { ["Combat/hound"] = { title = "H", goal = 100 }, ["Time/twenty"] = { title = "T", goal = 20 } },
      players = { KU_a = { klei_id = "KU_a", name = "A", days_survived = 1, last_seen_irl = 2000, achievements = {} } } })
    local res = merge.run({ root = dir, out = out })
    assert.are.equal(2, res.catalog_count)   -- recomputed from the 2-entry catalog
  end)
end)
