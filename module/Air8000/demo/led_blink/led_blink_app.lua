--[[
@module  led_blink_app
@summary led_blink_app应用功能模块 
@version 1.0
@date    2025.11.21
@author  沈园园
@usage
本文件为led_blink应用功能模块，核心业务逻辑为：
1、控制核心板上的网络灯1秒闪烁1次；

本文件没有对外接口，直接在main.lua中require "led_blink_app"就可以加载运行；
]]


-- 默认灯状态为off
local led = "off"
--设置演示所用的灯为网络指示GPIO21，初始化电平为低
local netled = 21
gpio.setup(netled, 0)

local function led_blink_task_func()
    while true do
        -- 打印灯状态
        log.info("led_blink_app led：", led)
        if led == "off" then
            gpio.setup(netled, 1)
            led = "on"            
        else
            gpio.setup(netled, 0)
            led = "off"                  
        end
        sys.wait(1000)
    end
end

--创建一个task，并且运行task的主函数led_blink_task_func
sys.taskInit(led_blink_task_func)
