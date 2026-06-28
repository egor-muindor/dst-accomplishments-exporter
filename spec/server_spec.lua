local server = require("acm_server")

local function fake_ctx(writes)
  return {
    shard_id = "2",
    get_session = function() return "SESS" end,
    now = function() return 4242 end,
    title_of = function(c, n) return c .. ":" .. n end,
    json_encode = function(t) return t end, -- pass-through so we can assert on the table
    write = function(fn, data) writes[#writes + 1] = { fn = fn, data = data } end,
    get_players = function()
      return {
        { klei_id = "KU_a", name = "A", prefab = "wilson", days_survived = 3,
          on_save = { completed_Boss_deerclops = { cycles = 5, irl = 99 }, numKilledPig = 2 },
          progress = { ["Combat/hound"] = 47 } },
      }
    end,
    get_catalog = function()
      return { ["Combat/hound"] = { title = "The Houndmaster", goal = 100 } }
    end,
  }
end

describe("acm_server", function()
  it("writes a shard partial named by shard id", function()
    local writes = {}
    server.write_snapshot(fake_ctx(writes))
    assert.are.equal(1, #writes)
    assert.are.equal("acm_export_shard_2.json", writes[1].fn)
  end)

  it("snapshot has session, shard, generated_irl and online player records", function()
    local writes = {}
    local snap = server.write_snapshot(fake_ctx(writes))
    assert.are.equal("SESS", snap.cluster_session)
    assert.are.equal("2", snap.shard_id)
    assert.are.equal(4242, snap.generated_irl)
    local p = snap.players.KU_a
    assert.are.equal("A", p.name)
    assert.are.equal(3, p.days_survived)
    assert.are.equal(4242, p.last_seen_irl)
    assert.is_table(p.achievements["Boss/deerclops"])
    assert.is_nil(p.achievements["numKilledPig"])
  end)

  it("writes catalog, catalog_count and per-player progress at schema v2", function()
    local writes = {}
    local snap = server.write_snapshot(fake_ctx(writes))
    assert.are.equal(2, snap.schema_version)
    assert.are.equal(1, snap.catalog_count)
    assert.are.equal(100, snap.catalog["Combat/hound"].goal)
    assert.are.equal(47, snap.players.KU_a.progress["Combat/hound"])
  end)

  it("tolerates a ctx without get_catalog: empty catalog, count 0", function()
    local writes = {}
    local ctx = fake_ctx(writes)
    ctx.get_catalog = nil
    local snap = server.write_snapshot(ctx)
    assert.are.equal(0, snap.catalog_count)
    assert.are.same({}, snap.catalog)
  end)

  it("omits an empty per-player progress map", function()
    local writes = {}
    local ctx = fake_ctx(writes)
    ctx.get_players = function()
      return {
        { klei_id = "KU_a", name = "A", prefab = "wilson", days_survived = 3,
          on_save = { completed_Boss_deerclops = { cycles = 5, irl = 99 } }, progress = {} },
      }
    end
    local snap = server.write_snapshot(ctx)
    assert.is_nil(snap.players.KU_a.progress)
  end)
end)
