
-- load httppost function
package.path = package.path .. ";../util/?.lua"

local httppost = require("httppost")



function odlAddFlowDriver (params, mo, ap)
  -- assemble resource path with
  -- DPID, table-id and flow-id
  -- here ap is from APMap
  local apiap = string.gsub(ap,
      "<DPID>", params[1]):gsub(
      "<TABID>", params[2]):gsub(
      "<FLID>", params[3])
    local ret = httppost(
    -- assemble point of access
    string.format("http://%s:%d/%s",
      mo.ip,
      mo.sport,
      apiap),
      param[4], -- body
      mo.cred.user, -- auth user
      mo.cred.passw) -- auth passw

  -- check HTTP return code
  -- if 200 or 201 then return true
  -- otherwise false + error response
  return ret:match("201 Created")
         or ret:match("200 OK")
         or false, ret
end

return odlAddFlowDriver

