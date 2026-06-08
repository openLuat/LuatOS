--[[
@module  led.lua
@summary LED模块
@version 1.1
@date    2026.05.20
@author  王城钧
@usage

规则：
  绿 — 传感器更新时脉冲1秒
  红 — 从站收到请求时亮，请求处理完后保持至少500ms再灭

用法：
  led.sensor_ok()   -- 温湿度数据更新 → 绿灯1秒
  led.rtu_req()     -- 收到主站请求   → 红灯亮（最少500ms）
  led.rtu_done()    -- 请求处理完毕   → 触发红灯倒计时

  本文件没有对外接口，直接在main.lua中require "led"就可以加载运行；
]]


local led = {}

local PINS = {27, 28, 26}  -- RED=GPIO27, GREEN=GPIO28, BLUE=GPIO26

local rtu_timer = nil       -- 红灯最小保持定时器
local green_timer = nil

local function off_all()
    for _, p in ipairs(PINS) do gpio.set(p, 0) end
end

local function start_red()
    off_all()
    gpio.set(PINS[1], 1)
end

local function start_green()
    off_all()
    gpio.set(PINS[2], 1)
end

-- 红灯灭
local function red_off()
    if rtu_timer then sys.timerStop(rtu_timer); rtu_timer = nil end
    off_all()
end

-- RTU/TCP从站收到主站请求 → 红灯亮
function led.rtu_req()
    if green_timer then sys.timerStop(green_timer); green_timer = nil end
    start_red()
end

-- 请求处理完毕 → 红灯至少再保持500ms后灭
function led.rtu_done()
    if rtu_timer then sys.timerStop(rtu_timer) end
    rtu_timer = sys.timerStart(function()
        rtu_timer = nil
        off_all()
    end, 500)
end

-- 传感器数据更新 → 绿灯亮1秒
function led.sensor_ok()
    if rtu_timer then return end  -- 红灯还在就不亮绿
    if green_timer then sys.timerStop(green_timer) end
    start_green()
    green_timer = sys.timerStart(function()
        green_timer = nil
        off_all()
    end, 1000)
end

for _, p in ipairs(PINS) do
    gpio.setup(p, 0, gpio.PULLDOWN)
end
off_all()

return led
