--[[
@module  room_sensor
@summary 房间温湿度：优先读真实传感器，没有传感器时用「室内外温差模型」给演示值
@version 1.0
@date    2026.11.08

=== 为什么默认是模型值 ===
Air8605 出厂底板没有板载温湿度传感器，读不到就显示 "--" 会让右下角长期空着。
所以默认 model = "none"，用室外温度 + 室内外温差模型算一个稳定的演示值，
现场再加传感器时把 conf.sensor.model 改成 "aht20"（或给 M.reader 赋函数）即可。

=== 接自己的传感器 ===
    local room = require "room_sensor"
    room.reader = function() return 24.6, 55.2 end   -- 温度℃, 湿度%
返回 nil 表示本次读取失败，会自动退回模型值。
]]

local conf = require "conf"

local M = {}

M.reader = nil          -- 可覆盖：function() -> temp, humi

local last_temp, last_humi = nil, nil

-- ==================== AHT20（可选） ====================
local function aht20_read()
    local id, addr = conf.sensor.i2c_id, conf.sensor.addr
    local function wr(bytes)
        return i2c.send(id, addr, string.char(table.unpack(bytes)))
    end
    local function rd(n)
        return i2c.recv(id, addr, n)
    end

    pcall(i2c.setup, id, 100 * 1000)

    -- 上电校准：0xBE 0x08 0x00，等 40ms
    wr({ 0xBE, 0x08, 0x00 })
    sys.wait(40)

    -- 触发测量：0xAC 0x33 0x00，等 80ms
    wr({ 0xAC, 0x33, 0x00 })
    sys.wait(80)

    local data = rd(7)
    if type(data) ~= "string" or #data < 7 then return nil end
    local b = { string.byte(data, 1, 7) }
    if b[1] % 2 == 1 then return nil end          -- bit0=1 表示忙

    local raw_h = (b[2] * 65536 + b[3] * 256 + b[4]) / 1048576 * 100
    local raw_t = ((b[5] % 16) * 65536 + b[6] * 256 + b[7]) / 1048576 * 200 - 50
    return raw_t, raw_h
end

-- ==================== 演示模型 ====================
-- 室内比室外暖，且一天里有一次缓慢起伏（空调/日照的滞后效果）。
local function model_read(outdoor_temp, hour_f)
    local out = outdoor_temp or 20
    local h = hour_f or 12
    local target = out + 7 + 2.2 * math.sin((h - 9) / 24 * math.pi * 2)
    if target < 16 then target = 16 end
    if target > 30 then target = 30 end
    local humi = 58 - (target - 24) * 1.8
    if humi < 35 then humi = 35 end
    if humi > 72 then humi = 72 end
    return target, humi
end

--- 读取房间温湿度
---@param outdoor_temp number 室外温度（模型值用）
---@param hour_f number 当前时刻（小时，带小数）
---@return number|nil temp, number|nil humi
function M.read(outdoor_temp, hour_f)
    local t, h

    if type(M.reader) == "function" then
        local ok, a, b = pcall(M.reader)
        if ok and a then t, h = a, b end
    end

    if not t and conf.sensor.model == "aht20" then
        local ok, a, b = pcall(aht20_read)
        if ok and a then t, h = a, b end
    end

    if not t then
        t, h = model_read(outdoor_temp, hour_f)
    end

    -- 一阶平滑：读数（尤其真实传感器）小幅抖动没必要全画到屏上
    if last_temp then
        t = last_temp + (t - last_temp) * 0.35
        h = last_humi + (h - last_humi) * 0.35
    end
    last_temp, last_humi = t, h
    return math.floor(t + 0.5), math.floor(h + 0.5)
end

return M
