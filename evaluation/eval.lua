#! /usr/bin/lua

-- relative paths to the fedcon framework, drivers and utility libraries
package.path = package.path .. ";../fedcon/?.lua;accessmodel/?.lua;drivers/?.lua;util/?.lua"

-- load fedcon init function into variable fcinit
fcinit = require "fedcon"

-- load access model as it is described in file accessModel.lua
currentAM = require "accessModel"




-- #### PREREQUISITES: Managed Object (MO) ID management


-- The following IDs are supposed to be managed, not by FEDCON itself, but by its corresponding HOST application.
-- The following table represents a very simple MO-ID management structure
sampleMOs = {
  mONE = "mONE-1",
  odl  = "odlight1"
}




-- #### FEDCON INITIALIZATION

-- initialize instance fedcon-a in data center alpha
fc = fcinit({
  thisDC = "alpha",
  myIP = "192.168.111.5",
  myPort = 5555,
  tlsKey = "config/tls.key",
  tlsCert = "config/tls.crt",

  -- driver functions (cf. later sections)
  -- are stored in this folder in script form
  driverDir = "drivers/",

  -- implemented in following sections
  accessmodel = currentAM
});



-- #### BUILD MOCTYPEMODEL

-- ###### MOCTYPEMODEL-Branch: moroot --- mano --- iaas --- opennebula

-- Add MANO-element, IAAS-element and OPENNEBULA-element
-- Parameters of function addMOCType: id, version, list-of-parent-nodes, is-abstract-flag
fc.addMOCType("mano", "", {"moroot"}, true)
fc.addMOCType("iaas", "", {"mano:"}, true)
fc.addMOCType("opennebula", "5.10", {"iaas:"}, false)

-- Parameters of function addFunction: func-id, func-parameters-types (here: id, ip, port), func-return-type (here: function call success)
fc.getMOCType("mano:"):addFunction ("addcompnode", {"string", "string", "number"}, {"boolean"})
fc.getMOCType("mano:"):addFunction ("addstoragenode", {"string", "string", "number"}, {"boolean"})

-- Params of function vmcreate: name, cpu, mem, disc; return value: function call success
fc.getMOCType("iaas:"):addFunction ("vmcreate", {"string", "number", "number", "number"}, {"boolean"})

-- Params of function vmboot: name of vm; return value: function call success
fc.getMOCType("iaas:"):addFunction ("vmboot", {"string"}, {"boolean"})




-- ###### MOCTYPEMODEL-Branch: moroot --- sdncontroller --- openflow-controller --- floodlight:1.2
--                                                    |
--                                                    ----- ovsdb-controller --- opendaylight:12


fc.addMOCType("sdncontroller", "", {"moroot"}, true)
fc.addMOCType("openflow-controller", "1.5.1", {"sdncontroller:"}, true)
fc.addMOCType("floodlight", "1.2", {"openflow-controller:1.5.1"}, false)
fc.addMOCType("ovsdb-controller", "", {"sdncontroller:"}, true)
fc.addMOCType("opendaylight", "12", {"ovsdb-controller:", "openflow-controller:1.5.1"}, false)

-- simple flow modification function
-- Params of function addFlow: DPID, table-id, flow-id, content; return value: function call success
fc.getMOCType("openflow-controller:1.5.1"):addFunction ("addFlow", {"string", "number", "number", "string"}, {"boolean"})

-- Params: ovsdb-table, conditions, columns
fc.getMOCType("ovsdb-controller:"):addFunction ("select", {"string", "string", "string"}, {"boolean"})

-- Adding ODLs network topology function
-- no Params
-- return topology as serialized list
-- fc.getMOCType("opendaylight:12"):addFunction("network-topology", {}, {"table"})



-- #### DRIVER IMPLEMENTATION and ASSIGNMENT
-- cf. separate lua files in directory ./drivers/
package.path = package.path .. ";./drivers/?.lua"

-- add driver for MOCType opennebula:5.10 for function "vmboot"
-- inherited from node iaas
-- miniONEd1 is driver module's name in driver directory
fc.getMOCType("opennebula:5.10"):addDriver("iaas:", "vmboot", "miniONEd1")

-- add driver for MOCType opendaylight:12 for function "addFlow"
-- inherited from node openflow-controller
-- odld1 is driver module's name in driver directory
fc.getMOCType("opendaylight:12"):addDriver( "openflow-controller:1.5.1", "addFlow", "odld1")

-- add APMap Entry in order to register a different API access point for function addFlow
fc.addAPMapEntry("openflow-controller::addFlow", "opendaylight:12", "/restconf/config/opendaylight-inventory:nodes/node/openflow:<DPID>/table/<TABID>/flow/<FLID>")





-- #### MOMAPPINGs and DOMAIN Handling

-- add domains domAlpha with user aAdmin and domain domBeta with user bAdmin
fc.addDomain("domAlpha"):addUser("aAdmin")
fc.addDomain("domBeta"):addUser("bAdmin")



-- (moid, ip, service-port, moctype, apipoint, data-center, credentials, default-access-class, access-class-exceptions)
fc.addMo(sampleMOs.mONE, "127.0.0.1", 2633, "opennebula:5.10", "RPC2", "alpha", {user="oneadmin", passw="mypassword"}, "inDomain")

-- add MO mONE-1 to domain domAlpha
fc.getDomain("domAlpha"):addMo(sampleMOs.mONE)


-- (moid, ip, service-port, moctype, apipoint, credentials data-center, default-access-class, access-class-exceptions)
fc.addMo(sampleMOs.odl, "192.168.130.15", 8181, "opendaylight:12", "/restconf", "beta", {user="admin", passw="admin"}, "inDomain", {["opendaylight:12:network-topology"] = "free"})

-- add MO odlight1 to domain domBeta
fc.getDomain("domBeta"):addMo(sampleMOs.odl)


-- #### Function calling

-- call for user aAlpha,
-- function vmboot from MOCType iaas
-- parameter: vm01 is id of instance to boot
local ret = fc.getMo(sampleMOs.mONE):exec("aAdmin", "iaas::vmboot", {"vm01"})

-- check if function call was successful
if ret then

else

end
