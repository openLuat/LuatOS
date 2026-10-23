--[[
@module  sip_task_keys
@summary Air8784 任务按键入口
@version 1.1
@date    2026.09.29
@usage
GPIO23 拉高提供按键参考电平，GPIO20 为 SOS，GPIO21 为 UP。
下降沿触发，150ms防抖；SOS发布 SIP_TASK_PRIMARY，UP发布 SIP_TASK_STOP。
由 main.lua 加载，不与其他相同GPIO按键模块重复加载。
]]

gpio.setup(23,1)
local function on_sos_pressed()sys.publish("SIP_TASK_PRIMARY")end
gpio.setup(20,on_sos_pressed,gpio.PULLUP,gpio.FALLING)
local function on_up_pressed()sys.publish("SIP_TASK_STOP")end
gpio.setup(21,on_up_pressed,gpio.PULLUP,gpio.FALLING)
gpio.debounce(20,150,1)
gpio.debounce(21,150,1)
