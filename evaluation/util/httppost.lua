
http = require("socket.http")
mime = require("mime")
local ltn12 = require("ltn12")

function httppost(url, body, username, password, contenttype)

  print(url, body)
  assert(url and body, "URL and Body must be given!")
  local auth = (username and password) and string.format("%s:%s", username, password) or nil
  local httpresponse = {}
  local r, c, rh, rs = http.request {
    url = url,
    method = "POST",
    sink = ltn12.sink.table(httpresponse),
    source = ltn12.source.string(body),
    headers = {
      ["authentication"] = auth and ("Basic " .. (mime.b64(auth))) or nil,
      ["Content-Length"] = #body,
      ["Content-Type"] = contenttype or nil,
      ["Connection"] = "close",
      ["Accept-Encoding"] = "identity",
      ["Accept"] = "*/*",
      ["Host"] = "localhost:2633",
      -- ["TE"] = "",
    }
  }
  if r then --success
    -- return response code, headers and body
    return string.format("%s,%s\n\n%s",c,rh,table.concat(httpresponse))
  else -- error
    return c, rh -- error code, headers
  end
end

return httppost

