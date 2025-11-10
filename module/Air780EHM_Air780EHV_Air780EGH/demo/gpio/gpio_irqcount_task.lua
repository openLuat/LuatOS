--[[
@module  gpio_irqcount_task
@summary GPIO中断计数功能
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为GPIO中断计数功能的代码示例，核心业务逻辑为：
1. 配置GPIO24为中断计数模式，用于统计外部信号触发次数
2. 每1秒读取并打印一次中断触发次数
3. 可用杜邦线轻触3.3V电源正极，即可观察中断触发效果。
]]

-- 配置gpio24为中断计数模式
-- 设置好后系统会自动记录中断触发次数。
local gpio_pin = 24
-- gpio.setup(gpio_pin, gpio.count, gpio.PULLUP, gpio.FALLING)
gpio.setup(gpio_pin, gpio.count)

-- 每隔1S统计一次中断触发的次数
local function countIrq()
    while true do
        sys.wait(1000)
        -- 返回从上次调用该函数后到当前时刻的中断触发次数
        log.info("irq cnt", gpio.count(gpio_pin)) -- 调用函数时会自动清空中断累计值
    end
end

sys.taskInit(countIrq)
