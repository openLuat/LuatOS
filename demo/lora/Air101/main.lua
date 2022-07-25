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

--[[
SPI0
SPI0_SCK                (PB2)
SPI0_MISO               (PB3)
SPI0_MOSI               (PB5)
SPI0_CS                 (PB4)
res                     (PB0)
busy                    (PB1)
dio1                    (PB6)
]]

sys.subscribe("LORA_TX_DONE", function()
    lora.recive(1000)
end)

sys.subscribe("LORA_RX_DONE", function(data, size)
    log.info("LORA_RX_DONE: ", data, size)
    lora.send("PING")
end)

sys.subscribe("LORA_RX_TIMEOUT", function()
    lora.recive(1000)
end)

sys.taskInit(function()

    lora.init("llcc68",{id = 0,cs = pin.PB04,res = pin.PB00,busy = pin.PB01,dio1 = pin.PB06})

    lora.set_channel(433000000)

    lora.set_txconfig("llcc68",
    {mode=1,power=22,fdev=0,bandwidth=0,datarate=9,coderate=4,preambleLen=8,
        fixLen=false,crcOn=true,freqHopOn=0,hopPeriod=0,iqInverted=false,timeout=3000}
    )
    lora.set_rxconfig("llcc68",
    {mode=1,bandwidth=0,datarate=9,coderate=4,bandwidthAfc=0,preambleLen=8,symbTimeout=0,fixLen=false,
        payloadLen=0,crcOn=true,freqHopOn=0,hopPeriod=0,iqInverted=false,rxContinuous=false}
    )

    lora.send("PING")
    while 1 do
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!


