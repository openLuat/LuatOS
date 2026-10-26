--[[
@module  ui_settings
@summary 设置页：手动校时（无 NTP，本地 RTC）+ 背光亮度
@author  王世豪
@version 1.0
@date    2026.10.26

=== 为什么必须手动校时 ===
Air8607 没有 4G / WiFi，无法 SNTP 自动授时。RTC 掉电或首次上电后时间可能是
出厂默认值，所以这里用「年/月/日/时/分 + 加减键」直接写 RTC。

=== 校时配方（官方 demo rtc_app.lua 无网络分支确认）===
    rtc.setBaseYear(1900)   -- 必须先设基准年
    rtc.timezone(32)        -- 必须先设东八区（合宙时区单位 15 分钟，8h = 32）
    rtc.set(时间戳)          -- 传时间戳，避开 rtc.set({mon=}) 与 os.time({month=}) 键名差异
]]
local conf = require "conf"
local theme = require "theme"
local du = require "date_util"
local settings = require "settings"
local rtc_util = require "rtc_util"

local M = {}

local C = theme.C
local SW, SH = conf.W, conf.H

local root = nil
local lb_vals = {}
local lb_msg = nil
local lb_bright = nil
local bright = nil

-- 当前正在编辑的时间
local f = { year = 2026, mon = 10, day = 26, hour = 0, min = 0 }
-- 只有用户真的按过 +/- 才允许保存：
-- 界面刚建好时虚拟输入设备可能误触发一次点击，没改动就不该写时间
local dirty = false

local FIELDS = {
    { key = "year", name = "年", min = 2000, max = 2099 },
    { key = "mon",  name = "月", min = 1,    max = 12 },
    { key = "day",  name = "日", min = 1,    max = 31 },
    { key = "hour", name = "时", min = 0,    max = 23 },
    { key = "min",  name = "分", min = 0,    max = 59 },
}

M.on_back = nil

-- ==================== 内部 ====================
local function fix_day_max()
    local dim = du.days_in_month(f.year, f.mon)
    if f.day > dim then f.day = dim end
end

local function read_from_rtc()
    local t = rtc_util.now()
    if not t then return end
    f.year, f.mon, f.day = t.year, t.month, t.day
    f.hour, f.min = t.hour, t.min
end

local function refresh_ui()
    for i, def in ipairs(FIELDS) do
        if lb_vals[i] then
            lb_vals[i]:set_text(string.format("%s   %04d", def.name, f[def.key]))
        end
    end
    if lb_bright then
        lb_bright:set_text(string.format("亮度   %d%%", bright or conf.backlight.default))
    end
end

local function adjust(def, delta)
    f[def.key] = f[def.key] + delta
    if f[def.key] < def.min then f[def.key] = def.min end
    if f[def.key] > def.max then f[def.key] = def.max end
    fix_day_max()
    dirty = true
    refresh_ui()
end

--[[把编辑好的时间写进 RTC]]
local function do_save()
    if not dirty then
        if lb_msg then lb_msg:set_text("时间没改动，无需保存") end
        return
    end
    local ok, msg = rtc_util.set_time(f.year, f.mon, f.day, f.hour, f.min, 0)
    dirty = false
    if lb_msg then lb_msg:set_text(msg or (ok and "已校时" or "校时失败")) end
    log.info("settings", "校时结果", tostring(ok), tostring(msg))
end

-- ==================== 生命周期 ====================
function M.build(parent)
    root = airui.container({
        parent = parent, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, color_opacity = 252, radius = 0, border_width = 0,
    })
    theme.label(root, 60, 30, 420, 48, "设置（手动校时）", 34, C.ink)

    local y = 104
    for i, def in ipairs(FIELDS) do
        theme.label(root, 150, y, 64, 46, def.name, 26, C.ink2)
        lb_vals[i] = theme.label(root, 230, y, 180, 46, "", 30, C.ink, airui.TEXT_ALIGN_CENTER)
        theme.button(root, 430, y, 56, 46, "-", 28, function()
            theme.defer(function() adjust(def, -1) end)
        end)
        theme.button(root, 500, y, 56, 46, "+", 28, function()
            theme.defer(function() adjust(def, 1) end)
        end)
        y = y + 58
    end

    -- 亮度
    theme.label(root, 150, y + 4, 64, 46, "光", 26, C.ink2)
    lb_bright = theme.label(root, 230, y + 4, 180, 46, "", 30, C.gold, airui.TEXT_ALIGN_CENTER)
    theme.button(root, 430, y + 4, 56, 46, "-", 28, function()
        theme.defer(function()
            bright = settings.set_brightness((bright or conf.backlight.default) - 10)
            refresh_ui()
        end)
    end)
    theme.button(root, 500, y + 4, 56, 46, "+", 28, function()
        theme.defer(function()
            bright = settings.set_brightness((bright or conf.backlight.default) + 10)
            refresh_ui()
        end)
    end)

    -- 操作按钮
    theme.button(root, 620, 104, 168, 52, "读取当前", 22, function()
        theme.defer(function() read_from_rtc(); refresh_ui() end)
    end)
    theme.button(root, 620, 170, 168, 52, "保存校时", 22, function()
        theme.defer(do_save)
    end)
    theme.button(root, 620, 236, 168, 52, "返回", 22, function()
        theme.defer(function() if M.on_back then M.on_back() end end)
    end)

    lb_msg = theme.label(root, 620, 310, 380, 44, "", 20, C.ink2)
    M.hide()
    return root
end

function M.show()
    if not root then return end
    read_from_rtc()
    dirty = false
    bright = settings.get_brightness()
    if lb_msg then lb_msg:set_text("") end
    refresh_ui()
    root:set_hidden(false)
end

function M.hide()
    if root then root:set_hidden(true) end
end

return M
