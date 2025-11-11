--[[
@module  gpio_output_task
@summary GPIO输出功能模块
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为 GPIO 输出功能的代码示例，核心业务逻辑为：
通过GPIO5输出高低电平，可用万用表测量验证
1. 初始化GPIO5为输出模式
2. 在任务循环中周期性地拉高/拉低GPIO5
3. 通过1000ms间隔切换电平，便于万用表观察
]]

local gpio_number = 5

gpio.setup(gpio_number, 1) -- 设置GPIO5为输出模式

local function controlgpio_task()
    -- 开始演示GPIO输出功能
    local count = 0
    while 1 do
        gpio.set(gpio_number, 1)
        log.info("GPIO", "当前IO5电平设置为高",count)
        sys.wait(1000)
        gpio.set(gpio_number, 0)
        log.info("GPIO", "当前IO5电平设置为低")
        sys.wait(1000)
        count = count + 1
    end
end

-- 执行任务函数
sys.taskInit(controlgpio_task)
