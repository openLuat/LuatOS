--[[
@module  led_app
@summary 状态灯控制模块，仅手动开关控制
@version 2.0
@date    2026.08.04
@author  江访
@usage
GPIO21(4G灯) + GPIO141(WiFi灯)，高电平亮。
- 订阅 LED_SET_REQUEST(type, state) 手动控制
- type: 1=4G灯, 2=WiFi灯
- state: 1=亮, 0=灭
- require 即注册订阅，无对外接口
]]

local LED_4G_PIN = 21
local LED_WIFI_PIN = 141

local LED_TYPE_4G = 1
local LED_TYPE_WIFI = 2

--[[
LED_SET_REQUEST 订阅回调：设置指定状态灯亮灭

@local
@function on_led_set_request
@param led_type number 灯类型：1=4G灯, 2=WiFi灯
@param state number/boolean 1/true=亮, 0/false=灭
]]
local function on_led_set_request(led_type, state)
    local pin = nil
    if led_type == LED_TYPE_4G then
        pin = LED_4G_PIN
    elseif led_type == LED_TYPE_WIFI then
        pin = LED_WIFI_PIN
    else
        log.warn("led_app", "unknown led type:", led_type)
        return
    end
    local val = (state == 0 or state == false) and 0 or 1
    gpio.set(pin, val)
    log.info("led_app", "LED", led_type, "set to", val)
end

sys.subscribe("LED_SET_REQUEST", on_led_set_request)

log.info("led_app", "init done")
