--[[
@module  gpio_pull_task
@summary Air780EPM演示GPIO上下拉功能模块
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为Air780EPM开发板演示 GPIO 上下拉功能的代码示例，核心业务逻辑为：
1. 配置GPIO7为上拉输入模式
2. 配置GPIO27为下拉输入模式
3. 定时读取并打印两个GPIO的电平状态
4. 将GPIO7和GPIO27引脚接地或接3.3V来控制GPIO7和GPIO27的电平变化，验证上拉/下拉配置是否生效
]]

local gpio_pin1 = 7
local gpio_pin2 = 27
-- 按键防抖函数
gpio.debounce(gpio_pin1, 50)
gpio.debounce(gpio_pin2, 50)

-- 设置GPIO7引脚为上拉输入模式
gpio.setup(gpio_pin1, nil, gpio.PULLUP)

-- 设置GPIO27引脚为下拉输入模式
gpio.setup(gpio_pin2, nil, gpio.PULLDOWN)

local function gpiopulltask()
    log.info("GPIO",gpio_pin1,"电平",gpio.get(gpio_pin1))
    log.info("GPIO",gpio_pin2,"电平",gpio.get(gpio_pin2))
end

sys.timerLoopStart(gpiopulltask,1000)
