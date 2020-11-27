
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "udpdemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

wlan.connect("uiot", "12345678")

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            sys.wait(2000)
            local netc = socket.udp()
            netc:host("nutz.cn")
            netc:port(17888)
            netc:on("connect", function(id, re)
                log.info("udp", "connect ok", id, re)
                if re then
                    netc:send("IMEI:" .. wlan.getMac())
                end
            end)
            netc:on("recv", function(id, data)
                log.info("udp", "recv", #data, data)
            end)
            if netc:start() == 0 then
                while netc:closed() == 0 do
                    sys.waitUntil("NETC_END_" .. netc:id(), 30000)
                    if netc:closed() == 0 then
                        log.info("udp", "send heartbeat")
                        netc:send("heartbeat:" .. wlan.getMac() .. " " .. os.date())
                    end
                end
            end
            netc:clean()
            netc:close()
            log.info("udp", "all close, sleep 30s")
            sys.wait(30000)
        else
            sys.wait(1000)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
