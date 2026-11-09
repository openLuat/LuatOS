--[[
@module  ui_settings
@summary 设置页：在屏上直接设置每路预警值 / 报警值（步进 1.0℃），掉电保存
@version 1.0.0
@date    2026.11.09

约束：
- 阈值单位为工程量（℃），范围 0 ~ val_max；
- 报警值必须大于预警值（自动纠正）；
- 修改立即参与报警判定，点"保存"才写入 fskv。
]]
local M = {}

M.TITLE = "参数设置"

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C
local alarm = require "app_alarm"
local store = require "app_store"
local data = require "app_data"

local STEP = 1.0   -- 温度步进 1.0℃（原来电压量程是 0.10V，同量程 1%）

local function round2(v)
    return math.floor(v * 100 + 0.5) / 100
end

local function clamp_thresholds(ch)
    local vmax = conf.scale.val_max
    ch.warn = round2(math.max(0, math.min(ch.warn, vmax - STEP)))
    ch.alarm = round2(math.max(0, math.min(ch.alarm, vmax)))
    if ch.alarm <= ch.warn then
        ch.alarm = round2(math.min(vmax, ch.warn + STEP))
    end
    if ch.alarm <= ch.warn then
        ch.warn = round2(math.max(0, ch.alarm - STEP))
    end
end

local function update_card(ui, idx)
    local ch = conf.chs[idx]
    theme.set_text(ui.warn_val, string.format("%.1f %s", ch.warn, conf.scale.unit))
    theme.set_text(ui.alarm_val, string.format("%.1f %s", ch.alarm, conf.scale.unit))
    local lv = alarm.state[idx] or 0
    theme.set_text(ui.state, string.format("当前 %.1f %s   %s",
        data.val[idx] or 0, conf.scale.unit,
        (lv == 2) and "报警中" or ((lv == 1) and "预警中" or "正常")))
end

local function build_card(body, x, y, w, h, idx, refresh_all)
    local ch = conf.chs[idx]
    local card = theme.card(body, x, y, w, h, C.panel, 12, C.line, 1)
    theme.accent_bar(card, 12, 0, w - 24, ch.color)

    theme.label(card, 18, 16, 260, 28, ch.name, 20, C.ink)
    -- 三菱软元件编号是十进制，直接用 %s%d
    theme.label(card, w - 190, 20, 172, 22, string.format("寄存器 %s%d", ch.dev, ch.addr), 13, C.ink3,
        airui.TEXT_ALIGN_RIGHT)

    local ui = {}

    -- 预警值
    theme.label(card, 18, 74, 120, 26, "预警值", 17, C.ink2)
    theme.ghost_button(card, 148, 64, 56, 44, "-", 24, C.ink, function()
        theme.defer(function()
            ch.warn = round2(ch.warn - STEP)
            clamp_thresholds(ch)
            update_card(ui, idx)
            if refresh_all then refresh_all() end
        end)
    end)
    ui.warn_val = theme.label(card, 212, 66, 150, 40,
        string.format("%.1f %s", ch.warn, conf.scale.unit), 26, C.amber, airui.TEXT_ALIGN_CENTER)
    theme.ghost_button(card, 370, 64, 56, 44, "+", 24, C.ink, function()
        theme.defer(function()
            ch.warn = round2(ch.warn + STEP)
            clamp_thresholds(ch)
            update_card(ui, idx)
            if refresh_all then refresh_all() end
        end)
    end)

    -- 报警值
    theme.label(card, 18, 150, 120, 26, "报警值", 17, C.ink2)
    theme.ghost_button(card, 148, 140, 56, 44, "-", 24, C.ink, function()
        theme.defer(function()
            ch.alarm = round2(ch.alarm - STEP)
            clamp_thresholds(ch)
            update_card(ui, idx)
            if refresh_all then refresh_all() end
        end)
    end)
    ui.alarm_val = theme.label(card, 212, 142, 150, 40,
        string.format("%.1f %s", ch.alarm, conf.scale.unit), 26, C.danger, airui.TEXT_ALIGN_CENTER)
    theme.ghost_button(card, 370, 140, 56, 44, "+", 24, C.ink, function()
        theme.defer(function()
            ch.alarm = round2(ch.alarm + STEP)
            clamp_thresholds(ch)
            update_card(ui, idx)
            if refresh_all then refresh_all() end
        end)
    end)

    ui.state = theme.label(card, 18, 208, w - 36, 24, "当前 --", 15, C.ink3)
    theme.label(card, 18, 238, w - 36, 22,
        string.format("量程 %d~%d → %.1f~%.1f%s，回差 %.1f%s",
            conf.scale.raw_min, conf.scale.raw_max, conf.scale.val_min,
            conf.scale.val_max, conf.scale.unit, conf.alarm.hysteresis, conf.scale.unit),
        13, C.ink3)

    return ui
end

function M.build(body)
    local api = { cards = {} }

    local tip = theme.label(body, 20, 4, 984, 24,
        "阈值按工程量（℃）设置，步进 1.0；报警值必须大于预警值，修改后点“保存”写入掉电存储。",
        15, C.ink3)

    -- 两个卡片的数值互相约束，任意一张改动后同步刷新另一张
    local function refresh_all()
        for i = 1, #api.cards do
            update_card(api.cards[i], i)
        end
    end

    api.cards[1] = build_card(body, 20, 40, 484, 290, 1, refresh_all)
    api.cards[2] = build_card(body, 520, 40, 484, 290, 2, refresh_all)

    api.tip2 = theme.label(body, 20, 344, 500, 26, "", 15, C.ok)

    theme.button(body, 640, 340, 160, 48, "保存", 18, C.cyan, 0x05141C, function()
        theme.defer(function()
            store.save_channels(conf.chs)
            theme.set_text(api.tip2, "已保存到掉电存储")
            theme.set_color(api.tip2, C.ok)
            sys.timerStart(function()
                theme.set_text(api.tip2, "")
            end, 3000)
        end)
    end)

    theme.ghost_button(body, 812, 340, 192, 48, "恢复默认(70%/90%)", 16, C.ink2, function()
        theme.defer(function()
            local vmax = conf.scale.val_max
            for _, ch in ipairs(conf.chs) do
                ch.warn = round2(vmax * 0.7)
                ch.alarm = round2(vmax * 0.9)
                clamp_thresholds(ch)
            end
            refresh_all()
            store.save_channels(conf.chs)
            theme.set_text(api.tip2, "已恢复默认并保存")
            theme.set_color(api.tip2, C.amber)
            sys.timerStart(function()
                theme.set_text(api.tip2, "")
            end, 3000)
        end)
    end)

    return api
end

function M.refresh(api)
    if not api then
        return
    end
    for i = 1, #api.cards do
        update_card(api.cards[i], i)
    end
end

function M.on_show(api)
    for i = 1, #api.cards do
        update_card(api.cards[i], i)
    end
end

return M
