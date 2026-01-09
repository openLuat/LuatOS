--[[
@module  key_drv
@summary 按键驱动模块
@version 1.0
@date    2026.01.06
@author  江访
@usage
本文件为按键驱动功能模块，核心业务逻辑为：
1、初始化切换键（GPIO8）和确认键（GPIO9）；
2、配置按键事件的中断处理函数；
3、实现按键防抖功能，防止误触发；
4、对外发布按键消息；

本文件没有对外接口，直接在main.lua中require "key_drv"就可以加载运行；
]]

-- 按键定义
local key_switch = 8 -- GPIO8
local key_confirm = 9  -- GPIO9


-- 按键事件处理函数
local function handle_switch_key(val)
    log.info("handle_switch_key",val)
    if val == 0 then
        sys.publish("KEY_EVENT", "switch_down")
    end
end

local function handle_confirm_key(val)
    log.info("handle_confirm_key",val)

    if val == 0 then
        sys.publish("KEY_EVENT", "confirm_down")
    end
end

--[[
初始化按键GPIO；
配置切换键（GPIO8）和确认键（GPIO9）的GPIO中断；

@api init()
@summary 配置切换键（GPIO8）和确认键（GPIO9）的GPIO中断
@return bool 初始化只会返回true
@usage

]]
local function init()
    gpio.setup(key_switch, handle_switch_key, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(key_switch, 1000, 0) -- 防抖，防止频繁触发

    gpio.setup(key_confirm, handle_confirm_key, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(key_confirm, 1000, 0) -- 防抖，防止频繁触发

    log.info("key_drv", "按键初始化完成，切换键:GPIO8, 确认键:GPIO9")
end

init()