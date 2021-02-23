

PROJECT = "wlandemo"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(1800, pmd.LDO_VLCD)

sys.taskInit(function()
    local netled = gpio.setup(1, 0)
    local count = 1
    while 1 do
        netled(1)
        sys.wait(1000)
        netled(0)
        sys.wait(1000)
        log.info("luatos", "hi", count, os.date())
        count = count + 1
    end
end)

sys.subscribe("NET_READY", function ()
    log.info("net", "NET_READY Get!!!")
    sys.taskInit(function()
        while true do
            sys.wait(10000)
            local netc = socket.tcp()
            netc:host("nutz.cn")
            netc:port(80)
            netc:on("connect", function(id, re)
                log.info("netc", "connect result", re)
                if re == 1 then
                    netc:send("GET / HTTP/1.0\r\nHost: nutz.cn\r\n\r\n")
                end
            end)
            netc:on("recv", function(id, re)
                log.info("recv", id, #re)
            end)
            if netc:start() == 0 then
                log.info("netc", "start ok")
                sys.waitUntil("NETC_END_" .. netc:id(), 30000)
            else
                log.info("netc", "start fail? why")
            end
            netc:close()
            netc:clean()
        end
    end)
end)


sys.run()
