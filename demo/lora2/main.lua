--- 模块功能：lorademo
-- @module lora
-- @author Dozingfiretruck
-- @release 2021.06.17

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lorademo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local rtos_bsp = rtos.bsp()

-- spi_id,pin_cs,pin_reset,pin_busy,pin_dio1
local function lora_pin()     
    if rtos_bsp == "AIR101" then
        return 0,pin.PB04,pin.PB00,pin.PB01,pin.PB06
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PB04,pin.PB00,pin.PB01,pin.PB06
    elseif rtos_bsp == "AIR105" then
        return 5,pin.PC14,pin.PE08,pin.PE09,pin.PE06
    elseif rtos_bsp == "ESP32C3" then
        return 2,7,6,11,5
    elseif rtos_bsp == "ESP32S3" then
        return 2,14,15,13,12
    elseif rtos_bsp == "EC618" then
        return 0,8,1,18,19
    elseif rtos_bsp == "EC718P" then
        return 0,8,1,31,32
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id,pin_cs,pin_reset,pin_busy,pin_dio1 = lora_pin() 

sys.taskInit(function()
    spi_lora = spi.deviceSetup(spi_id,pin_cs,0,0,8,10*1000*1000,spi.MSB,1,0)
    lora_device = lora2.init("llcc68",{res = pin_reset,busy = pin_busy,dio1 = pin_dio1},spi_lora)
    print("lora_device",lora_device)
    lora_device:set_channel(433000000)
    lora_device:set_txconfig({mode=1,power=22,fdev=0,bandwidth=0,datarate=9,coderate=4,preambleLen=8,
        fixLen=false,crcOn=true,freqHopOn=0,hopPeriod=0,iqInverted=false,timeout=3000}
    )
    lora_device:set_rxconfig({mode=1,bandwidth=0,datarate=9,coderate=4,bandwidthAfc=0,preambleLen=8,symbTimeout=0,fixLen=false,
        payloadLen=0,crcOn=true,freqHopOn=0,hopPeriod=0,iqInverted=false,rxContinuous=false}
    )

    lora_device:on(function(lora_device, event, data, size)
        log.info("lora", "event", event, lora_device, data, size)
        if event == "tx_done" then
            lora_device:recv(1000)
        elseif event == "rx_done" then
            lora_device:send("PING")
        elseif event == "tx_timeout" then

        elseif event == "rx_timeout" then
            lora_device:recv(1000)
        elseif event == "rx_error" then

        end
    end)

    lora_device:send("PING")

    while 1 do
        print("lora")
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!


