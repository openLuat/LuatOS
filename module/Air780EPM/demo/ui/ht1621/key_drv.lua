--[[
@module  key_drv
@summary 按键驱动模块
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为按键驱动功能模块，核心业务逻辑为：
1、初始化BOOT键和PWR键的GPIO；
2、配置按键事件的中断处理函数；
3、实现按键防抖功能，防止误触发；
4、对外发布按键消息；

本文件没有对外接口，直接在main.lua中require "key_drv"就可以加载运行；
]]

-- 按键定义
local key_boot = 0           -- GPIO0按键（BOOT键）
local key_pwr = gpio.PWR_KEY -- 电源按键


-- 按键事件处理函数
local function handle_boot_key(val)
    -- print("key_boot", val)
    if val == 1 then
        sys.publish("KEY_EVENT", "boot_down")
    else
        sys.publish("KEY_EVENT", "boot_up")
    end
end

local function handle_pwr_key(val)
    -- print("key_pwr", val)
    if val == 1 then
        sys.publish("KEY_EVENT", "pwr_up")
    else
        sys.publish("KEY_EVENT", "pwr_down")
    end
end

--[[
初始化按键GPIO；
配置BOOT键和PWR键的GPIO中断；

@api init()
@summary 配置BOOT键和PWR键的GPIO中断
@return bool 初始化只会返回true
@usage

]]
local function init()
    gpio.setup(key_boot, handle_boot_key, gpio.PULLDOWN, gpio.BOTH)
    gpio.debounce(key_boot, 50, 0) -- 防抖，防止频繁触发

    gpio.setup(key_pwr, handle_pwr_key, gpio.PULLUP, gpio.BOTH)
    gpio.debounce(key_pwr, 50, 0) -- 防抖，防止频繁触发

    log.info("key_drv", "按键初始化完成")
end

init()