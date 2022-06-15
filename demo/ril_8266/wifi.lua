--module(..., package.seeall)

-- require "pm"
-- pm.wake("WIFI")

-- require "pins"

-- sys.taskInit(function()
--     pmd.ldoset(6, pmd.LDO_VLCD)
--     local urtIO = pins.setup(15, 0)
--     urtIO(0)
--     sys.wait(5000)
--     print("pins.setup")
--     urtIO(1)
-- end)

ril_wifi = require "ril_wifi"
_G.link = require "link_wifi"
_G.socket = require "socket_wifi"
_G.net = {
    switchFly = function(f)
        log.info("net", "switchFly", f)
    end,
    startQueryAll = print
}

local unlod = {
    socket = true,
    link = true,
    net = true
}

local require_wifi = _G.require
_G.require = function(name)
    if not unlod[name] then
        require_wifi(name)
    end
end

_G.point = function(...)
    local name = debug.getinfo(2).short_src:sub(6, -5)
    local line = debug.getinfo(2).currentline
    print("[" .. name .. " : " .. line .. "]", ...)
end

