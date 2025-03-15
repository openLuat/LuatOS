
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netdrv"
VERSION = "1.0.4"


-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")
dnsproxy = require ("dnsproxy")

sys.taskInit(function()
    sys.wait(100)
    -- 初始化airlink
    airlink.init()
    log.info("创建桥接网络设备")
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    -- 启动底层线程, 从机模式
    airlink.start(1)

    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.2", "255.255.255.0", "192.168.111.1")
    sys.wait(100)
    sys.waitUntil("IP_READY", 10000)
    netdrv.napt(socket.LWIP_GP)
    dnsproxy.setup(socket.LWIP_USER0, socket.LWIP_GP)
    -- sys.wait(1000)
    -- while 1 do
    --     sys.wait(1000)
    --     log.info("执行http请求")
    --     -- local code = http.request("GET", "http://192.168.1.15:8000/README.md", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
    --     local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
    --     log.info("http执行结果", code, code, headers, body)
    -- end
end)

sys.subscribe("IP_READY", function(id, ip)
    log.info("收到IP_READY!!", id, ip)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
