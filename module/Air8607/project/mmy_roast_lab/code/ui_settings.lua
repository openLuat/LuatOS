--[[
@module  ui_settings
@summary ROAST LAB 设置：背光亮度 / 报警阈值 / 演示控制 / 关于
@version 1.0
@date    2026.10.30
]]
local conf = require("conf")
local theme = require("theme")
local sim = require("sim")
local art = require("art")
local app = require("app")

local C, SZ = theme.C, theme.SZ

local M = {}

local function set_brightness(v)
    v = math.max(conf.backlight.min, math.min(100, v))
    pcall(function()
        pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, v)
        pwm.start(conf.backlight.pwm_ch)
    end)
    return v
end

function M.build(p)
    local alive = true
    local U = {}
    local bright = conf.backlight.default

    app.subbar(p, "设置", "显示 · 报警阈值 · 演示控制")

    -- ===================== 显示 =====================
    local dispCard = theme.card(p, 24, 72, 480, 236)
    theme.label(dispCard, 20, 14, 200, 22, "显示", SZ.m, C.ink)
    art.icon(dispCard, "temp", 400, 14, 18, C.copper)
    theme.label(dispCard, 20, 48, 120, 20, "背光亮度", SZ.s, C.ink2)
    U.brightVal = theme.label(dispCard, 300, 48, 160, 20, bright .. "%", SZ.s, C.copper2, theme.RT)
    theme.slider({
        parent = dispCard, x = 20, y = 76, w = 440, h = 16,
        min = conf.backlight.min, max = 100, value = bright,
        bg_color = C.panel3, bg_opa = 255,
        indicator_color = C.copper, indicator_opa = 255,
        knob_color = C.ink, knob_opa = 255,
        knob_border_color = C.copper, knob_border_width = 2,
        on_change = function(s)
            if not alive then return end
            local ok, v = pcall(function() return s:get_value() end)
            if not ok then return end
            bright = set_brightness(v)
            U.brightVal:set_text(bright .. "%")
        end,
    })
    theme.label(dispCard, 20, 100, 440, 16, "亮度经 PWM3（GPIO13）实时生效，不写入配置",
        SZ.xs, C.ink3)
    theme.hline(dispCard, 20, 128, 440, C.line)

    local info = {
        { "屏幕", "10.1 寸 RGB · 1024×600" },
        { "触摸", "GT911 电容 · I2C1 轮询" },
        { "采样周期", conf.sim.interval_ms .. " ms / 点（每点推进 " .. conf.sim.dt_s .. "s）" },
    }
    for i, it in ipairs(info) do
        local y = 142 + (i - 1) * 26
        theme.label(dispCard, 20, y, 120, 20, it[1], SZ.xs, C.ink3)
        theme.label(dispCard, 140, y, 320, 20, it[2], SZ.xs, C.ink2)
    end

    -- ===================== 报警阈值 =====================
    local alarmCard = theme.card(p, 24, 320, 480, 240)
    theme.label(alarmCard, 20, 14, 260, 22, "报警与提示阈值", SZ.m, C.ink)
    theme.label(alarmCard, 20, 14, 440, 22, "主屏右上提示同源", SZ.xs, C.ink3, theme.RT)

    theme.label(alarmCard, 20, 46, 160, 20, "升温过快 ROR", SZ.s, C.ink2)
    U.rorVal = theme.label(alarmCard, 300, 46, 160, 20,
        conf.roast.hint.ror_high .. " °C/min", SZ.s, C.gold, theme.RT)
    theme.slider({
        parent = alarmCard, x = 20, y = 74, w = 440, h = 16,
        min = 15, max = 45, value = conf.roast.hint.ror_high,
        bg_color = C.panel3, bg_opa = 255,
        indicator_color = C.gold, indicator_opa = 255,
        knob_color = C.ink, knob_opa = 255,
        knob_border_color = C.gold, knob_border_width = 2,
        on_change = function(s)
            if not alive then return end
            local ok, v = pcall(function() return s:get_value() end)
            if not ok then return end
            conf.roast.hint.ror_high = v
            U.rorVal:set_text(v .. " °C/min")
        end,
    })

    theme.label(alarmCard, 20, 112, 160, 20, "炉温上限", SZ.s, C.ink2)
    U.etVal = theme.label(alarmCard, 300, 112, 160, 20,
        conf.roast.hint.et_high .. "°C", SZ.s, C.red, theme.RT)
    theme.slider({
        parent = alarmCard, x = 20, y = 140, w = 440, h = 16,
        min = 220, max = 265, value = conf.roast.hint.et_high,
        bg_color = C.panel3, bg_opa = 255,
        indicator_color = C.red, indicator_opa = 255,
        knob_color = C.ink, knob_opa = 255,
        knob_border_color = C.red, knob_border_width = 2,
        on_change = function(s)
            if not alive then return end
            local ok, v = pcall(function() return s:get_value() end)
            if not ok then return end
            conf.roast.hint.et_high = v
            U.etVal:set_text(v .. "°C")
        end,
    })
    theme.label(alarmCard, 20, 172, 440, 16, "阈值越低越早预警；调整后主屏提示立即生效",
        SZ.xs, C.ink3)
    theme.label(alarmCard, 20, 200, 440, 16, "一爆 / 二爆阈值由豆种档案决定，不可在此修改",
        SZ.xs, C.ink3)

    -- ===================== 演示控制 =====================
    local ctrlCard = theme.card(p, 520, 72, 480, 236)
    theme.label(ctrlCard, 20, 14, 260, 22, "演示控制", SZ.m, C.ink)
    U.stateTip = theme.chip(ctrlCard, 380, 12, 80, 24, "运行中", C.green, C.panel3)

    U.btnPause = theme.button(ctrlCard, 20, 52, 200, 48, "暂停推演", { on_click = function()
        if not alive then return end
        local paused = sim.toggle_pause()
        U.btnPause:set_text(paused and "继续推演" or "暂停推演")
        U.stateTip:set(paused and "已暂停" or "运行中", paused and C.gold or C.green)
        app.toast(paused and "推演已暂停" or "推演已继续", C.copper2)
    end })
    theme.ghost(ctrlCard, 236, 52, 200, 48, "复位当前批次", { on_click = function()
        if not alive then return end
        sim.reset()
        app.toast("已复位到待机", C.ink2)
    end })

    theme.hline(ctrlCard, 20, 118, 440, C.line)
    local tips = {
        { "推演加速", "12× · 一炉约 50~65 秒走完" },
        { "曲线窗口", "120 点 × 6s = 12 分钟" },
        { "数据来源", "本地烘焙模型，无外设依赖" },
    }
    for i, it in ipairs(tips) do
        local y = 132 + (i - 1) * 26
        theme.label(ctrlCard, 20, y, 120, 20, it[1], SZ.xs, C.ink3)
        theme.label(ctrlCard, 140, y, 320, 20, it[2], SZ.xs, C.ink2)
    end
    theme.label(ctrlCard, 20, 210, 440, 16, "暂停后曲线与温度全部冻结，便于观察取点",
        SZ.xs, C.ink3)

    -- ===================== 关于 =====================
    local aboutCard = theme.card(p, 520, 320, 480, 240)
    theme.label(aboutCard, 20, 14, 260, 22, "关于 ROAST LAB", SZ.m, C.ink)
    theme.label(aboutCard, 20, 14, 440, 22, "版本 " .. conf.version, SZ.xs, C.ink3, theme.RT)
    theme.label(aboutCard, 20, 46, 440, 60,
        "一屏完成一炉咖啡的完整闭环：入豆、升温、一爆、出豆、冷却、评分、存档与曲线对比。",
        SZ.xs, C.ink2)
    local rows = {
        { "硬件平台", "Air8607（Air1603）" },
        { "界面框架", "AirUI / LVGL9 · 纯 Lua 矢量绘制" },
        { "烘焙模型", "温差驱动 + 炉温惯性 + 入豆吸热" },
        { "目录", "module/Air8607/project/mmy_roast_lab" },
    }
    for i, it in ipairs(rows) do
        local y = 108 + (i - 1) * 26
        theme.label(aboutCard, 20, y, 110, 20, it[1], SZ.xs, C.ink3)
        theme.label(aboutCard, 130, y, 330, 20, it[2], SZ.xs, C.ink2)
    end
    theme.label(aboutCard, 20, 214, 440, 16, "MIT License · openLuat / LuatOS", SZ.xs, C.ink3)

    theme.label(p, 24, 576, 976, 16,
        "设置项仅作用于本次运行 · 重新上电恢复默认值", SZ.xs, C.ink3)

    local page = {}
    page.refresh = function()
        if not alive then return end
        local paused = sim.paused()
        U.stateTip:set(paused and "已暂停" or "运行中", paused and C.gold or C.green)
    end
    page.refresh_clock = function() end
    page.destroy = function() alive = false end
    return page
end

return M
