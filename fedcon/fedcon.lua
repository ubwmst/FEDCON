
--[[
  Defines objects, which can be used to describe MOCs and inheritance relations + defines management structures like domains, users, etc.
  Furthermore describes functions in order to access them

]]
 --local _ENV = require 'std.strict' (_G)


--[[ TODOs
1. Funktion remoteCall ausimplementieren
2. SYNCHRONISIERUNG -- FUTURE WORK

]]

local lsock = require "socket" -- Sockets library
local lsec  = require "ssl" -- TLS library

-- #################### HELPER FUNCTIONS

function multiReturn(tab, last)
  local cur = next(tab or {}, last)
  if cur then
    return cur, multiReturn(tab, cur)
  end
end


function serializeFunctionCallStructure(t)
  local params = "{"
  for i,v in ipairs(t.params) do
    assert(type(v) == "string" or type(v) == "number" or type(b) == boolean, "Parameter types must be string, number or boolean")
    params = params .. (type(v) == "string") and string.format("\"v\"") or v
    params = (#t==i) and params .. "}" or params .. ", " -- if not last entry, then add "," afterwards, else close the bracket
  end
  return string.format([[
  return {
    type = "call",
    user = %s,
    moid = %s,
    moc = %s,
    func = %s,
    params = params
  }]],
  assert(t.user, "Serialization error: USER not found"),
  assert(t.moid, "Serialization error: MOID not found"),
  assert(t.moc, "Serialization error: MOCID not found"),
  assert(t.func, "Serialization error: FUNCTION not found")
  );
end

-- #################### FRAMEWORK INSTANCE PARAMS AND FUNCTIONS


local myDC = 0 -- my own data center ID
local myClusterIP = "0.0.0.0" -- IP-Address of instance within its data center NOT "0.0.0.0", but the one that is connectable from external
local myClusterPort = 55655 -- Port for Cluster comm
local myDriverDir = "./drivers" -- Path for MOMapping Drivers
local myTLSKey = "./config/tls.key"
local myTLSCert = "./config/tls.cert"

-- describes the cluster environment of all instances
local clusterEnvironment = {
  --[[ EXEMPLARY ENTRY
  dcid = {dcid = <DCID>,
        clip = <IP-ADDRESS OF REMOTE INSTANCE>,
        clpo = <SERVICE PORT OF REMOTE INSTANCE>}
  ]]
}


local tlsparams = {
  mode = "client",
  protocol = "tlsv1_2",
  key = myTLSKey,
  certificate = myTLSCert,
  verify = "none" -- "none" ONLY FOR TESTING PURPOSES!! USE "peer" INSTEAD
}



-- register new instance in my cluster
function registerInstance  (dcid, clip, clpo)
  assert(dcid, "Data Center ID must be given as first parameter!")
  assert(clip, "Remote IP-Address of instance must be given as second parameter!")
  assert(clpo, "Remote Port of instance must be given as third parameter!")
  assert(not clusterEnvironment.dcid, "Data center ID is already assigned, choose another one!")
  
  clusterEnvironment[dcid] = {dcid=dcid,
                              clip=clip,
                              clpo=clpo}
end

function unregisterInstance (dcid)
  assert(dcid, "Data Center ID must be given!")
  clusterEnvironment[dcid] = nil
end

function loadDriverModule(filename)
  assert(filename, "Module name must be given")
  local fh = assert(io.open(string.format("%s/%s", myDriverDir, filename), "r"))
  local ct = assert(fh:read("a"))
  fh:close()
  return loadstring(ct)
end


-- #################### CLUSTER FUNCTIONS...

-- TO BE CONTINUED


--
-- Sends a simple method call to DC with DCID which looks like this
-- 
-- {
--      type = "call",
--      user = <USER>,
--      moid = <MOID>,
--      moc = <MOCID>,
--      func = <FULL-FUNC-ID>,
--      params = {param1, param2, param3, ...}
-- }
--
--
--
function remoteCall(dcid, user, moid, moc, func, params)
  assert(dcid and type(dcid) == "string", "DCID must be given and of type string (first parameter)")
  assert(clusterEnvironment[dcid], "Data center ID does not exist")
  assert(clusterEnvironment[dcid][clip] and clusterEnvironment[dcid][clpo], "Service IP address or service port of DCID instance not found!")
  assert(user and type(user) == "string", "User must be given and of type string (second parameter)")
  assert(moid and type(moid) == "string", "MO must be given and of type string (third parameter)")
  assert(moc and type(moc) == "string", "MOC must be given and of type string (fourth parameter)")
  assert(func and type(func) == "string", "FUNC must be given and of type string (fifth parameter)")
  assert(params and type(params) == "table", "PARAMS must be given and of type table (sixth parameter)")

  -- check if params type comply
  assert(getMOCType:checkFuncParamsCompatibility(func, params), "Parameters do not comply")
  
  -- build message
  local command = serializeFunctionCallStructure({type="call", user=user, moid=moid, moc=moc, func=func, params=params})
  
  -- connect and send it!
  local tcp = lsock.tcp() -- create TCP obj
  local conn = tcp:connect()
  assert(conn:connect(clusterEnvironment[dcid].clip, clusterEnvironment[dcid].clpo), string.format("Could not connect to %s:%d", clusterEnvironment[dcid].clip, clusterEnvironment[dcid].clpo))
  
  -- Initialize TLS with tlsparams from above
  conn = lsec:wrap(conn, tlsparams)
  assert(conn:dohandshake())
  assert(conn:send(command) == #command, "Seems like the message could not be sent successfully...")
  conn:close()
end

-- #################### FUNCTION ACCESS HANDLER


-- local accessModel = {
  -- e.g.
  -- free = function (user, mo, func) return true end,
  -- inDomain = function (user, mo, func)
  --   
  --   
  -- end
  --
  
-- }
local currentAM = {
  -- free Class: Everyone can access
  free = function (user, moid, func) return true end,
  -- inDomain = Access granted if user is in same domain as MO 
  inDomain = function (user, moid, func) 
    assert(user, "User must be given as first parameter")
    assert(moid, "MO-ID must be given as second parameter")
    assert(func, "Requested function must be given as third parameter")
    -- Using public functions only...
    local doms = {getDomainIDs}
    for _,d in ipairs(doms) do
      if d:checkUser(user) and d:checkMo(moid) then
        return true
      end
    end
    return false
  end
}


function setAccessModel (newAM)
  assert(newAM, "New Access Model must be given!")
  -- Currently quite liberal plausibility check 
  for _,v in pairs(newAM) do
    if type(v) ~= "function" then 
      assert("All Types of contents of Access model must be function (user, no, func)")
    end
  end
  return true
end


-- #################### DOMAINS

local domains = {}
local domain = {}

domain.new = function (did)
  assert(not domains[did], string.format("Domain %s already existing", did))
  local t = {}
  t.id = did
  setmetatable(t, {__index = domain})
  domains[did] = t -- Add domain to the others...
  return t
end

function domain:addUser (uid)
  assert(uid, "UserID must be given")
  self.users = self.users or {}
  self.users[uid] = true -- If user is already in domain, then nothing changes...
end

function domain:delUser (uid)
  assert(uid, "UserID must be given")
  if self.users then
    self.users[uid] = nil -- Remove the user, no matter if he existed or not...
  end
end

function domain:getUsers()
  return multiReturn(self.users)
end

-- reverse find user and his/her domains
function findUser(u)
  local userdomains = {}
  for _,d in pairs(domains) do
    if (d:checkUser(u)) then
      userdomains[#userdomains+1] = d.id
    end
  end
  multiReturn(userdomains)
end

-- Check if user is in domain
function domain:checkUser(uid)
  return self.users and self.users[uid]
end

-- check if mo is in domain
function domain:checkMo(m)
  return self.mos and self.mos[m]
end

function getDomainIDs()
--  function gdomHelper (last)
--    local cur = next(domains, last)
--    if cur then
--      return cur, gdomHelper(cur)
--    end
--  end
  return multiReturn(domains)
end

function getDomain(did)
  assert(domains[did], string.format("Domain %s does not exist", did))
  return domains[did]
end

-- #################### MOCTypeModel

-- add node moroot initially
local MOCTypeModel = {moroot = {id="moroot", version="NoVersion", parents = {}, functions={}, abstract = true}} 
local moctype = {}

--
--
--
-- parents = {"nodeX:version", ...}
moctype.new = function (mid, version, parents, abstract)
  assert(mid and version, "Moctype ID mid and version must be given! (parents is an optional third param)")
  assert(not MOCTypeModel[mid], "MocType already existing in Model!")
  assert(abstract ~= nil, "Abstract flag must be given as last parameter!")
  -- check is parents given and all exist
  if parents then
    for _,m in ipairs(parents) do
      assert(MOCTypeModel[m], string.format("MOCType %s not existing in MOCTypeModel", m))
    end
  end
  
  local t = {id=mid, version=version, parents = parents or {"moroot"}, functions = {}, abstract = abstract} -- if no parent is given, then add it to moroot
  MOCTypeModel[string.format("%s:%s", mid, version)] = t
  setmetatable(t, {__index = moctype})
  return t
end

-- Every function has an identifier fid, belongs to a MOCType mid and takes params paramList
-- e.g., {string, string, int} and returns one or multiple result described by retList,
-- e.g., {boolean, int}
-- DRIVER = function (params, self)
function moctype:addFunction (fid, paramList, retList, driver) -- TODO implement Driver
  assert(fid, "Function ID must be given")
  assert(paramList , "ParamList must be given: {\"type1\", ..., \"typeN\"}")
  assert(retList , "RetList must be given: {\"type1\", ..., \"typeN\"}")
  assert(self.abstract or driver , "driver function must be implemented: reference to file implementing function (params, mo)")
  assert(not self.functions[fid], "Function in MOCType already existing...")
  self.functions[fid] = {snode = nil, params = paramList or {}, ret = retList or {}, driver=driver} -- Add function, param- + retDescriptors
end

function moctype:addDriver(snode, fid, driver)
  assert(not self.abstract, "You cannot add drivers to abstract nodes!")
  assert(snode and MOCTypeModel[snode], "Function's source node must be given and existing!")
  assert(fid and MOCTypeModel[snode].functions[fid], "Function's id node must be given and existing for referencedsource node!")
  local func = require(driver)
  assert(func, "Could not load driver... Not found or erroneous!")
  assert(type(func) == "function", "Given driver must implement a driver function")
  
  -- driver must implement an inherited function... hence: set snode reference in own functions
  self.functions[fid] = {snode=snode, driver=func}
end


function moctype:delFunction (fid)
  assert(fid, "Function ID must be given")
  assert(self, "MOCType not existing...")
  assert(self.functions[fid], "Function in MOCType does not exist anyway...")
  self.functions[fid] = nil -- remove it already!
end

function moctype:checkFuncParamsCompatibility(func, params)
  assert(func and type(func) == "string", "Function ID must be given as first parameter as string")
  assert(self.functions[func], string.format("Function %s does not exist in this MOCType", func))
  assert(params and type(func) == "table", "Calling Params must be given as second parameter as table of values")
  assert(#params == #self.functions[func].params[i], string.format("Number of parameters given (%d) does not complay with expected number (%d)", #params, #self.functions[func].params[i]))
  for i,_ in ipairs(params) do
    assert(type(params[i]) == self.functions[func].params[i], string.format("Parameter at position %d does not comply with expected type %s", i, self.functions[func].params[i]))
  end
  return true
end

-- input a la MOCTYPE:VERSION:FUNC
function moctype:findDriverFunction(nfunc)

  -- disassemble func
  local moc, func = nfunc:match("(%S+:%S*):(%S+)")
  assert(moc and func, "Could not disassemble function")
  assert(MOCTypeModel[moc] and MOCTypeModel[moc].functions[func], "Function's source MOCType not existing or function missing!")
  
  -- 1 case: I implement it myself!
  if self.functions[func] and self.functions[func].snode == moc and self.functions[func].driver then
    return self.functions[func].driver
  end
  
  -- 2 case: check where function comes from: Traverse MOCTree
  local tnode = self
  local next =  {p=1}
  while tnode ~= MOCTypeModel[moc] or tnode ~= nil do
    for _,v in ipairs(tnode.parents) do
      next[#next+1] = MOCTypeModel[v]
    end
    tnode = next[next.p]
    
    if not tnode.abstract and tnode.functions[func] and tnode.functions[func].snode == moc and tnode.functions[func].driver then
      return tnode.functions[func].driver
    end
    next.p = next.p+1
  end
  error("Driver not found")  
end


function moctype:getFunctions ()
  local res = {}
  -- functions from MOCType itself 
  for v in pairs(self.functions) do
    res[#res+1] = string.format("%s:%s:%s", self.id, self.version, v)
  end
  for i in ipairs(self.parents) do
    for v in pairs(MOCTypeModel[i].functions) do
      res[#res+1] = string.format("%s:%s:%s", MOCTypeModel[i].id, MOCTypeModel[i].version, v)
    end
  end
  multiReturn(res)
end

-- MUST BE IMPROVED, in a manner that this function return the tree-view of dependent MOCTypes
function getMOCTypes()
--  function gmocsHelper (last)
--    local cur = next(MOCTypeModel, last)
--    if cur then
--      return cur, gmocsHelper(cur)
--    end
--  end
  return multiReturn(MOCTypeModel)
end

function getMOCType(mid)
  assert(MOCTypeModel[mid], "MOCType does not exist...")
  return MOCTypeModel[mid]
end

-- Add root Moctype
-- moctype.new("moroot, "NoVersion");







-- #################### MOMAPPING

local momapping = {}
local moids = {}
local mo = {} --- IP, TYPE, API-URL, DC


-- MO domain handling

function domain:addMo (moid)
  assert(moid and momapping[moid], "MOID must be given and existing")
  self.mos = self.mos or {}
  self.mos[moid] = true
end

function domain:delMo (moid)
  assert(moid and momapping[moid], "MOID must be given and existing")
  assert(self.mos[moid], "MO is not part of this domain")
  if self.mos then
    self.mos[moid] = nil
  end
end


-- APIpoint needs to be defined in a more detailed manner -- meant as var in order to adapt to differences e.g. in a HTTP-REST-URL
mo.new = function (moid, ip, servport, mtype, apipoint, dc, cred, aclass, acexceptions) 
  assert(ip and servport and mtype and apipoint and dc, "MO-ID, IP, Service Port, MOCType, APIPoint and Datacenter must be given (credentials can be given optionally)")
  assert(MOCTypeModel[mtype], "The Type of MO must correspond to an existing MOCType in the MOCTypeModel")
  assert(aclass, "Default access class must be given!")
  assert(currentAM[aclass], string.format("Access class '%s' not found in access model!", aclass))
  local t = {id=moid, ip=ip, sport=servport, mtype=mtype, apipoint=apipoint, dc=dc, cred=cred, defaultAccess=aclass, acexception=acexceptions or {}}
  setmetatable(t, {__index=mo})
  momapping[moid] = t -- moid references the object in the mo-mapping -- cannot be changed or overwritten
  moids[t] = moid
  return t
end

function deleteMo (moid)
  assert(moid, "MO-ID must be given")
  momapping[moid] = nil
end

function getMos()
  return multiReturn(momapping)
end

function getMo(moid)
  assert(moid, "MO-ID must be given")
  assert(momapping[moid], "Cannot find MO with given ID")
  return momapping[moid]
end

function mo:getId()
  assert(moids[self], "Cannot find id of MO")
  return moids[self]
end

function mo:getFunctions()
  local t = {}
  local mtmnode = MOCTypeModel[self.mtype] or MOCTypeModel.moroot -- Fallback if (through whatever cause) the MOCType does not exist
  while (mtmnode ~= nil) do
    for i,_ in pairs(mtmnode.functions) do
      t[#t+1] = i -- Add any function in mtmnode
    end
    mtmnode = mtmnode.parent
  end
  return multiReturn(t)
end

function mo:exec(user, nfunc, params)
  assert(user and nfunc and type(nfunc) == "string" and type(params) == "table", "UserID, Full-Function-ID (string) and params must be given (params must be a, array-like table, w/ values corresponding to the function's params description)")
  assert(not self.mtype.abstract, "Functions can only be called on non-abstract MOCTypes")
  -- 0. Separate MOC and function from nfunc. Note that version is not necessarily given
  local moc, func = nfunc:match("(%S+:%S*):(%S+)")
  assert(moc and func, "Could not separate MOC and function-id from full function ID")
  
  -- 1. Access checks -- is user authorized to call func?; BTW User authentication must be done in host application BTW!!
  -- 1a Check if there is any exception
  if (self.acexception[nfunc]) then
    -- 1aa found -- check if it exists in AccessModel
    assert(currentAM[self.acexception[nfunc]], string.format("Given access model exception class '%s' for MO '%s' and function '%s' cannot be found in access model! Call blocked!.", self.acexception[nfunc], self.id, nfunc))
    assert(currentAM[self.acexception[nfunc]](user, self, func) == true, string.format("User %s calls func %s from MO %s: Access Denied!", user, nfunc, self.id))
  else
  -- 1b no exception found -- ask default class...
    assert(currentAM[self.defaultAccess](user, self, nfunc) == true, string.format("User %s calls func %s from MO %s: Access Denied!", user, nfunc, self.id))
  end
  -- 2 find data center -- which instance is responsible?
  if self.dc == myDC then 
    -- 2a THIS IS MY DC :))
    
    
    
    -- 3. Find Driver function!!
    local dri = MOCTypeModel[self.mtype]:findDriverFunction(nfunc)
    assert(dri, "Could not find driver function")
    
    -- Driver found, OK...
    -- 4. check whether params corresponds to function's param description
    assert(#params == #(MOCTypeModel[moc].functions[func].params), "Number of parameters does not fit the function description")
    for i=1,#params do
      assert(type(params[i]) == MOCTypeModel[moc].functions[func].params[i], string.format("Parameter %d does not have an appropriate type. Must be %s", i, MOCTypeModel[moc].functions[func].params[i]))
    end

    -- 5. get access point via apmap/momapping lookup
    local api = lookupAPIAccessPoint(nfunc, self.id, self.mtype)


    -- Everything is fine, execute it already!
    local ret = dri(params, self, api)
    return ret
    
  else
    -- 2b this mo is NOT in MY DC...find responsible instance
    assert(clusterEnvironment[self.dc], string.format("Responsible instance for data center with ID %s cannot be found", self.dc))
    remoteCall(self.dc, user, self, func, params)
  end
end

function mo:addToDomain(did)
  assert(did and domains[did], "Domain must be given and existing")
  domains[did]:addMo(self:getId())
end

function mo:getDomains()
  local r = {}
  for i,v in pairs(domains) do
    if v.mos[self.id] then
      r[#r+1] = v
		end
	end
  return r
end



-- #################### APMap

local apmap = {}

function addAPMapEntry(ffid, callingMOC, newap)
  apmap[ffid] = apmap[ffid] or {}
  apmap[ffid][callingMOC] = apmap[ffid][callingMOC] or newap
end


function lookupAPIAccessPoint(ffid, mo, mocid)
  if apmap[ffid] and apmap[ffid][mocid] then
    -- apmap has (ffid, mocid) tuple
    return apmap[ffid][mocid]
  else
    -- apmap does not have (ffid, mocid) tuple
    -- => use MO's standard API access point
    -- from momapping
    return momapping[mo].apipoint
  end
end




-- #################### GENERAL FUNCTIONS

function init(config)
  assert(config, "Configuration Parameter not found...")
  assert(config.thisDC, "Data Center ID of this instance must be given in param1.myDC")
  assert(config.myIP, "Cluster IP-Address of this instance must be given in param1.myIP")
  assert(config.myPort, "Data Center ID of this instance must be given in param1.myPort")
  assert(config.driverDir, "Driver directory path of this instance must be given in param1.driverDir")
  assert(config.tlsKey, "TLS KEY path of this instance must be given in param1.tlsKey")
  assert(config.tlsCert, "TLS CERT path of this instance must be given in param1.tlsCert")
  if not config.accessmodel then print("Hint: Access model CAN be given in param1.accessmodel") end
  myDC = config.thisDC
  myClusterIP = config.myIP
  myClusterPort = config.myPort
  myDriverDir = config.driverDir
  currentAM = config.accessmodel or currentAM
  
  return {
  -- General
  registerInstance = registerInstance,
  unregisterInstance = unregisterInstance,
  -- Domains
  getDomains = getDomainIDs,
  addDomain = domain.new,
  getDomain = getDomain,
  -- MOCTypes
  addMOCType = moctype.new,
  getMOCTypes = getMOCTypes,
  getMOCType = getMOCType,
  addAPMapEntry = addAPMapEntry,
  -- MOs
  getMos = getMos,
  addMo = mo.new,
  getMo = getMo,
  -- Function Access Handler
  -- setAccessModel = setAccessModel,-- DEFINE IT IN ORDER TO IMPLEMENT IT
  getAccessModel = function () return currentAM end
}

end

-- #################### EXPORT STRUCTURE

return init
