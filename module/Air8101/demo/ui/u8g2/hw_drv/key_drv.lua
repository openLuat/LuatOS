--[[
@module  key_drv
@summary 按键驱动模块
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为按键驱动功能模块，核心业务逻辑为：
1、初始化切换键（GPIO8）和确认键（GPIO5）；
2、配置按键事件的中断处理函数；
3、实现按键防抖功能，防止误触发；
4、对外发布按键消息；

本文件没有对外接口，直接在main.lua中require "key_drv"就可以加载运行；
]]

-- 按键定义
local key_switch = 8 -- GPIO8
local key_confirm = 5  -- GPIO5


-- 按键事件处理函数
local function handle_switch_key(val)

    if val == 0 then
        sys.publish("KEY_EVENT", "switch_down")
    else
        sys.publish("KEY_EVENT", "switch_up")
    end
end

local function handle_confirm_key(val)

    if val == 0 then
        sys.publish("KEY_EVENT", "confirm_down")
    else
        sys.publish("KEY_EVENT", "confirm_up")
    end
end

--[[
初始化按键GPIO；
配置切换键（GPIO8）和确认键（GPIO5）的GPIO中断；

@api init()
@summary 配置切换键（GPIO8）和确认键（GPIO5）的GPIO中断
@return bool 初始化只会返回true
@usage

]]
local function init()
    gpio.setup(key_switch, handle_switch_key, gpio.PULLUP, gpio.BOTH)
    gpio.debounce(key_switch, 100, 0) -- 防抖，防止频繁触发

    gpio.setup(key_confirm, handle_confirm_key, gpio.PULLUP, gpio.BOTH)
    gpio.debounce(key_confirm, 100, 0) -- 防抖，防止频繁触发

    log.info("key_drv", "按键初始化完成，切换键:GPIO8, 确认键:GPIO5")
end

init()