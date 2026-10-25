--[[
@module  ui_settings
@summary 设置页：亮度、数据模拟开关、坚果烘干参数一览、关于
@version 1.0
@date    2026.10.24
]]
local conf = require "conf"
local theme = require "theme"
local sim = require "sim"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H

local root = nil
local app_ref = nil
local brightSlider = nil
local brightLabel = nil
local simBtn = nil
local curBright = conf.backlight.default

local function apply_bright(v)
    v = math.floor(v + 0.5)
    if v < conf.backlight.min then v = conf.backlight.min end
    if v > 100 then v = 100 end
    curBright = v
    if pwm and pwm.setup then
        pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, v)
        pwm.start(conf.backlight.pwm_ch)
    end
    if brightLabel then brightLabel:set_text(v .. "%") end
    return v
end

local function bright_step(delta)
    apply_bright(curBright + delta)
    if brightSlider then brightSlider:set_value(curBright, true) end
end

local function toggle_sim()
    local paused = not sim.paused()
    sim.set_paused(paused)
    if simBtn then simBtn:set_text(paused and "继续模拟" or "暂停模拟") end
    if app_ref then app_ref.toast(paused and "数据模拟已暂停" or "数据模拟已恢复") end
end

function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 14)

    theme.box(root, 0, 0, SW, 64, 0x1C1209)
    theme.button(root, 16, 14, 104, 36, "返回", 18, C.panel2, C.ink, function()
        theme.defer(function()
            if app_ref then app_ref.close_settings() end
        end)
    end, 10)
    theme.label(root, 136, 14, 400, 36, "系统设置", 26, C.ink)

    -- 亮度
    local c1 = theme.card(root, 40, 88, SW - 80, 128)
    theme.accent_bar(c1, 24, 0, 50, C.amber)
    theme.label(c1, 24, 16, 200, 26, "屏幕亮度", 20, C.ink)
    brightLabel = theme.label(c1, 700, 18, 160, 26, "", 20, C.ink, airui.TEXT_ALIGN_RIGHT)
    theme.button(c1, 24, 58, 60, 40, "-", 20, C.panel2, C.ink, function()
        theme.defer(function() bright_step(-10) end)
    end, 10)
    theme.button(c1, 96, 58, 60, 40, "+", 20, C.panel2, C.ink, function()
        theme.defer(function() bright_step(10) end)
    end, 10)
    local ok, sl = pcall(function()
        return airui.slider({
            parent = c1, x = 176, y = 66, w = 500, h = 24,
            min = conf.backlight.min, max = 100, value = curBright,
            style = {
                bg_color = C.line, bg_opa = 255,
                indicator_color = C.amber, indicator_opa = 255,
                knob_color = 0xFFFFFF, knob_opa = 255,
                knob_border_color = C.amber, knob_border_width = 2,
                radius = 12,
            },
            on_change = function()
                if not brightSlider then return end
                apply_bright(brightSlider:get_value())
            end,
        })
    end)
    brightSlider = ok and sl or nil
    brightLabel:set_text(curBright .. "%")

    -- 模拟开关
    local c2 = theme.card(root, 40, 232, SW - 80, 112)
    theme.label(c2, 24, 16, 300, 26, "数据模拟", 20, C.ink)
    theme.label(c2, 24, 56, 540, 24, "模拟传感器数据实时刷新（温度 / 湿度 / 气体 / 含水率 / 水质）", 14, C.ink3)
    simBtn = theme.button(c2, 680, 40, 220, 48, "暂停模拟", 16, C.orange, 0x1A120C, function()
        theme.defer(toggle_sim)
    end, 12)

    -- 坚果烘干参数一览
    local c3 = theme.card(root, 40, 360, SW - 80, 180)
    theme.label(c3, 24, 16, 500, 26, "坚果烘干参数（推荐温度 / 建议时长）", 20, C.ink)
    for i, nut in ipairs(conf.nuts) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 24 + col * 440
        local y = 58 + row * 40
        theme.label(c3, x, y, 100, 22, nut.name, 16, C.ink2)
        theme.label(c3, x + 110, y, 160, 22,
            string.format("%d~%d °C", nut.temp_min, nut.temp_max), 16, C.amber)
        theme.label(c3, x + 290, y, 130, 22,
            string.format("%d 小时", nut.hours), 16, C.ink2, airui.TEXT_ALIGN_RIGHT)
    end

    theme.label(root, 40, 556, 700, 22,
        string.format("%s v%s · Air8607 1024×600 · 模拟演示", conf.name, conf.version), 13, C.ink3)
end

function M.destroy()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    brightSlider, brightLabel, simBtn = nil, nil, nil
end

return M
