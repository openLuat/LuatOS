
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "udpdemo"
VERSION = "1.0.0"

local sys = require "sys"

-- V0004开始支持设置Band模式, 中移动的卡支持B8
if nbiot.getBands then log.info("bands", nbiot.getBands()) end
if nbiot.setBands then nbiot.setBands({8}) end

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
                    netc:send("IMEI:" .. nbiot.imei())
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
                        netc:send("heartbeat:" .. nbiot.imei() .. " " .. os.date())
                    end
                end
            end
            netc:clean()
            netc:close()
            log.info("udp", "all close, sleep 30s")
            sys.wait(300000)
        else
            sys.wait(1000)
        end
    end
end)

-- 结尾总是这一句哦
sys.run()
