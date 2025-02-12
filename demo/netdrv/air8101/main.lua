
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netdrv"
VERSION = "1.0.4"


-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

sys.taskInit(function()
    sys.wait(1000)
    gpio.setup(13, 1, gpio.PULLUP) -- 打开开发板的LDO供电,否则3.3V没电
    netdrv.setup(socket.LWIP_ETH)
    netdrv.dhcp(socket.LWIP_ETH, true)
end)

sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(6000)
        log.info("http", http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {adapter=socket.LWIP_ETH}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("ip", socket.localIP(socket.LWIP_ETH))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
