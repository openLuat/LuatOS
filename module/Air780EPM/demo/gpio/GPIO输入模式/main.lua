-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpio_irq"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- 配置gpio24为输入模式
-- 配置GPIO27(即开发板上LED灯)为输出模式

-- 请根据实际需求更改gpio编号和上下拉

local inputpin = 24
local ledpin = 27

local input = gpio.setup(inputpin,nil)
local led = gpio.setup(ledpin, 1)

gpio.debounce(inputpin, 50)
--GPIO24检测到有高低电平输入后，会返回GPIO24当前获取到的电平为高还是低，高返回值为1，低返回值为0
--将这个返回值，传给GPIO27(LED),为0 则GPIO27输出低电平(LED灯灭)，为1则输出高电平(LED灯亮)
sys.taskInit(function ()
    while true do
        led(input())
        sys.wait(500)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
