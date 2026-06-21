local acm_core = require("acm_core")
local dkjson = require("dkjson")

local M = {}

local function read_file(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function write_file(path, s)
  local f = assert(io.open(path, "w")); f:write(s); f:close()
end
-- DST's TheSim:SetPersistentString writes the payload on disk prefixed with a
-- "KLEI     1 " persistent-string header (magic + version + padding). Strip it
-- before decoding; a no-op for the merger's own pure-JSON output / fixtures.
local function strip_klei_header(s)
  return (s:gsub("^KLEI%s+%d+%s+", ""))
end
local function read_json(path)
  local s = read_file(path); if not s then return nil end
  s = strip_klei_header(s)
  local ok, t = pcall(dkjson.decode, s)
  if ok and type(t) == "table" then return t end
  return nil
end

-- POSIX single-quote the path so spaces/quotes/metachars are safe in the shell command.
-- (root is operator-supplied via --root, not attacker-controlled, but be robust.)
local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function list_partials(root)
  local files = {}
  local cmd = "find " .. shell_quote(root) .. " -name 'acm_export_shard_*.json' -type f 2>/dev/null"
  local p = io.popen(cmd)
  if p then
    for line in p:lines() do files[#files + 1] = line end
    p:close()
  end
  return files
end

-- dkjson encodes an empty Lua table as []; force object encoding so empty map-like
-- fields (players, achievements) serialize as {} to satisfy the JSON Schema.
local function as_object(t)
  if type(t) == "table" then setmetatable(t, { __jsontype = "object" }) end
  return t
end

local function generated_at(pt)
  return type(pt.generated_irl) == "number" and pt.generated_irl or 0
end

function M.parse_args(argv)
  local opts = { root = ".", out = nil, prev = nil }
  local i = 1
  while argv[i] do
    local a = argv[i]
    if a == "--root" or a == "--out" or a == "--prev" then
      local v = argv[i + 1]
      if v == nil then error("acm_merge: " .. a .. " requires a value") end
      opts[a:sub(3)] = v
      i = i + 2
    else
      error("acm_merge: unknown argument '" .. tostring(a) .. "'")
    end
  end
  return opts
end

-- now_fn injectable for testing; defaults to os.time.
function M.run(opts, now_fn)
  now_fn = now_fn or os.time
  opts.out = opts.out or (opts.root .. "/acm_export.json")
  opts.prev = opts.prev or opts.out
  local prev = read_json(opts.prev)

  -- collect well-formed partials; torn/half-written or wrong-typed files are skipped.
  local partials = {}
  for _, path in ipairs(list_partials(opts.root)) do
    local t = read_json(path)
    if t and type(t.players) == "table" then partials[#partials + 1] = t end
  end

  -- deterministic order: oldest -> newest by generated_irl, ties broken by shard_id.
  table.sort(partials, function(a, b)
    local ga, gb = generated_at(a), generated_at(b)
    if ga ~= gb then return ga < gb end
    return tostring(a.shard_id) < tostring(b.shard_id)
  end)

  -- current session = newest partial's session; fall back to prev when no partials.
  local cur_session = nil
  if #partials > 0 then cur_session = partials[#partials].cluster_session end
  if not cur_session and prev then cur_session = prev.cluster_session end

  local db = acm_core.select_seed(prev, cur_session)
  acm_core.mark_all_offline(db)

  -- merge ONLY the current session's partials: a stale old-world shard (e.g. a shard
  -- left offline across a world regen) must not repopulate a freshly reset leaderboard.
  for _, pt in ipairs(partials) do
    if pt.cluster_session == cur_session then acm_core.merge_snapshot(db, pt) end
  end

  local export = acm_core.build_export(db, { cluster_session = cur_session, generated_irl = now_fn() })
  export.cluster_session = export.cluster_session or dkjson.null
  as_object(export.players)
  for _, p in pairs(export.players) do as_object(p.achievements) end
  write_file(opts.out, dkjson.encode(export, { indent = true }))
  return export
end

-- Run as CLI only when invoked directly (not when required by busted).
if arg and arg[0] and arg[0]:match("acm_merge%.lua$") then
  M.run(M.parse_args(arg))
end

return M
