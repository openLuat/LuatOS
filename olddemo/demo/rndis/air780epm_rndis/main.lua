
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "rndis"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()

    
    -- 开启RNDIS, 独立IP模式(直接拿到基站分配的内网IP)
    -- mobile.config(mobile.CONF_USB_ETHERNET, 1)

    -- 设置USB以太网卡的IP地址
    -- netdrv.ipv4(socket.LWIP_USB, "192.168.20.1", "255.255.255.0", "0.0.0.0")
    -- 开启RNDIS, NAT模式
    mobile.config(mobile.CONF_USB_ETHERNET, 1 + (1 << 1))

    -- 开启ECM, 独立IP模式(直接拿到基站分配的内网IP)
    -- mobile.config(mobile.CONF_USB_ETHERNET, 1 + (0 << 1) + (1 << 2))

    -- 开启ECM, NAT模式
    -- mobile.config(mobile.CONF_USB_ETHERNET, 1 + (1 << 1) + (1 << 2))

    log.info("进入飞行模式")
    mobile.flymode(0, true)
    log.info("退出飞行模式")
    mobile.flymode(0, false)
    -- 设置网卡需要开关USB电源
    pm.power(pm.USB ,false)
    pm.power(pm.USB ,true)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
