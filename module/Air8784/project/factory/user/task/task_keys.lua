--[[
@module  task_keys
@summary Air8784 任务按键入口
@version 1.2
@date    2026.09.30
@author  王世豪
@usage
GPIO23 拉高提供按键参考电平，GPIO20 为 SOS，GPIO21 为 UP。
SOS 下降沿触发，150ms 防抖，发布 SIP_TASK_PRIMARY（执行任务/接听来电）。
UP 双沿触发，按下启动 1s 定时器：按住超过 1s 视为长按 → 发布 SIP_TASK_STOP（挂断/拒接）；
短按（<1s 松开）为预留动作，当前不处理。由 main.lua 加载，不与其他相同 GPIO 按键模块重复加载。
]]

gpio.setup(23,1)
local function on_sos_pressed()sys.publish("SIP_TASK_PRIMARY")end
gpio.setup(20,on_sos_pressed,gpio.PULLUP,gpio.FALLING)
gpio.debounce(20,150,1)

-- UP：长按(>=1s)挂断，短按预留
local function on_up_long_press()sys.publish("SIP_TASK_STOP")end
local up_long_timer
local function on_up()
    if gpio.get(21) == 0 then
        -- 按下：1s 后若仍按住则判定为长按挂断
        up_long_timer = sys.timerStart(on_up_long_press, 1000)
    else
        -- 松开：未达 1s 为短按（预留，不动作），取消长按判定
        if up_long_timer then sys.timerStop(up_long_timer); up_long_timer = nil end
    end
end
gpio.setup(21,on_up,gpio.PULLUP,gpio.BOTH)
gpio.debounce(21,150,1)
