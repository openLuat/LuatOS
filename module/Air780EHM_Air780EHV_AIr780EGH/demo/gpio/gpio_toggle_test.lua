--[[
@module  gpio_toggle_test
@summary GPIO翻转测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板测试GPIO的IO翻转时间，通过gpio.pulse输出指定脉冲变化的波形，使用示波器或逻辑分析仪来测量脉冲电平翻转的时间
]]

-- 配置输出pulse的GPIO端口
local pulse_io_number = 27

function test_gpio_toggle_func()

    -- 配置GPIO为输出模式，初始输出低电平
    gpio.setup(pulse_io_number, 0)
    
    while 1 do
        -- 通过测试的GPIO27 输出指定的脉冲信号
        -- 结合脉冲高低变化可以评估IO翻转时间，使用示波器或逻辑分析仪来测量电平翻转的时间
        -- 第三参数表示输出8组电平变化，每组1或0表示高和低电平
        -- 第二参数0xA9就是输出的电平高低状态，即 10101001
        -- 第四参数表示每个电平的延时保持时间，0代表无延时
        gpio.pulse(pulse_io_number, 0xA9, 8, 0)
        
        -- 打印运行打印信息
        log.info("gpio----------->pulse")
        sys.wait(100)
    end
end


--创建并且启动一个task
--运行这个task的主函数 test_gpio_toggle_func
sys.taskInit(test_gpio_toggle_func)