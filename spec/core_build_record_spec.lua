local core = require("acm_core")
local sample = require("fixtures.onsave_sample")

describe("build_record", function()
  local rec = core.build_record(sample, {
    klei_id = "KU_a", name = "Nick", prefab = "wilson",
    days_survived = 23.4, last_seen_irl = 1718000000,
    title_of = function(c, n) return c .. ":" .. n end,
  })

  it("copies identity + days", function()
    assert.are.equal("KU_a", rec.klei_id)
    assert.are.equal("Nick", rec.name)
    assert.are.equal("wilson", rec.prefab)
    assert.are.equal(23.4, rec.days_survived)
    assert.are.equal(1718000000, rec.last_seen_irl)
  end)
  it("keys achievements by Category/name and ignores counters", function()
    assert.is_table(rec.achievements["Boss/deerclops"])
    assert.is_table(rec.achievements["Time/firstnight"])
    assert.is_nil(rec.achievements["numKilledPig"])
  end)
  it("captures day, unlocked_irl, and title", function()
    local a = rec.achievements["Boss/deerclops"]
    assert.are.equal(12, a.day)
    assert.are.equal(1717900000, a.unlocked_irl)
    assert.are.equal("Boss:deerclops", a.title)
  end)
  it("defaults days_survived to 0 when missing", function()
    local r = core.build_record({}, { klei_id = "x", name = "y" })
    assert.are.equal(0, r.days_survived)
  end)
end)
