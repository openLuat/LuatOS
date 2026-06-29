
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

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

function create_ap()
    log.info("执行AP创建操作", "luatos8888")
    wlan.createAP("luatos8888", "12345678")
    sys.wait(1000)
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    apdhcpd = dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
    end
end

sys.taskInit(function()
    sys.wait(100)
    wlan.init()
    sys.wait(100)

    -- 启动AP测试
    create_ap()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
