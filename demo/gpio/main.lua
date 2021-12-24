
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
-- Air101开发板的3个LED分别为 PB08/PB09/PB10
-- Air103开发板的3个LED分别为 PB24/PB25/PB26

-- 若下载到设备后提示pin库不存在,请升级固件到V0006或以上
local LEDA = gpio.setup(pin.PB08, 0, gpio.PULLUP) -- PB8输出模式,内部上拉
local LEDB = gpio.setup(pin.PB09, 0, gpio.PULLUP) -- PB9输出模式,内部上拉
local LEDC = gpio.setup(pin.PB10, 0, gpio.PULLUP) -- PB10输出模式,内部上拉

sys.taskInit(function()
    local count = 0
    while 1 do
        sys.wait(500)
        -- 一闪一闪亮晶晶
        LEDA(count & 0x01 == 0x01 and 1 or 0)
        LEDB(count & 0x02 == 0x02 and 1 or 0)
        LEDC(count & 0x03 == 0x03 and 1 or 0)
        log.info("gpio", "Go Go Go", count, rtos.bsp())
        count = count + 1
    end
end)

-- API文档 https://wiki.luatos.com/api/gpio.html

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
