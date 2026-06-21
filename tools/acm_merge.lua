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
local function read_json(path)
  local s = read_file(path); if not s then return nil end
  local ok, t = pcall(dkjson.decode, s)
  if ok and type(t) == "table" then return t end
  return nil
end
local function list_partials(root)
  local files = {}
  local cmd = 'find "' .. root .. '" -name "acm_export_shard_*.json" -type f 2>/dev/null'
  local p = io.popen(cmd)
  if p then
    for line in p:lines() do files[#files + 1] = line end
    p:close()
  end
  return files
end

function M.parse_args(argv)
  local opts = { root = ".", out = nil, prev = nil }
  local i = 1
  while argv[i] do
    local a = argv[i]
    if a == "--root" then i = i + 1; opts.root = argv[i]
    elseif a == "--out" then i = i + 1; opts.out = argv[i]
    elseif a == "--prev" then i = i + 1; opts.prev = argv[i]
    end
    i = i + 1
  end
  opts.out = opts.out or (opts.root .. "/acm_export.json")
  opts.prev = opts.prev or opts.out
  return opts
end

-- now_fn injectable for testing; defaults to os.time
function M.run(opts, now_fn)
  now_fn = now_fn or os.time
  local prev = read_json(opts.prev)

  local partials = {}
  for _, path in ipairs(list_partials(opts.root)) do
    local t = read_json(path)
    if t and t.players then partials[#partials + 1] = t end
  end

  local cur_session, newest = nil, -1
  for _, pt in ipairs(partials) do
    if (pt.generated_irl or 0) > newest then
      newest = pt.generated_irl or 0
      cur_session = pt.cluster_session
    end
  end
  if not cur_session and prev then cur_session = prev.cluster_session end

  local db = acm_core.select_seed(prev, cur_session)
  acm_core.mark_all_offline(db)

  table.sort(partials, function(a, b) return (a.generated_irl or 0) < (b.generated_irl or 0) end)
  for _, pt in ipairs(partials) do acm_core.merge_snapshot(db, pt) end

  local export = acm_core.build_export(db, { cluster_session = cur_session, generated_irl = now_fn() })
  write_file(opts.out, dkjson.encode(export, { indent = true }))
  return export
end

-- Run as CLI only when invoked directly (not when required by busted).
if arg and arg[0] and arg[0]:match("acm_merge%.lua$") then
  M.run(M.parse_args(arg))
end

return M
