
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "echo"
VERSION = "1.0.0"

local sys = require "sys"

sys.taskInit(function()
    while 1 do
        log.info("netc", "test loop ...")
        while not nbiot.isReady() do
            log.info("netc", "wait for ready ...")
            sys.wait(1000)
        end
        log.info("netc", "call socket.tcp()")
        local netc = socket.tcp()
        netc:host("39.105.203.30") -- modbus server
        netc:port(19001)
        netc:on("connect", function(id, re)
            log.info("netc", "connect", id, re)
            local data = json.encode({imei=nbiot.imei(),rssi=nbiot.rssi(),iccid=nbiot.iccid()})
            log.info("netc", "send reg package", data)
            netc:send(data)
        end)
        netc:on("recv", function(id, data)
            log.info("netc", "recv", id, data)
            netc:send(data)
        end)
        if netc:start() == 0 then
            log.info("netc", "netc start successed!!!")
            local tcount = 0
            while netc:closed() == 0 do
                tcount = tcount + 1
                if tcount > 60 then
                    netc:send(string.char(0))
                    tcount = 0
                end
                sys.wait(1000)
                log.debug("netc", "wait for closed", netc:closed() == 0)
            end
            log.info("netc", "socket closed?")
        end
        log.info("netc", "socket is closed, clean up")
        netc:clean()
        netc:close()
        sys.wait(10000)
    end
end)

sys.run()
