

currentAM = {
  --access class free: always returns true
  free = function (u,m,f) return true end,

  --returns true if user and MO share
  --at least one common domain
  inDomain = function (u,m,f)
    local domains = m:getDomains()
    for _,d in ipairs(domains) do
      if (d:checkUser(u)) then
        return true
      end
    end
    return false
  end
}

return currentAM

