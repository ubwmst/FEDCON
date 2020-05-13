
-- load httppost function
package.path = package.path .. ";../util/?.lua"

local httppost = require("httppost")



function oneVMBootDriver (params, mo, ap)
  
  -- assemble RPC call
  local xmlreq = string.format([[<?xml version="1.0" ?><methodCall><methodName>one.vm.action</methodName><params><param><value><string>%s:%s</string></value></param><param><value><string>resume</string></value></param><param><value><i4>%s</i4></value></param></params>
  
  ]],
  mo.cred.user,
  mo.cred.passw,
  params[1])

  -- execute RPC call
  -- httppost is a custom http-post function
  -- based on lua's socket.http library
  local ret = httppost(
    -- assemble point of access
    string.format("http://%s:%d/%s",
      mo.ip,
      mo.sport,
      ap), --here ap is mo.apiap
    xmlreq,
    nil, nil, "text/xml; charset=utf-8")
    
  -- Check if error occured, if so return
  -- false and error message response
  -- otherwise true
  return ret and not ret:match("Error") or false, ret
end

return oneVMBootDriver
