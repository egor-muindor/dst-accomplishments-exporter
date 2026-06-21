local M = {}

function M.parse_completed_key(varname)
  local rest = string.match(varname, "^completed_(.+)$")
  if not rest then return nil end
  local cat, name = string.match(rest, "^([^_]+)_(.+)$")
  if not cat then return nil end
  return cat, name
end

return M
