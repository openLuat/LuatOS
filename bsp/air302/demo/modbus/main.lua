
PROJECT = "air302demo"
VERSION = "1.0.0"

local sys = require "sys"
--local console = require "console"
--console.setup(2, 115200)


log.info("hi", _VERSION, VERSION)
log.info("hi", "from main.lua file --------")

-- uart.on(2, "receive", function(id, len)
--     log.info("uart", "receive", uart.read(id, 1024))
-- end)
-- uart.setup(2, 115200)
-- _G.tled = 0
gpio.setup(1, function()
    log.info("gpio", "BOOT button release")
end)
-- gpio.setup(2, 0)
-- gpio.setup(3, 0)
-- gpio.setup(9, 0)
-- gpio.setup(17, 0)
-- gpio.setup(18, 0)
-- gpio.setup(19, 0)
sys.taskInit(function()
    while 1 do
        --log.info("gpio", "LED UP")
        --log.info("gpio", "gpio1", gpio.get(1) == 1)
        --log.info("gpio", "gpio2", gpio.get(2) == 1)
        --log.info("gpio", "gpio3", gpio.get(3) == 1)
        -- log.info("gpio", "gpio9", gpio.get(9, 1) == 1)
        -- log.info("gpio", "gpio17", gpio.get(17, 1) == 1)
        -- log.info("gpio", "gpio18", gpio.get(18, 1) == 1)
        -- log.info("gpio", "gpio19", gpio.get(19, 1) == 1)
        --sys.wait(3000)

        --log.info("gpio", "fuck", "0")
        -- gpio.set(1, 0)
        -- gpio.set(19, 0)
        --sys.wait(1000)
        --log.info("gpio", "fuck", "1")
        -- gpio.set(1, 1)
        -- gpio.set(19, 1)
        --sys.wait(1000)
        -- log.info("pwm", ">>>>>")
        -- for i = 10,1,-1 do 
        --     pwm.open(5, 1000, i*9)
        --     sys.wait(200 + i*10)
        -- end
        -- for i = 10,1,-1 do 
        --     pwm.open(5, 1000, 100 - i*9)
        --     sys.wait(200 + i*10)
        -- end
        -- adc.open(0)
        -- adc.open(1)
        -- adc.open(2)
        -- log.info("adc", "adc0", adc.read(0))
        -- log.info("adc", "adc0", adc.read(1))
        -- log.info("adc", "adc0", adc.read(2))
        -- adc.close(0)
        -- adc.close(1)
        -- adc.close(2)
        --print(1)
        sys.wait(5000)
    end
end)

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
--[[
sys.timerLoopStart(function()
    log.info("hi", _VERSION)
    log.info("nbiot1", "rssi", nbiot.rssiStr())
    log.info("nbiot2", "imsi", nbiot.imsi())
    log.info("nbiot3", "iccid", nbiot.iccid())
    log.info("nbiot4", "imei", nbiot.imei())
    log.info("nbiot5", "net ready?", nbiot.isReady())
end, 10000)
]]

sys.run()
