--[[
@module  buzzer_app
@summary 蜂鸣器控制，点击响0.5秒
@version 2.0
@date    2026.08.04
@author  江访
@usage
PWM2(PIN98) 驱动蜂鸣器，2700Hz，50%占空比，响0.5秒。
- 订阅 BUZZER_BEEP_REQUEST 触发
- require 即注册订阅，无对外接口
]]

local BUZZER_PWM = 2

--[[
蜂鸣器发声协程：发声0.5秒后自动关闭（含 sys.wait，需放协程）

@local
@function beep_task
]]
local function beep_task()
    pwm.setup(BUZZER_PWM, 2700, 50)
    pwm.start(BUZZER_PWM)
    sys.wait(500)
    pwm.close(BUZZER_PWM)
end

--[[
BUZZER_BEEP_REQUEST 订阅回调：启动蜂鸣器发声协程

@local
@function on_beep_request
]]
local function on_beep_request()
    log.info("buzzer_app", "beep 0.5s")
    sys.taskInit(beep_task)
end

sys.subscribe("BUZZER_BEEP_REQUEST", on_beep_request)

log.info("buzzer_app", "init done")
