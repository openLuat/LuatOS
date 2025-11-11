--[[
@module  gpio_output_task
@summary Air8000 演示GPIO输出功能模块
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为 Air8000 开发板演示 GPIO 输出功能的代码示例，核心业务逻辑为：
通过GPIO146控制开发板载网络指示灯（绿灯）实现闪烁效果
1. 初始化GPIO146为输出模式
2. 在任务循环中周期性地拉高/拉低GPIO146
3. 通过500ms亮灭间隔实现简单的闪烁效果
]]

local gpio_number = 146 -- Air8000 开发板上的网络指示灯（绿灯）与GPIO146相连

gpio.setup(gpio_number, 1) -- 设置GPIO146为输出模式

-- 定义任务函数
local function ledlight_task()
    local count = 0
    while 1 do
        -- 闪烁灯程序
        gpio.set(gpio_number, 1)
        log.info("GPIO", "点亮 LED")
        sys.wait(500)--点亮时间 500ms
        gpio.set(gpio_number, 0)
        log.info("GPIO", "熄灭 LED")
        sys.wait(500)--熄灭时间 500ms
        count = count + 1
    end
end

-- 执行闪烁灯任务函数
sys.taskInit(ledlight_task)
