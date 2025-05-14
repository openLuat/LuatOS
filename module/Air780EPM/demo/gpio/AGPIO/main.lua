-- 本示例对比了普通GPIO和AGPIO的进入休眠模式前后的区别。
-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "AGPIO_GPIO_testdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local gpio_number = 1   -- 普通GPIO GPIO号为1，休眠后掉电。
local Agpio_number = 27 -- AGPIO GPIO号为27，休眠后可保持电平。

gpio.setup(gpio_number, 1)
gpio.setup(Agpio_number, 1)

sys.taskInit(function()
    sys.wait(16000)
    -- 关闭USB电源
    pm.power(pm.USB, false)
    -- 进入低功耗模式
    pm.power(pm.WORK_MODE, 3)
    sys.wait(10000)
    pm.power(pm.USB, true)
    pm.power(pm.WORK_MODE, 0)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
