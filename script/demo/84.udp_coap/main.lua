
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "luatos_air640w_udp"
VERSION = "1.0.0"

local sys = require "sys"

wlan.connect("uiot", "12345678")

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            sys.wait(2000)
            local netc = socket.udp()
            netc:host("coap.vue2.cn")
            netc:port(5683)
            netc:on("connect", function(id, re)
                log.info("udp", "connect ok", id, re)
                if re then
                    local data = libcoap.new(libcoap.GET, "time"):rawdata()
                    log.info("coap", "send", data:toHex())
                    netc:send(data)
                end
            end)
            netc:on("recv", function(id, data)
                log.info("udp", "recv", data:toHex())
                if #data >= 4 then
                    local _coap = libcoap.parse(data)
                    if _coap then
                        log.info("coap", "type", _coap:tp())
                        log.info("coap", "code", _coap:code())
                        log.info("coap", "msgid", _coap:msgid())
                        log.info("coap", "data", _coap:data())
                    end
                end
            end)
            if netc:start() == 0 then
                while netc:closed() == 0 do
                    sys.waitUntil("NETC_END_" .. netc:id(), 30000)
                    if netc:closed() == 0 then
                        log.info("udp", "send heartbeat")
                        local data = libcoap.new(libcoap.GET, "time"):rawdata()
                        log.info("coap", "send", data:toHex())
                        netc:send(data)
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

-- 结尾总是这一句哦
sys.run()
