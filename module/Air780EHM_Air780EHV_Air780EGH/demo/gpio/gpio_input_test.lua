--[[
@module  gpio_input_test
@summary GPIO输出测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板测试GPIO输入功能，主要流程为获取指定IO口的输入电平，根据高电平状态，点亮外接LED灯；根据低电平状态，熄灭外接LED灯
]]

-- 配置外接LED灯的GPIO端口
local led_io_number = 27

-- 配置输入检测的GPIO端口
local input_io_numble = 24

function test_gpio_input_func()

    local input_level
    -- 配置LED GPIO为推挽输出模式，第二参数1表示初始为输出高电平
    gpio.setup(led_io_number, 1)
    -- 配置输入检测的GPIO为输入模式, 第二参数nil表示输入模式，第三参数nil表示浮空输入(未检测到电平时 电平状态不确定)
    gpio.setup(input_io_numble, nil, nil)
    -- 配置输入IO防抖动参数：50ms
    gpio.debounce(input_io_numble, 50)
    
    while 1 do
        -- 获取IO电平，并打印
        input_level = gpio.get(input_io_numble) 
        log.info("GPIO", "input level", input_level)
        
        -- 根据获取的电平来设置LED
        gpio.set(led_io_number, input_level)
        
        -- 延时500ms，循环上面的流程
        sys.wait(500)
    end
end


--创建并且启动一个task
--运行这个task的主函数 test_gpio_input_func
sys.taskInit(test_gpio_input_func)