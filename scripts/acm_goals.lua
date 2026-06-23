-- Counter-achievement goal (denominator) table for the Accomplishments mod.
--
-- Provenance: extracted from "Accomplishments" (DST Workshop 2843097516),
--   scripts/achievements/*.lua `Check` thresholds + kaachievement_utils/constants.lua,
--   on 2026-06-23. Keys are "Category/name"; values are the "Y" in an X/Y fraction.
--
-- Included: only achievements whose Check is `value >= N` with N > 1 (true counters).
-- Excluded by design (NOT bugs):
--   * one-shots (`> 0`, `>= 1`, AMOUNT_TINY = 1)  -> goal defaults to 1 at runtime;
--   * boolean flags (e.g. exploration biomes)     -> goal defaults to 1 at runtime;
--   * meta achievements (Record returns "X/Y")    -> goal parsed live via Record({}).
--
-- REFRESH THIS TABLE when the base mod changes a Check threshold or adds a counter
-- achievement. Cross-check against ACHIEVEMENTS_LIST.md (in the research repo root,
-- outside this mod folder). Missing/stale entries are not
-- fatal: an unknown counter simply falls back to goal = 1.
return {
  -- Combat
  ["Combat/hound"]            = 100, -- AMOUNT_HUGE
  ["Combat/worm"]            = 50,  -- AMOUNT_LARGE
  ["Combat/pigman"]          = 40,  -- AMOUNT_MEDLARGE
  ["Combat/bunnyman"]        = 40,  -- AMOUNT_MEDLARGE
  ["Combat/krampus"]         = 10,  -- AMOUNT_MEDSMALL
  ["Combat/rocky"]           = 5,   -- AMOUNT_SMALL
  ["Combat/brightshadestaff"] = 20, -- AMOUNT_MED
  ["Combat/brightshadepipe"] = 20,  -- AMOUNT_MED
  ["Combat/shadowscythe"]    = 20,  -- AMOUNT_MED
  ["Combat/shadowboomerang"] = 20,  -- AMOUNT_MED
  -- Time
  ["Time/twenty"]            = 20,   -- AMOUNT_MED
  ["Time/thirtyfive"]        = 35,   -- inline
  ["Time/fiftyfive"]         = 55,   -- inline
  ["Time/onehundred"]        = 100,  -- AMOUNT_HUGE
  ["Time/fivehundred"]       = 500,  -- AMOUNT_MEDHUGE
  ["Time/onethousand"]       = 1000, -- AMOUNT_SUPERHUGE
  ["Time/sailor2"]           = 3,    -- inline (GetWaterDays >= 3)
  -- Hunt
  ["Hunt/generic"]           = 10,   -- AMOUNT_MEDSMALL
  ["Hunt/greathunter"]       = 20,   -- AMOUNT_MED
  -- Farming
  ["Farming/tilling"]        = 200,  -- inline
  ["Farming/tilling2"]       = 400,  -- inline
  -- Activity
  ["Activity/faileddish"]    = 10,   -- AMOUNT_MEDSMALL
  ["Activity/jimbo"]         = 600,  -- ACTIVITY.JIMBO_MINIGAME_WIN_SCORE
  ["Activity/mastertrader"]  = 10,   -- ACTIVITY.NUM_TRADED_WITH_WANDERING_TRADER
  ["Activity/pigfollower"]   = 6,    -- ACTIVITY.NUM_PIG_FOLLOWERS
  ["Activity/bunnyfollower"] = 6,    -- ACTIVITY.NUM_BUNNY_FOLLOWERS
  ["Activity/lobsterfollower"] = 4,  -- ACTIVITY.NUM_ROCKY_FOLLOWERS
  ["Activity/tumbleweed"]    = 20,   -- inline
  ["Activity/antlionhat"]    = 100,  -- AMOUNT_HUGE
  -- Social
  ["Social/tendeath"]        = 10,   -- AMOUNT_MEDSMALL
  ["Social/sixplayers"]      = 6,    -- inline
  ["Social/samecharacter"]   = 3,    -- inline
  ["Social/soakplayer"]      = 10,   -- AMOUNT_MEDSMALL
  -- Character
  ["Character/willow1"]      = 40,   -- AMOUNT_MEDLARGE
  ["Character/wolfgang2"]    = 40,   -- AMOUNT_MEDLARGE
  ["Character/wendy1"]       = 10,   -- AMOUNT_MEDSMALL
  ["Character/wendy2"]       = 40,   -- AMOUNT_MEDLARGE
  ["Character/wickerbottom1"] = 40,  -- AMOUNT_MEDLARGE
  ["Character/woodie1"]      = 500,  -- AMOUNT_MEDHUGE
  ["Character/woodie2"]      = 40,   -- AMOUNT_MEDLARGE
  ["Character/waxwell1"]     = 10,   -- AMOUNT_MEDSMALL
  ["Character/waxwell2"]     = 40,   -- AMOUNT_MEDLARGE
  ["Character/wathgrithr1"]  = 20,   -- AMOUNT_MED
  ["Character/wathgrithr2"]  = 3,    -- inline
  ["Character/winona1"]      = 40,   -- AMOUNT_MEDLARGE
  ["Character/winona2"]      = 5,    -- AMOUNT_SMALL
  ["Character/wortox2"]      = 1000, -- AMOUNT_SUPERHUGE
  ["Character/wormwood1"]    = 100,  -- AMOUNT_HUGE
  ["Character/walter1"]      = 40,   -- AMOUNT_MEDLARGE
  ["Character/wanda2"]       = 40,   -- AMOUNT_MEDLARGE
  ["Character/wonkey1"]      = 40,   -- AMOUNT_MEDLARGE
}
