
sys.taskInit(function()
    while true do
        gpio.setup(27, 1)
        sys.wait(1000)
        gpio.setup(27, 0)
        sys.wait(1000)
    end
end)

gpio.setup(37, function()
    log.info("GPIO37 被触发")
end,gpio.PULLDOWN,gpio.RISING)

gpio.setup(38, function()
    log.info("GPIO38 被触发")
end,gpio.PULLDOWN,gpio.RISING)

gpio.setup(39, function()
    log.info("GPIO39 被触发")
end,gpio.PULLDOWN,gpio.RISING)