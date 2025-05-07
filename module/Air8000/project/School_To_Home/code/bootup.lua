
-- IPV6_UDP_VER = true
--[[ 
    测试，如果设置下面的网络参数，rrc 和 drx， 对通话连接的建立和销毁，似乎有影响
        比如：
            1：手机给模块打电话，模块收不到通话消息
            2：手机给模块打电话，模块延迟收到通话消息
            3：手机给模块打电话，模块收到通话消息后，不接通，手机挂断，模块收不到通话结束的消息

    如果测试发现通话异常，可以将下面设置rrc和drx的代码注释掉，重新下载，下载的时候选上清除kv和fs分区
]]

mobile.flymode(0, true)
-- mobile.rtime(3)
-- mobile.config(mobile.CONF_USERDRXCYCLE, 10)
_G.chip = hmeta.chip and hmeta.chip() or "EC718U"
if chip == "EC718UM" or chip == "EC718HM" then
    log.info("vsim", "开启VSIM功能")
    -- mobile.vsimInit()
    -- mobile.vsimOnOff(true)
else
    log.info("vsim", "不需要开启")
end
if IPV6_UDP_VER then
    mobile.ipv6(true)
else
    mobile.ipv6(false)
end
mobile.flymode(0, false)


wlan.init()
sys.taskInit(function()
    sys.waitUntil("IP_READY", 15000)
    sys.wait(5000)
    wlan.scan()
end)

-- 遥测数据
_G.mreport = require "mreport"

-- config
require "cfg"

--2712A
-- require "2712A"

-- netWork
_G.netWork = require "netWork"

-- libnet
_G.libnet = require "libnet"

-- manage
_G.manage = require "manage"

_G.charge = require "charge"

-- gnss
_G.gnss = require "gnss"

-- commnon
_G.common = require "common"

-- api
_G.api = require "api"

-- jt808
_G.jt808 = require "jt808"

_G.srvs = require "srvs"

-- if cc and audio then
--     _G.calling = require "calling"
-- else
--     log.warn("main", "当前底层不支持VoLTE,关闭呼叫功能")
-- end

-- auxTask
local auxTask = require "auxServer"
srvs.add(auxTask)

-- ledTask
require "ledTask"

collectgarbage("collect")
collectgarbage("collect")

-- Gsensor
require "da221"

require "mdebug"
