

PROJECT = "socketdemo"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(3000, pmd.LDO_VLCD)

sys.taskInit(function()
    local netled = gpio.setup(1, 0)
    local count = 1
    while 1 do
        netled(1)
        sys.wait(1000)
        netled(0)
        sys.wait(1000)
        log.info("luatos", "hi", count, os.date())
        log.info("luatos", "socket", socket.isReady())
        count = count + 1
        --lte.switchSimSet(1)
    end
end)

sys.subscribe("NET_READY", function ()
    log.info("net", "NET_READY Get!!!")
end)

sys.taskInit(function()
    sys.wait(2000)
    while not socket.isReady() do
        log.info("net", "wait for network ready")
        sys.waitUntil("NET_READY", 1000)
    end
    while true do
        if not socket.isReady() then
            sys.waitUntil("NET_READY", 1000)
        else
            local netc = socket.tcp()
            -- 模拟http请求 http://site0.cn/api/httptest/simple/date
            netc:host("site0.cn")
            netc:port(80)
            netc:on("connect", function(id, re)
                log.info("netc", "connect result", re)
                if re == 1 then
                    netc:send("GET /api/httptest/simple/date HTTP/1.0\r\nHost: site0.cn\r\n\r\n")
                end
            end)
            netc:on("recv", function(id, re)
                log.info("recv", id, #re, re)
                if #re == 0 then
                    --re = netc:recv(1500)
                    log.info("recv", id, re)
                end
            end)
            if netc:start() == 0 then
                log.info("netc", "start ok")
                sys.waitUntil("NETC_END_" .. netc:id(), 30000)
            else
                log.info("netc", "start fail? why")
            end
            netc:close()
            netc:clean()
            sys.wait(60000)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
