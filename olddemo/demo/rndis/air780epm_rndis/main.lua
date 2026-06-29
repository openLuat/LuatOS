
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "rndis"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    -- 开启RNDIS, 独立IP模式(直接拿到基站分配的内网IP)
    -- mobile.config(mobile.CONF_USB_ETHERNET, 1)

    -- 开启RNDIS, NAT模式
    mobile.config(mobile.CONF_USB_ETHERNET, 1 + (1 << 1))

    -- 开启ECM, 独立IP模式(直接拿到基站分配的内网IP)
    -- mobile.config(mobile.CONF_USB_ETHERNET, 1 + (0 << 1) + (1 << 2))

    -- 开启ECM, NAT模式
    -- mobile.config(mobile.CONF_USB_ETHERNET, 1 + (1 << 1) + (1 << 2))
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
