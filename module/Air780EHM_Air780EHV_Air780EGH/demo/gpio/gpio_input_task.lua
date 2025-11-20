--[[
@module  gpio_input_task
@summary GPIO输入检测与LED联动示例
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为GPIO输入检测功能的代码示例，核心业务逻辑为：
1. 初始化GPIO24为输入模式（可用杜邦线接稳压电源，高电平接3.3V，低电平接地）
2. 初始化GPIO26为输出模式，默认高电平
3. 启用输入消抖，消抖时间50 ms
4. 每500 ms读取一次GPIO24电平
5. 打印并将采集到的电平设置到GPIO26
]]

-- 配置gpio24为输入模式
-- 配置GPIO26为输出模式
local inputpin = 24
local ledpin = 26

gpio.setup(inputpin, nil, gpio.PULLDOWN)
gpio.setup(ledpin, 1)

gpio.debounce(inputpin, 50)
--GPIO24检测到有高低电平输入后，会返回GPIO24当前获取到的电平为高还是低，高返回值为1，低返回值为0
--将这个返回值，传给GPIO26,为0 则GPIO26输出低电平，为1则输出高电平
local function controlgpio()
    local level = 0
    while true do
        level = gpio.get(inputpin)
        log.info("gpio","set netled level: ",level)
        gpio.set(ledpin, level)
        sys.wait(500)
    end
end

sys.taskInit(controlgpio)
