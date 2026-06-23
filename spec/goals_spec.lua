local goals = require("acm_goals")
local core = require("acm_core")

describe("acm_goals", function()
  it("pins known counter denominators across categories", function()
    assert.are.equal(100, goals["Combat/hound"])
    assert.are.equal(50, goals["Combat/worm"])
    assert.are.equal(20, goals["Time/twenty"])
    assert.are.equal(1000, goals["Time/onethousand"])
    assert.are.equal(10, goals["Hunt/generic"])
    assert.are.equal(200, goals["Farming/tilling"])
    assert.are.equal(600, goals["Activity/jimbo"])
    assert.are.equal(6, goals["Social/sixplayers"])
    assert.are.equal(1000, goals["Character/wortox2"])
  end)

  it("omits one-shot / boolean / meta achievements (default goal 1 at runtime)", function()
    assert.is_nil(goals["Combat/ghost"])        -- AMOUNT_TINY (1) -> one-shot
    assert.is_nil(goals["Time/firstnight"])     -- > 0 -> one-shot
    assert.is_nil(goals["Boss/deerclops"])      -- > 0 -> one-shot
    assert.is_nil(goals["Mastery/allcombat"])   -- meta "X/Y" -> runtime
    assert.is_nil(goals["Exploration/cavesbiome"]) -- boolean flag
  end)

  it("every key is a non-empty Category/name and every goal an integer > 1", function()
    for id, goal in pairs(goals) do
      local cat, name = core.parse_completed_key("completed_" .. id:gsub("/", "_"))
      assert.is_truthy(cat, "bad id: " .. id)
      assert.is_truthy(name, "bad id: " .. id)
      assert.are.equal("number", type(goal))
      assert.is_true(goal > 1, id .. " goal must be > 1")
      assert.are.equal(goal, math.floor(goal))
    end
  end)
end)
