local core = require("acm_core")

local function snap(shard, irl, players)
  return { schema_version = 1, cluster_session = "S1", shard_id = shard,
           generated_irl = irl, players = players }
end
local function rec(uid, days, irl, ach, prog)
  return { klei_id = uid, name = uid, prefab = "wilson",
           days_survived = days, last_seen_irl = irl, achievements = ach or {},
           progress = prog }
end

describe("merge_snapshot / mark_all_offline", function()
  it("adds new players as online with current_shard", function()
    local db = {}
    core.merge_snapshot(db, snap("1", 100, { KU_a = rec("KU_a", 5, 100, { ["Boss/deerclops"] = { day = 5, unlocked_irl = 100 } }) }))
    assert.is_true(db.KU_a.online)
    assert.are.equal("1", db.KU_a.current_shard)
    assert.is_table(db.KU_a.achievements["Boss/deerclops"])
  end)

  it("unions achievements and takes max days across shards", function()
    local db = {}
    core.merge_snapshot(db, snap("1", 100, { KU_a = rec("KU_a", 5, 100, { ["Boss/deerclops"] = { day = 5, unlocked_irl = 100 } }) }))
    core.merge_snapshot(db, snap("2", 120, { KU_a = rec("KU_a", 9, 120, { ["Time/firstnight"] = { day = 1, unlocked_irl = 90 } }) }))
    assert.are.equal(9, db.KU_a.days_survived)
    assert.are.equal("2", db.KU_a.current_shard)
    assert.is_table(db.KU_a.achievements["Boss/deerclops"])
    assert.is_table(db.KU_a.achievements["Time/firstnight"])
  end)

  it("is idempotent", function()
    local db = {}
    local s = snap("1", 100, { KU_a = rec("KU_a", 5, 100, { ["Boss/deerclops"] = { day = 5, unlocked_irl = 100 } }) })
    core.merge_snapshot(db, s)
    core.merge_snapshot(db, s)
    local n = 0; for _ in pairs(db.KU_a.achievements) do n = n + 1 end
    assert.are.equal(1, n)
  end)

  it("mark_all_offline flips online to false and clears current_shard", function()
    local db = {}
    core.merge_snapshot(db, snap("1", 100, { KU_a = rec("KU_a", 5, 100) }))
    assert.are.equal("1", db.KU_a.current_shard)
    core.mark_all_offline(db)
    assert.is_false(db.KU_a.online)
    assert.is_nil(db.KU_a.current_shard)
  end)
  it("keeps the earliest unlocked_irl on conflict (re-merge is a no-op)", function()
    local db = {}
    core.merge_snapshot(db, snap("1", 100, { KU_a = rec("KU_a", 5, 100, { ["Boss/deerclops"] = { day = 5, unlocked_irl = 200 } }) }))
    core.merge_snapshot(db, snap("2", 120, { KU_a = rec("KU_a", 5, 120, { ["Boss/deerclops"] = { day = 3, unlocked_irl = 150 } }) }))
    assert.are.equal(150, db.KU_a.achievements["Boss/deerclops"].unlocked_irl)
    core.merge_snapshot(db, snap("1", 130, { KU_a = rec("KU_a", 5, 130, { ["Boss/deerclops"] = { day = 9, unlocked_irl = 300 } }) }))
    assert.are.equal(150, db.KU_a.achievements["Boss/deerclops"].unlocked_irl)
  end)
  it("takes the freshest last_seen_irl across shards", function()
    local db = {}
    core.merge_snapshot(db, snap("1", 100, { KU_a = rec("KU_a", 5, 100) }))
    core.merge_snapshot(db, snap("2", 120, { KU_a = rec("KU_a", 5, 120) }))
    assert.are.equal(120, db.KU_a.last_seen_irl)
  end)

  it("unions progress across shards taking the max numerator", function()
    local db = {}
    core.merge_snapshot(db, snap("1", 100, { KU_a = rec("KU_a", 5, 100, {},
      { ["Combat/hound"] = 47, ["Time/twenty"] = 13 }) }))
    core.merge_snapshot(db, snap("2", 120, { KU_a = rec("KU_a", 5, 120, {},
      { ["Combat/hound"] = 60 }) }))
    assert.are.equal(60, db.KU_a.progress["Combat/hound"])
    assert.are.equal(13, db.KU_a.progress["Time/twenty"])
    -- reverse order: a later, SMALLER numerator must not overwrite the larger one
    core.merge_snapshot(db, snap("3", 130, { KU_a = rec("KU_a", 5, 130, {},
      { ["Combat/hound"] = 50 }) }))
    assert.are.equal(60, db.KU_a.progress["Combat/hound"])
  end)

  it("drops a completed progress key while keeping other in-progress keys (completed wins)", function()
    local db = {}
    core.merge_snapshot(db, snap("1", 100, { KU_a = rec("KU_a", 5, 100, {},
      { ["Combat/hound"] = 99, ["Time/twenty"] = 5 }) }))
    core.merge_snapshot(db, snap("2", 120, { KU_a = rec("KU_a", 5, 120,
      { ["Combat/hound"] = { day = 7, unlocked_irl = 110 } },
      { ["Combat/hound"] = 100, ["Time/twenty"] = 8 }) }))
    assert.is_table(db.KU_a.achievements["Combat/hound"])
    assert.is_nil(db.KU_a.progress["Combat/hound"])      -- completed -> dropped (map still non-nil)
    assert.are.equal(8, db.KU_a.progress["Time/twenty"]) -- still in progress -> max kept
  end)

  it("omits an empty progress map entirely, idempotently across re-merge", function()
    local db = {}
    local s = snap("1", 100, { KU_a = rec("KU_a", 5, 100,
      { ["Combat/hound"] = { day = 7, unlocked_irl = 110 } }, { ["Combat/hound"] = 100 }) })
    core.merge_snapshot(db, s)
    assert.is_nil(db.KU_a.progress)
    core.merge_snapshot(db, s)         -- re-merge a snapshot whose only progress key was pruned
    assert.is_nil(db.KU_a.progress)
  end)

  it("re-merging identical progress is idempotent", function()
    local db = {}
    local s = snap("1", 100, { KU_a = rec("KU_a", 5, 100, {}, { ["Combat/hound"] = 47 }) })
    core.merge_snapshot(db, s)
    core.merge_snapshot(db, s)
    assert.are.equal(47, db.KU_a.progress["Combat/hound"])
  end)
end)
