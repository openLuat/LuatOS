
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netdrv"
VERSION = "1.0.4"


-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

sys.taskInit(function()
    -- sys.wait(500)
    airlink.init()
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    airlink.start(0)
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
end)

sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    sys.wait(6000)
    while 1 do
        sys.wait(500)
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_USER0,timeout=3000}).wait()
        log.info("http", code, body and #body)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
