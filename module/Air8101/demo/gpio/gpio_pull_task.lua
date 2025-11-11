--[[
@module  gpio_pull_task
@summary GPIO上下拉功能模块
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为 GPIO 上下拉功能的代码示例，核心业务逻辑为：
1. 配置GPIO5为上拉输入模式
2. 配置GPIO6为下拉输入模式
3. 定时读取并打印两个GPIO的电平状态
4. 将GPIO5和GPIO6引脚接地或接3.3V来控制GPIO5和GPIO6的电平变化，验证上拉/下拉配置是否生效
]]

local gpio_pin1 = 5
local gpio_pin2 = 6
-- 按键防抖函数
gpio.debounce(gpio_pin1, 50)
gpio.debounce(gpio_pin2, 50)

-- 设置GPIO2引脚为上拉输入模式
gpio.setup(gpio_pin1, nil, gpio.PULLUP)

-- 设置GPIO5引脚为下拉输入模式
gpio.setup(gpio_pin2, nil, gpio.PULLDOWN)

local function gpiopulltask()
    log.info("GPIO",gpio_pin1,"电平",gpio.get(gpio_pin1))
    log.info("GPIO",gpio_pin2,"电平",gpio.get(gpio_pin2))
end

sys.timerLoopStart(gpiopulltask,1000)
