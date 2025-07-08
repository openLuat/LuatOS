--[[
@module  breathing_led
@summary PWM呼吸灯效果模块
@version 1.0
@date    2025.07.08
@author  王世豪
@usage
使用Air780EHV核心板的GPIO引脚输出PWM波形，演示呼吸灯效果。
]]

local PWM_ID = 0
local function breathing_led()
    log.info("pwm", "ch", PWM_ID)
    while 1 do
        -- 仿呼吸灯效果
        log.info("pwm", ">>>>>")
        for i = 10, 1, -1 do 
            pwm.open(PWM_ID, 1000, i*9) -- 频率1000hz, 占空比从 90% 递减到 9%
            sys.wait(100 + i*10) 
        end
        for i = 10, 1, -1 do 
            pwm.open(PWM_ID, 1000, 100 - i*9) -- 频率1000hz, 占空比从 10% 递增到 91%
            sys.wait(100 + i*10)
        end
        sys.wait(2000)
    end
end

sys.taskInit(breathing_led)