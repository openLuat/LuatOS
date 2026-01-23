--[[
@module  ble_lowpower
@summary WiFi和蓝牙控制模块
@version 1.0
@date    2026.01.22
@author  王世豪
@usage
控制WiFi和蓝牙的开启和关闭
说明：Air8000的蓝牙功能依赖WiFi协处理器，所以关闭WiFi后，蓝牙功能也会被关闭。
     pm.power(pm.WIFI, 0) -- 关闭WiFi
     pm.power(pm.WIFI, 1) -- 开启WiFi

注意：
    1. 本模块会在后台运行，每300秒关闭一次WiFi，再等待300秒开启WiFi。
    2. 本模块会发布"WIFI_STATE_CHANGED"消息，用于通知其他模块WiFi状态的改变。
    3. 关闭WiFi后，蓝牙功能也会被关闭，还有以下功能均会失效：
    （1）WiFi芯片的GPIO（大于100的GPIO）无法使用，再次开启WiFi后，如需使用需要重新初始化GPIO。
    （2）WiFi芯片的串口（uart10,11,12）无法使用，再次开启WiFi后，如需使用需要重新初始化串口。

本文件没有对外接口，直接在main.lua中require "ble_lowpower"就可以加载运行。
]]

local function ble_lowpower()
    while true do
        sys.wait(300000)  -- 等待300秒
        
        -- 关闭WiFi并发布消息
        pm.power(pm.WIFI, 0) 
        sys.publish("WIFI_STATE_CHANGED", 0) 
        log.info("ble_lowpower", "发布: WiFi状态 -> 0")
        
        sys.wait(300000)  -- 等待300秒
        
        -- 开启WiFi并发布消息
        pm.power(pm.WIFI, 1) 
        sys.publish("WIFI_STATE_CHANGED", 1) 
        log.info("ble_lowpower", "发布: WiFi状态 -> 1")
    end
end

sys.taskInit(ble_lowpower)