--[[
@module  gpio_pullupdown_test
@summary GPIO输入的上拉下拉测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板测试GPIO输入模式上拉和下拉模式的电平状态
]]

-- 定义输入上拉模式的端口GPIO7
local gpio_pullup_number = 7
-- 定义输入下拉模式的端口GPIO27
local gpio_pulldown_number = 27

function test_gpio_pullupdown_func()

    -- 设置GPIO输入上拉模式
    gpio.setup(gpio_pullup_number, nil, gpio.PULLUP)
    -- 配置输入检测防抖50ms
    gpio.debounce(gpio_pullup_number, 50)

    -- 设置GPIO输入下拉模式
    gpio.setup(gpio_pulldown_number, nil, gpio.PULLDOWN)
    -- 配置输入检测防抖50ms
    gpio.debounce(gpio_pulldown_number, 50)
    
    while 1 do
        -- 打印获取端口当前的电平状态
        log.info("GPIO",gpio_pullup_number,"电平",gpio.get(gpio_pullup_number))
        log.info("GPIO",gpio_pulldown_number,"电平",gpio.get(gpio_pulldown_number))
       
        sys.wait(1000)
    end
end


--创建并且启动一个task
--运行这个task的主函数 test_gpio_pullupdown_func
sys.taskInit(test_gpio_pullupdown_func)