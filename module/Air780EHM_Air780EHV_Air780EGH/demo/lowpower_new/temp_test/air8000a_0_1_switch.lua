


local function normal_lowpower_switch_task()
    while true do
        -- sys.wait(5000)
        -- gpio.setup(25, 0) -- 关闭GNSS电源
        gpio.setup(24, 0) -- 关闭三轴电源和gnss备电
        -- gpio.close(33) -- 如果功耗偏高，开始尝试关闭WAKEUPPAD1
        -- gpio.close(35) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要
        log.info("before set lowpower mode")

        -- sys.wait(2000)
        pm.power(pm.WORK_MODE, 1)

        -- sys.wait(20)
        -- airlink.pause(1)

        sys.wait(33360000)

        -- sys.wait(30000)
        -- log.info("before set normal mode")
        -- pm.power(pm.WORK_MODE, 0)

        -- sys.wait(30000)
    end
end

local function normal_lowpower_switch_task1()
    pm.power(pm.WORK_MODE, 1)
end


sys.taskInit(normal_lowpower_switch_task)
-- sys.taskInit(normal_lowpower_switch_task1)