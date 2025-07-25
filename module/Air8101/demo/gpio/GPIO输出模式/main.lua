-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpio_out"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end


local gpio_number = 0

LED = gpio.setup(gpio_number, 1)

sys.taskInit(function()
    -- 开始呼吸灯
    local count = 0
    while 1 do
        -- 呼吸灯程序
        LED(1)
        log.info("GPIO", "Go Go Go", count, rtos.bsp())
        sys.wait(500)--点亮时间 500ms
        LED(0)
        sys.wait(500)--熄灭时间 500ms
        count = count + 1
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!