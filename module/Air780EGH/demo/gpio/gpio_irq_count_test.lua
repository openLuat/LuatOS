--[[
@module  gpio_irq_test
@summary GPIO中断计数测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板测试GPIO中断计数功能，主要流程为配置指定PIN脚IO输出1KHz占空比50%的方波波形作为中断信号原，
通过杜邦线连接到使能中断计数的IO管脚，定时统计中断触发的次数。
]]


-- 配置GPIO中断检测端口
local irq_io_number = 24

function test_gpio_irq_count_func()

    -- PIN引脚16，配置PWM4输出波形，并作为信号源将其通过杜邦线连接到PIN引脚20(GPIO24)
    -- 第一参数表示PWM channel4，第二参数表示频率为1000Hz，第三参数表示占空比为50%
    pwm.open(4,1000,50)

    -- 配置GPIO为中断计数模式, 第二参数为gpio.count表示中断计数模式，
    gpio.setup(irq_io_number, gpio.count)
    
    --每隔1S统计一次中断触发的次数
    while true do
        sys.wait(1000)
        log.info("irq cnt", gpio.count(irq_io_number))
    end
    
end


--创建并且启动一个task
--运行这个task的主函数 test_gpio_irq_count_func
sys.taskInit(test_gpio_irq_count_func)