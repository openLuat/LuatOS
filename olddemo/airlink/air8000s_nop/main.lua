
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netdrv"
VERSION = "1.0.5"
--[[特别注意, 生成量产文件的时候要带上nop.txt，否则会造成fota失败]]
--[[特别注意, 生成量产文件的时候要带上nop.txt，否则会造成fota失败]]
--[[特别注意, 生成量产文件的时候要带上nop.txt，否则会造成fota失败]]


-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

sys.taskInit(function()
    -- sys.wait(500)
    -- airlink.start(0)
    -- wlan.init()
end)

sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    sys.wait(6000)
    while 1 do
        sys.wait(6000)
        -- log.info("http", http.request("GET", "http://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_ETH,timeout=3000}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        -- log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        -- log.info("ip", socket.localIP(socket.LWIP_ETH))
        airlink.statistics()
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
