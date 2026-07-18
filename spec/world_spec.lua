local world = require("acm_world")

local function iter_of(names)
  local i = 0
  return function()
    i = i + 1
    return names[i]
  end
end

local function fake_ctx(writes)
  return {
    shard_id = "1",
    is_master = true,
    world_prefabs = { "Dragonfly", "bearger", "reeds" },
    get_session = function() return "SESS" end,
    get_worldstate = function() return { season = "winter", cycles = 213, phase = "day" } end,
    iterate_prefabs = function() return iter_of({ "dragonfly", "reeds", "spider", "reeds" }) end,
    now = function() return 4242 end,
    write = function(fn, data) writes[#writes + 1] = { fn = fn, data = data } end,
    json_encode = function(t) return t end, -- pass-through so we can assert on the table
  }
end

describe("acm_world", function()
  describe("filename", function()
    it("is derived from the shard id", function()
      assert.are.equal("acm_world_shard_1.json", world.filename({ shard_id = "1" }))
      assert.are.equal("acm_world_shard_Caves.json", world.filename({ shard_id = "Caves" }))
    end)

    it("stringifies a numeric shard id", function()
      assert.are.equal("acm_world_shard_2.json", world.filename({ shard_id = 2 }))
    end)
  end)

  describe("is_enabled", function()
    it("is true for a table with at least one entry", function()
      assert.is_true(world.is_enabled({ "dragonfly" }))
    end)

    it("is false for false, nil, non-tables and the empty table", function()
      assert.is_false(world.is_enabled(false))
      assert.is_false(world.is_enabled(nil))
      assert.is_false(world.is_enabled("dragonfly"))
      assert.is_false(world.is_enabled(42))
      assert.is_false(world.is_enabled({}))
    end)

    it("is false when no entry is a string (counts would encode as [])", function()
      assert.is_false(world.is_enabled({ 42 }))
      assert.is_false(world.is_enabled({ { "dragonfly" }, { "bearger" } }))
    end)

    it("is true when a hole precedes a valid entry (unquoted-name typo)", function()
      -- modoverrides typo `{ dragonfly, "bearger" }`: the unquoted name is nil
      assert.is_true(world.is_enabled({ nil, "bearger" }))
    end)
  end)

  describe("count_prefabs", function()
    it("counts occurrences of configured prefabs", function()
      local counts = world.count_prefabs(
        iter_of({ "reeds", "dragonfly", "reeds", "reeds" }),
        { "dragonfly", "reeds" })
      assert.are.equal(1, counts.dragonfly)
      assert.are.equal(3, counts.reeds)
    end)

    it("includes every configured prefab, zeros included", function()
      local counts = world.count_prefabs(iter_of({}), { "dragonfly", "bearger" })
      assert.are.equal(0, counts.dragonfly)
      assert.are.equal(0, counts.bearger)
    end)

    it("ignores prefabs that are not configured", function()
      local counts = world.count_prefabs(iter_of({ "spider", "spider" }), { "reeds" })
      assert.is_nil(counts.spider)
      assert.are.equal(0, counts.reeds)
    end)

    it("normalizes configured names to lowercase", function()
      local counts = world.count_prefabs(iter_of({ "dragonfly" }), { "DragonFly" })
      assert.are.equal(1, counts.dragonfly)
      assert.is_nil(counts.DragonFly)
    end)

    it("keeps entries after a hole and drops non-strings (agrees with is_enabled)", function()
      local counts = world.count_prefabs(iter_of({ "bearger" }), { nil, "bearger" })
      assert.are.equal(1, counts.bearger)
      counts = world.count_prefabs(iter_of({}), { 42, "reeds" })
      assert.are.equal(0, counts.reeds)
      assert.is_nil(counts[42])
    end)
  end)

  describe("snapshot", function()
    it("has session, shard, is_master, generated_irl, worldstate and counts", function()
      local snap = world.snapshot(fake_ctx({}))
      assert.are.equal(1, snap.schema_version)
      assert.are.equal("SESS", snap.cluster_session)
      assert.are.equal("1", snap.shard_id)
      assert.is_true(snap.is_master)
      assert.are.equal(4242, snap.generated_irl)
      assert.are.same({ season = "winter", cycles = 213, phase = "day" }, snap.worldstate)
      assert.are.same({ dragonfly = 1, bearger = 0, reeds = 2 }, snap.counts)
    end)

    it("stringifies the shard id and keeps is_master false", function()
      local ctx = fake_ctx({})
      ctx.shard_id = 2
      ctx.is_master = false
      local snap = world.snapshot(ctx)
      assert.are.equal("2", snap.shard_id)
      assert.is_false(snap.is_master)
    end)
  end)

  describe("write_snapshot", function()
    it("writes one shard-named file with the encoded snapshot and returns it", function()
      local writes = {}
      local snap = world.write_snapshot(fake_ctx(writes))
      assert.are.equal(1, #writes)
      assert.are.equal("acm_world_shard_1.json", writes[1].fn)
      assert.are.equal(snap, writes[1].data)
      assert.are.equal(0, snap.counts.bearger)
    end)
  end)
end)
