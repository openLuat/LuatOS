-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "GPIO_int"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- 请根据实际需求更改GPIO编号和上下拉
local inputpin = 0

--设置GPIO为输入模式
local input = gpio.setup(inputpin,nil)
-- 设置GPIO为上拉输入模式
--GPIO.setup(inputpin, nil, GPIO.PULLUP)
-- 设置GPIO为下拉输入模式
--GPIO.setup(inputpin, nil, GPIO.PULLDOWN)


--循环打印GPIO当前输入状态，为1是高电平，为0是低电平
sys.taskInit(function ()
    while true do
        log.info("GPIO_int 电平输入状态",input())
        sys.wait(999)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!