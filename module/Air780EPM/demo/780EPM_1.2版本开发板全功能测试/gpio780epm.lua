-- LED引脚判断赋值结束
local P1, P2, P3 = 1, 2, 16 --给这三个开发板引出的不连续的GPIO编号单独取出来

sys.taskInit(function()
    while 1 do
        sys.wait(500) -- 置高时间
        -- 先给这些GPIO置高
        log.info("gpio1/2/16/20-33设置为高电平")
        gpio.setup(P1, 1)
        gpio.setup(P2, 1)
        gpio.setup(P3, 1)
        for i = 20, 33 do
            gpio.setup(i, 1)
        end
        sys.wait(500)
        -- 等待500ms后再将这些GPIO电平反转
        log.info("gpio1/2/16/20-33设置为低电平")
        gpio.toggle(P1)
        gpio.toggle(P2)
        gpio.toggle(P3)
        for i = 20, 33 do
            gpio.toggle(i)
        end

    end
end)
