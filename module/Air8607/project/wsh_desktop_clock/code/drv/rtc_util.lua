--[[
@module  rtc_util
@summary 时间读取与校时：硬件 RTC 读写（含时区不对称补偿）
@author  王世豪
@version 1.1
@date    2026.10.26

=== 时区不对称补偿（照 factory/settings_time_app.lua 的做法）===
固件上 os.date("*t", ts) 显示的是 ts 加上时区偏移后的钟面，
而 os.time({日历}) 按 mktime 本地域折算，两者不对称。
先用当前时刻量出差值 bias，写时间时反向补偿，保证界面显示的正好是用户输入的钟面。
]]
local conf = require "conf"

local M = {}

local rtc_lib = nil

--[[探测 rtc 库（全局核心库，无需 require）
注意：LuatOS 的库有的是 rotable，type() 返回的是 userdata 而不是 table，
所以这里只判「非 nil 且有 set 方法」，绝不能用 type(x) == "table" 去卡，
否则会把明明存在的 rtc 误判成不存在。
]]
local function detect_rtc()
    local ok_g, has_set = pcall(function()
        return rtc ~= nil and type(rtc.set) == "function"
    end)
    if ok_g and has_set then return rtc end
    return nil
end

--[[量出 os.time 与 os.date 之间的时区折算差（秒）]]
local function tz_bias()
    local ok, bias = pcall(function()
        local now = tonumber(os.time())
        local shown = os.date("*t", now)
        local back = os.time({
            year = shown.year, month = shown.month, day = shown.day,
            hour = shown.hour, min = shown.min, sec = shown.sec,
        })
        return tonumber(back) - now
    end)
    if ok and type(bias) == "number" then return bias end
    return 0
end

--[[初始化：设置 RTC 基准年与时区
@return string "rtc" = 硬件时钟可用 | "none" = 固件无 rtc，只能读不能写
]]
function M.init()
    rtc_lib = detect_rtc()
    log.info("rtc_util", "rtc 探测", "type(rtc) =", type(rtc),
        "set 可用 =", tostring(rtc_lib ~= nil))
    if rtc_lib then
        pcall(rtc_lib.setBaseYear, conf.rtc.base_year)
        pcall(rtc_lib.timezone, conf.rtc.timezone)
        log.info("rtc_util", "校时方式 = 硬件 RTC")
        return "rtc"
    end
    log.warn("rtc_util", "固件无 rtc 库：时间只能读，不能校时")
    return "none"
end

--[[当前时间，返回 os.date 风格的日历表]]
function M.now()
    return os.date("*t")
end

--[[校时：写入硬件 RTC（带时区补偿）
@return boolean ok, string msg
]]
function M.set_time(y, mo, d, h, mi, s)
    if not rtc_lib then
        return false, "固件无系统时钟，无法校时"
    end
    s = s or 0
    local ok_t, ts = pcall(os.time, {
        year = y, month = mo, day = d, hour = h, min = mi, sec = s,
    })
    if not ok_t or not ts then return false, "时间参数无法转换" end

    local target = math.floor(ts - tz_bias())
    local ok = pcall(rtc_lib.set, target)
    if not ok then
        return false, "系统时钟写入失败"
    end
    log.info("rtc_util", "已写入硬件 RTC", os.date("%Y-%m-%d %H:%M:%S", target))
    return true, "已写入系统时钟"
end

return M
