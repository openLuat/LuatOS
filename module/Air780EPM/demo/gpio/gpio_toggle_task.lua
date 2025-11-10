--[[
@module  gpio_toggle
@summary Air780EPM演示波形翻转功能模块
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为 Air780EPM 开发板演示 GPIO 翻转（脉冲）输出的代码示例，核心业务逻辑为：
GPIO 快速翻转测速与波形观测
1. 配置 GPIO27 为输出模式并上拉初始化；
2. 在任务中循环调用 gpio.pulse() 按给定模式输出脉冲序列；
   - 演示模式为 0xA9（二进制 10101001），每次输出 8 组电平变化；
3. 使用示波器或逻辑分析仪连接到 GPIO27，观察翻转波形与频率，翻转一次所需时间大概 50ns；
4. 可根据需要修改 `test_gpio_number`、`0xA9`（翻转模式）和 `8`（组数），以测试不同引脚和模式；
5. 注意：高频翻转请勿直接驱动重负载，推荐用于逻辑检测或带限流的 LED 演示。
]]

local test_gpio_number = 27

gpio.setup(test_gpio_number, 0, gpio.PULLUP)

local function gpiotoggletask()
    sys.wait(100)
    while true do
        sys.wait(100)
        -- 通过GPIO27脚输出输出8组电平变化
        -- 0xA9就是输出的电平高低状态，即 10101001
        gpio.pulse(test_gpio_number, 0xA9, 8, 0)
        log.info("gpio----------->pulse")
    end
end

sys.taskInit(gpiotoggletask)
