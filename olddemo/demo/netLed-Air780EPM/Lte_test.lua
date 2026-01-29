--[[
@module  Lte_test
@summary Lte_test测试功能模块
@version 1.0
@date    2025.10.15
@author  马亚丹
@usage
本demo演示的功能为：使用Air780EPM，1.3开发板，GPIO27,即LTE（板子上的NET）指示灯演示亮灭显示。


核心逻辑：

1.初始化LTE,打开LTE指示灯功能；
2.LTE灯状态模拟，通过sys.publish("LTE_LED_UPDATE", 状态)：手动模拟状态触发，控制 LTE 灯的亮灭状态
3.关闭常规LTE灯功能（避免冲突）,演示呼吸灯效果


]]
-- 网络状态指示灯演示示例
-- 注意：需在支持gpio和sys库的环境中运行（如嵌入式Lua开发板）
-- 引入必要模块
local netLed = require("netLed")


-- 初始化Lte引脚（根据实际硬件调整）
-- 初始低电平（灭）
local ltePin = gpio.setup(27, 0, gpio.PULLUP)




-- 模拟LTE灯不同状态的任务
local function ltetest()
    while true do
        -- 打开指示灯功能,开启功能，LTE灯用GPIO27
        netLed.setup(true, 0xffff, 27)
        
        -- 状态1：LTE灯常灭（初始状态）
        log.info("LTE灯状态", "常灭")
        -- 灭
        sys.publish("LTE_LED_UPDATE", false)
        -- 演示效果，维持5秒
        sys.wait(5000)

        -- 状态2：LTE灯常亮
        log.info("LTE灯状态", "常亮")
        -- 亮
        sys.publish("LTE_LED_UPDATE", true)
        -- 演示效果，维持5秒
        sys.wait(5000)

        -- 状态3：LTE灯慢速闪烁（500ms亮/500ms灭）
        log.info("LTE灯状态", "慢速闪烁（500ms亮/500ms灭）")
        -- 演示效果，闪烁5次
        for i = 1, 5 do
            sys.publish("LTE_LED_UPDATE", true)
            sys.wait(500)
            sys.publish("LTE_LED_UPDATE", false)
            sys.wait(500)
        end

        -- 状态4：LTE灯快速闪烁（100ms亮/100ms灭）
        log.info("LTE灯状态", "快速闪烁（100ms亮/100ms灭）")
        -- 演示效果，闪烁10次
        for i = 1, 10 do
            sys.publish("LTE_LED_UPDATE", true)
            sys.wait(100)
            sys.publish("LTE_LED_UPDATE", false)
            sys.wait(100)
        end

        -- 状态5：LTE灯呼吸灯效果（通过渐变模拟）
        log.info("LTE灯状态", "呼吸灯效果")
        -- 先关闭常规LTE灯功能（避免冲突）
        netLed.setup(false, 0xffff, 27)
        -- 自定义呼吸灯逻辑（复用netLed的呼吸灯函数）
        local n = 0
        while n < 10 do
            -- 传入LTE灯引脚
            netLed.setupBreateLed(ltePin)
            -- 呼吸灯循环间隔
            sys.wait(20)
            n = n + 1
        end
    end
end

sys.taskInit(ltetest)
