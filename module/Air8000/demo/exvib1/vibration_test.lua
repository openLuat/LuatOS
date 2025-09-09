--[[
@module  vibration_test
@summary exvib1扩展库使用demo
@version 1.0
@date    2025.09.5
@author  孟伟
@usage
本demo演示的功能为：
使用Air8000开发板，搭配AirVIBRATING_1000震动小板，演示滚珠震动传感器的使用
本示例主要是展示exvib1库的使用：
]]
local exvib1= require "exvib1"-- 自定义配置启动

-- 震动事件回调
local function vibration_cb(pulse_cnt)
    log.info("VIB", "detected! pulses =", pulse_cnt)
end
--演示最简单的使用方法，都使用默认配置
exvib1.open({
    gpio_pin = 20,
    on_event = vibration_cb,
    })