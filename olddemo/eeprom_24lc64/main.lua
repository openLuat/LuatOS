-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "eeprom_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

--[[
    示例里将A0、A1、A2、WP引脚都接地
]]

local eeprom = require "eeprom"

local EEPROM_DEVICE_ADDRESS             =       0x50                    -- i2c设备地址(7bit)
local EEPROM_RegAddr                    =       "\x00\x01"              -- 要写入/读取的EEPROM地址
local dataToWrite                       =       "\xC3\x23\xB1"          -- 要写入的示例数据
local DATA_LEN                          =       3                       -- 读出数据的长度

i2cid       =   0
i2cSpeed    =   i2c.FAST

sys.taskInit(function()
    local code = i2c.setup(i2cid,i2cSpeed)
    while true do
        local res_write = eeprom.writebyte(i2cid,EEPROM_DEVICE_ADDRESS,EEPROM_RegAddr,dataToWrite)
        log.info("transfer write: ",res_write)
        sys.wait(1000)
        local result, rxdata = eeprom.readbyte(i2cid,EEPROM_DEVICE_ADDRESS,EEPROM_RegAddr,DATA_LEN)
        log.info("transfer read: ",result,rxdata:toHex())
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
