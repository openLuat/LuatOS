local function normal_lowpower_switch_task()
    gpio.setup(141, 1, gpio.PULLUP) -- LED
    gpio.setup(146, 1, gpio.PULLUP) -- LED
    log.info("LCD_PAGE_TASK_FUNC", "LED 141, 146 已配置为输出模式")
    sys.wait(3000)
    pm.power(pm.WORK_MODE, 1) -- 低功耗
end

sys.taskInit(normal_lowpower_switch_task)
