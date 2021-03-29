

PROJECT = "wlandemo"
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

uart.on(1, "receive", function(id, len)
    local data = uart.read(id, 1500)
    if data and #data > 0 then
        log.info("uart", "read", data:toHex())
        sys.publish("NET_WRITE", data)
    end
end)
uart.setup(1, 115200)
sys.subscribe("UART_WRITE", function(id, data)
    if data and #data > 0 then
        uart.write(id, data)
    end
end)

sys.subscribe("NET_READY", function ()
    log.info("net", "NET_READY Get!!!")
end)
sys.taskInit(function()
    while true do
        if not socket.isReady() then
            sys.waitUntil("NET_READY", 1000)
        else
            local netc = socket.tcp()
            -- 请登录netlab获取你的临时tcp端口
            -- https://netlab.luatos.com
            netc:host("112.125.89.8")
            netc:port(37476)
            netc:on("connect", function(id, re)
                log.info("netc", "connect result", re)
                if re == 1 then
                    netc:send("reg," .. lte.imei() .. "," .. lte.iccid() .. "\n")
                end
            end)
            netc:on("recv", function(id, re)
                log.info("recv", id, #re, re)
                if #re == 0 then
                    re = netc:recv(1500)
                end
                if #re > 0 then
                    sys.publish("UART_WRITE", 1, re)
                end
            end)
            if netc:start() == 0 then
                log.info("netc", "start ok")
                local topic = "NETC_END_" .. netc:id()
                while netc:closed() == 0 do
                    local result, data = sys.waitUntil({topic, "NET_WRITE"}, 30000)
                    if result then
                        if data ~= nil and type(data) == "string" then
                            netc:send(data)
                        end
                    else
                        netc:send("ping\n")
                    end
                end
            else
                log.info("netc", "start fail? why")
            end
            netc:close()
            netc:clean()
            sys.wait(15000)
        end
    end
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
