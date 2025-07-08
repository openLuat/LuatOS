--[[
@module  pwm_output
@summary PWM输出模块
@version 1.0
@date    2025.07.08
@author  王世豪
@usage
使用Air780EGH核心板的GPIO引脚输出PWM波形，演示不同占空比的PWM波形输出效果。
]]

local PWM_ID = 0
local function pwm_output()
    while true do
        -- 开启pwm通道0，设置脉冲频率为1kHz，分频精度为1000，占空比为10/1000=1% 持续输出
        pwm.open(PWM_ID, 1000, 10, 0, 1000)
        sys.wait(1000)
        -- 开启pwm通道0，设置脉冲频率为1kHz，分频精度为1000，占空比为500/1000=50% 持续输出
        pwm.open(PWM_ID, 1000, 500, 0, 1000)
        sys.wait(1000)
        -- 开启pwm通道0，设置脉冲频率为1kHz，分频精度为1000，占空比为1000/1000=100% 持续输出
        pwm.open(PWM_ID, 1000, 1000, 0, 1000)
        sys.wait(1000)
    end
end

sys.taskInit(pwm_output)