--[[
@module  gpio_irq_test
@summary GPIO中断测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板测试GPIO中断功能，主要流程为配置指定IO的触发模式，IO被触发时输出调试信息
]]


-- 配置GPIO中断检测端口
local irq_io_number = 24

function io_irq_handler(level, io_number)
    log.info("gpio", io_number, "被触发", "level=", level)
end

function test_gpio_irq_func()

    -- 配置GPIO为中断模式, 第二参数为function表示中断模式，
    -- 第三参数表示内部上拉输入，第四参数表示下降沿触发中断
    gpio.setup(irq_io_number, io_irq_handler, gpio.PULLUP, gpio.FALLING)
    -- 配置输入IO防抖动参数：100ms
    gpio.debounce(irq_io_number, 100)
    
end


--创建并且启动一个task
--运行这个task的主函数 test_gpio_irq_func
sys.taskInit(test_gpio_irq_func)