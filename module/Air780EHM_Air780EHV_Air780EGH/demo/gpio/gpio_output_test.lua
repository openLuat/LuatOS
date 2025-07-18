--[[
@module  gpio_output_test
@summary GPIO输出测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板测试GPIO输出功能，主要流程为指定IO口外接LED灯，500ms输出高电平点亮LED，500ms输出低电平熄灭LED，循环执行这个流程
]]

-- 配置外接LED灯的GPIO端口
local led_io_number = 27

function test_gpio_output_func()
    -- 定义运行计数器
    local count = 0
    
    -- 配置GPIO为输出模式
    gpio.setup(led_io_number, 1)
    
    while 1 do
        -- 打印运行计数
        log.info("GPIO", "Go Go Go", count, rtos.bsp())
        
        -- 点亮500ms
        gpio.set(led_io_number, 1)
        sys.wait(500)
        
        -- 熄灭500ms
        gpio.set(led_io_number, 0)
        sys.wait(500)
        
        -- 运行计数器累计加1
        count = count + 1
    end
end


--创建并且启动一个task
--运行这个task的主函数 test_gpio_output_func
sys.taskInit(test_gpio_output_func)