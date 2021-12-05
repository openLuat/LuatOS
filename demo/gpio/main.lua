
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

--下面的GPIO引脚编号，请根据实际需要进行更改！
--[[-- v0006及以后版本可用pin方式
local LEDA = gpio.setup(pin.PB08, 0, gpio.PULLUP) -- PB8输出模式
local LEDB = gpio.setup(pin.PB09, 0, gpio.PULLUP) -- PB9输出模式
local LEDC = gpio.setup(pin.PB10, 0, gpio.PULLUP) -- PB10输出模式
]]

local LEDA = gpio.setup(24, 0, gpio.PULLUP) -- PB8输出模式
local LEDB = gpio.setup(25, 0, gpio.PULLUP) -- PB9输出模式
local LEDC = gpio.setup(26, 0, gpio.PULLUP) -- PB10输出模式

sys.taskInit(function()
    local count = 0
    local uid = ""
    if mcu then
        uid = mcu.unique_id():toHex()
    elseif nbiot then
        uid = nbiot.imei()
    end
    while 1 do
        -- 一闪一闪亮晶晶
        LEDA(count & 0x01 == 0x01 and 1 or 0)
        LEDB(count & 0x02 == 0x02 and 1 or 0)
        LEDC(count & 0x03 == 0x03 and 1 or 0)
        log.info("gpio", "Go Go Go", uid, count)
        sys.wait(1000)
        count = count + 1
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
