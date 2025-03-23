
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_gpio_ext"
VERSION = "1.0.5"

-- sys库是标配
_G.sys = require("sys")
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")

PWR8000S = gpio.setup(23, 0, gpio.PULLUP) -- 关闭Air8000S的LDO供电

sys.taskInit(function()
    -- 稍微缓一下
    sys.wait(10)
    -- 初始化airlink
    airlink.init()
    -- 启动底层线程, 从机模式
    airlink.start(1)
    PWR8000S(1)
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)

    sys.wait(100)
    wlan.init()
    sys.wait(100)
    wlan.createAP("uiot5678", "12345678")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    sys.wait(100)
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
