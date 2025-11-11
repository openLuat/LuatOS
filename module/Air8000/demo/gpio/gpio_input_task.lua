--[[
@module  gpio_input_task
@summary Air8000演示GPIO输入检测与LED联动示例
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为Air8000开发板演示GPIO输入检测功能的代码示例，核心业务逻辑为：
1. 初始化GPIO1为输入模式（可用杜邦线接稳压电源，高电平接3.3V，低电平接地）
2. 初始化GPIO146（板载LED）为输出模式，默认高电平（亮）
3. 启用输入消抖，消抖时间50 ms
4. 每500 ms读取一次GPIO1电平，并同步控制LED亮灭
5. 高电平→LED亮，低电平→LED灭
]]

-- 配置gpio1为输入模式
-- 配置GPIO146(即开发板上LED灯)为输出模式

-- 请根据实际需求更改gpio编号和上下拉

local inputpin = 1
local ledpin = 146

local input = gpio.setup(inputpin, nil, gpio.PULLDOWN)
local led = gpio.setup(ledpin, 1)

gpio.debounce(inputpin, 50)
--GPIO1检测到有高低电平输入后，会返回GPIO1当前获取到的电平为高还是低，高返回值为1，低返回值为0
--将这个返回值，传给GPIO146(LED),为0 则GPIO146输出低电平(LED灯灭)，为1则输出高电平(LED灯亮)
-- 定义一个函数用于循环读取输入引脚电平并控制LED灯
local function controlLed()
    local level = 0
    while true do
        level = gpio.get(inputpin)
        log.info("gpio","set netled level: ",level)
        gpio.set(ledpin, level)
        sys.wait(500)
    end
end

sys.taskInit(controlLed)
