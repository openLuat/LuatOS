
--当前正在测试的GPIO ID
local gpio_id
--当前正在测试的GPIO ID对应的可以输出高低电平的函数
local gpio_output_func

local function gpio_test_task_func()
    while true do
        if gpio_id then
            if not gpio_output_func then
                gpio_output_func = gpio.setup(gpio_id, 1)
            end
            gpio_output_func(1)
            log.info("gpio test", gpio_id, "output 1")
            sys.wait(1000)
        end

        if gpio_id then
            if not gpio_output_func then
                gpio_output_func = gpio.setup(gpio_id, 0)                
            end
            gpio_output_func(0)
            log.info("gpio test", gpio_id, "output 0")
        end

        sys.wait(1000)
    end
end

local function gpio_id_update(id)
    if gpio_output_func then
        gpio.close(gpio_id)
        gpio_output_func = nil
    end
    gpio_id = id
end

sys.subscribe("GPIO_TEST_IND", gpio_id_update)

sys.taskInit(gpio_test_task_func)

