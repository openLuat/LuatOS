
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netdrv"
VERSION = "1.0.4"


-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

-- 第一组是GPIO27, GPIO29, GPIO32到GPIO39
-- 支持切换到第二组ETH引脚, GPIO47到GPIO55 (临时写法,将来支持pins)
-- if mcu.ETH then
--     mcu.altfun(mcu.ETH, 0, 49) -- 固定用GPIO49来选
-- end

sys.taskInit(function()
    sys.wait(500)
    gpio.setup(13, 1, gpio.PULLUP) -- 打开开发板的LDO供电,否则3.3V没电
    netdrv.setup(socket.LWIP_ETH)
    -- log.info("设置启用DHCP")
    netdrv.dhcp(socket.LWIP_ETH, true)
    -- log.info("设置静态IPV4")
    -- netdrv.ipv4(socket.LWIP_ETH, "192.168.1.129", "255.255.255.0", "192.168.1.1")
    -- log.info("ip", socket.localIP(socket.LWIP_ETH))
end)

sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(6000)
        log.info("http", http.request("GET", "http://httpbin.air32.cn/get", nil, nil, {adapter=socket.LWIP_ETH,timeout=3000}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))
        log.info("ip", socket.localIP(socket.LWIP_ETH))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
