--[[
@module  led
@summary LED控制模块
@version 1.0
@date    2025.12.18
@author  马梦阳
@usage
本功能模块为通用LED控制模块，核心业务逻辑为：
1、初始化LED引脚
2、根据通信状态控制LED闪烁或熄灭
3、通信成功时LED轮流闪烁，通信失败时全部熄灭

本文件对外接口：
1、led.init(led_pins) - 初始化LED引脚
2、led.set_comm_status(status) - 设置通信状态
3、led.start() - 启动LED控制任务

使用示例：
local led = require "led"
led.init({26, 27, 28})  -- 初始化LED引脚
led.start()             -- 启动LED任务
led.set_comm_status(true)  -- 设置通信成功，LED开始闪烁
led.set_comm_status(false) -- 设置通信失败，LED全部熄灭
]]

local led = {}

-- LED引脚表
local led_pins = {}
-- 通信状态标志
local comm_success = false
-- LED任务句柄
local led_task_handle = nil

-- 初始化LED引脚
-- @param pins table LED引脚编号表，例如 {26, 27, 28}
function led.init(pins)
    led_pins = pins or {26, 27, 28}
    -- 初始化所有LED引脚为输出，默认熄灭
    for i, pin in ipairs(led_pins) do
        gpio.setup(pin, 0, gpio.PULLDOWN)
    end
    log.info("led", "LED初始化完成，引脚:", table.concat(led_pins, ", "))
end

-- 设置通信状态
-- @param status boolean true表示通信成功，false表示通信失败
function led.set_comm_status(status)
    comm_success = status
end

-- 获取通信状态
-- @return boolean 当前通信状态
function led.get_comm_status()
    return comm_success
end

-- LED闪烁控制函数
local function led_task()
    local current = 1
    
    while true do
        if comm_success then
            -- 通信成功，执行闪烁
            -- 熄灭所有LED
            for i, pin in ipairs(led_pins) do
                gpio.set(pin, 0)
            end
            -- 点亮当前LED
            if #led_pins > 0 then
                gpio.set(led_pins[current], 1)
                
                -- 切换到下一个
                current = current + 1
                if current > #led_pins then
                    current = 1
                end
            end
            
            sys.wait(1000) -- 1s切换一次
        else
            -- 通信未成功，全部熄灭
            for i, pin in ipairs(led_pins) do
                gpio.set(pin, 0)
            end
            sys.wait(100) -- 短暂等待后再次检查
        end
    end
end

-- 启动LED任务
function led.start()
    if led_task_handle then
        log.warn("led", "LED任务已启动，请勿重复启动")
        return
    end
    led_task_handle = sys.taskInit(led_task)
    log.info("led", "LED任务已启动")
end


return led
