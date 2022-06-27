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
HSPI
HSPI_SCK                (PC15)
HSPI_MISO               (PC12)
HSPI_MOSI               (PC13)
HSPI_CS                 (PC14)
res                     (PE08)
busy                    (PE09)
dio1                    (PE06)
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
    lora.init("llcc68",
    {mode=1,bandwidth=0,datarate=9,coderate=4,preambleLen=8,fixLen=false,crcOn=true,freqHopOn=0,hopPeriod=0,iqInverted=false,
        frequency = 433000000, power=22,fdev=0,timeout=3000,  bandwidthAfc=0,symbTimeout=0,payloadLen=0,rxContinuous=false},
    {id = 5,cs = pin.PC14,res = pin.PE08,busy = pin.PE09,dio1 = pin.PE06}
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


