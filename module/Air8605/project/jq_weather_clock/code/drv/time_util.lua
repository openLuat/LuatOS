--[[
@module  time_util
@summary 时间读取（RTC 基准年 + 时区）与「加速一天」演示模式
@version 1.0
@date    2026.11.08

=== 两个必须（照官方 demo/rtc 的配方）===
rtc.setBaseYear(1900) 不设 → 时间戳换算基准不对
rtc.timezone(32)      不设 → 本地时间差 8 小时（合宙时区单位是 15 分钟）

=== 加速模式 ===
conf.time.demo_day_seconds > 0 时，把 24 小时压缩成这么多秒，
画面上就能在几分钟内看完「天亮 → 天黑 → 天亮」的完整循环。
真机部署请保持 0（跟随真实时钟）。
]]

local conf = require "conf"
local lunar = require "lunar"

local M = {}

local WD = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }
local FAST = (conf.time.demo_day_seconds or 0) > 0
local base_ts, base_ms = 0, 0
local last_ts = 0

-- 农历一天只变一次，按 年-月-日 缓存，避免 10fps 下每帧都跑一遍换算
local lunar_key, lunar_val, lunar_gz = "", "", ""

--[[加速模式用的毫秒时钟。和 ui_main.now_ms 同一口径：
mcu.ticks() 在 Air1602 上约 20ms/tick，当毫秒用会让"一天"变成 480 小时。]]
local function now_ms()
    if mcu and mcu.ticks2 then
        local ok, s, us = pcall(mcu.ticks2, 0)
        if ok and type(s) == "number" then
            return s * 1000 + (tonumber(us) or 0) / 1000
        end
    end
    local ok, v = pcall(mcu.ticks)
    if not ok or type(v) ~= "number" then return nil end
    local hz = 1000
    if mcu and mcu.hz then
        local ok2, h = pcall(mcu.hz)
        if ok2 and type(h) == "number" and h > 0 then hz = h end
    end
    return v * 1000 / hz
end

function M.init()
    pcall(function() rtc.setBaseYear(conf.time.base_year) end)
    pcall(function() rtc.timezone(conf.time.timezone) end)
    base_ts = os.time()
    last_ts = base_ts
    base_ms = now_ms() or 0
    log.info("time_util", "时间基准", os.date("%Y-%m-%d %H:%M:%S", base_ts),
        FAST and ("加速模式: 一天 = " .. conf.time.demo_day_seconds .. " 秒") or "跟随真实时钟")
end

--- 当前时间戳（加速模式下按毫秒推进虚拟时钟）
local function now_ts()
    if not FAST then
        local ok, t = pcall(os.time)
        if ok and type(t) == "number" and t > 0 then
            last_ts = t
        end
        return last_ts
    end
    local span = conf.time.demo_day_seconds
    local d = (now_ms() or 0) - base_ms
    if d < 0 then d = 0 end                      -- 老固件 ticks 回绕时不要倒着走
    return base_ts + math.floor(d / span * 86400)
end

--[[当前时间
@return table { year, month, day, hour, min, sec, wday, hour_f, hhmm, date_str, wd_str, ts }
        hour_f = 带小数的 24 小时制时刻（画日夜渐变用）
]]
function M.now()
    local ts = now_ts()
    -- os.date 返回的是裸表，不要往上面挂字段（同一张表可能被复用，容易串值），
    -- 组装一张自己的表返回。
    local d = os.date("*t", ts) or {}
    local hour = d.hour or 0
    local min = d.min or 0
    local sec = d.sec or 0
    local y, mo, dy = d.year or 1970, d.month or 1, d.day or 1

    local key = string.format("%d-%d-%d", y, mo, dy)
    if key ~= lunar_key then
        lunar_key = key
        local L = lunar.solar2lunar(y, mo, dy)
        if L then
            lunar_val = L.text
            lunar_gz = L.gz_year
        else
            -- 超出 1900-2100（表范围），留空而不是显示错的农历
            lunar_val, lunar_gz = "", ""
        end
    end

    return {
        ts = ts,
        year = y, month = mo, day = dy, wday = d.wday,
        hour = hour, min = min, sec = sec,
        hour_f = hour + min / 60 + sec / 3600,
        hhmm = string.format("%02d:%02d", hour, min),
        -- 顶部第一行日期：带年份，用短横线分隔省宽度（"2026/11/08 周日"）
        date_str = string.format("%d/%02d/%02d", y, mo, dy),
        wd_str = WD[d.wday or 1],
        lunar = lunar_val,
        lunar_gz = lunar_gz,
    }
end

return M
