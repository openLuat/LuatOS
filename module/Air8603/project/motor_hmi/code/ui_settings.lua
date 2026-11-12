--[[
@module  ui_settings
@summary 设置页：启动间隔延时（触摸屏直接输入数字，掉电保存）
@version 1.0.0
@date    2026.11.12

这一页对应需求 3：不修改程序、不重新下载固件，直接在屏上输数字。
输入用 airui.keyboard(mode="numeric") + airui.textarea 绑定，
点输入框弹数字键盘，改完点「保存」写入 fskv。
]]
local M = {}

M.TITLE = "参数设置"

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C
local store = require "app_store"
local seq = require "app_seq"

local ROW_W = 984

local function clamp(v)
    if v < conf.seq.gap_min then v = conf.seq.gap_min end
    if v > conf.seq.gap_max then v = conf.seq.gap_max end
    return v
end

function M.build(body)
    local api = {}

    -- 说明卡
    local c1 = theme.card(body, 20, 8, ROW_W, 104, C.panel, 12, C.line, 1)
    theme.accent_bar(c1, 12, 0, ROW_W - 24, C.cyan)
    theme.label(c1, 22, 18, ROW_W - 44, 26, "启动间隔延时", 22, C.ink)
    theme.label(c1, 22, 52, ROW_W - 44, 22,
        "多台电机依次启动时，相邻两台之间的等待时间。第 1 台立即启动，第 2 台等 N 秒，第 3 台再等 N 秒。",
        14, C.ink3)
    theme.label(c1, 22, 76, ROW_W - 44, 22,
        "当前只接了 1 台电机，因此不会观察到延时效果，参数本身有效并被保存，接上第 2 台后自动生效。",
        14, C.amber)

    -- 输入卡
    local c2 = theme.card(body, 20, 124, ROW_W, 200, C.panel, 12, C.line, 1)

    -- 数字键盘：默认隐藏，点输入框自动弹出
    -- 内容区高度 = 600 - 56(顶栏) - 8 - 48(导航) = 488，键盘贴底占最后 240
    local keyboard = airui.keyboard({
        parent = body,
        x = 0,
        y = 248,
        w = conf.W,
        h = 240,
        mode = "numeric",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    theme.label(c2, 24, 30, 220, 30, "间隔时间", 20, C.ink)

    api.input = airui.textarea({
        parent = c2,
        text = tostring(conf.seq.gap_s),
        x = 250,
        y = 24,
        w = 160,
        h = 56,
        font_size = 30,
        color = C.cyan,
        bg_color = C.panel2,
        single_line = true,
        keyboard = keyboard,
        scroll = false,
        max_length = 3,
    })

    theme.label(c2, 424, 36, 60, 30, "秒", 22, C.ink2)

    theme.label(c2, 24, 96, ROW_W - 48, 22,
        string.format("有效范围 %d ~ %d 秒，整数。留空或超范围会自动纠正。",
            conf.seq.gap_min, conf.seq.gap_max), 14, C.ink3)

    api.cur = theme.label(c2, 24, 128, ROW_W - 48, 24, "", 15, C.ink3)

    -- 操作按钮
    theme.button(body, 20, 340, 200, 56, "保  存", 20, C.cyan, 0x05141C, function()
        theme.defer(function()
            local raw = api.input:get_text() or ""
            local v = tonumber(raw)
            if not v then
                theme.set_text(api.tip, "请输入数字")
                theme.set_color(api.tip, C.danger)
                return
            end
            v = math.floor(clamp(v) + 0.5)
            conf.seq.gap_s = v
            store.save_gap(v)
            pcall(api.input.set_text, api.input, tostring(v))
            theme.set_text(api.tip, string.format("已保存：%d 秒", v))
            theme.set_color(api.tip, C.ok)
            M.refresh(api)
            sys.timerStart(function()
                theme.set_text(api.tip, "")
            end, 3000)
        end)
    end, 12)

    theme.ghost_button(body, 240, 340, 200, 56, "恢复默认", 18, C.ink2, function()
        theme.defer(function()
            conf.seq.gap_s = 2
            store.save_gap(2)
            pcall(api.input.set_text, api.input, "2")
            theme.set_text(api.tip, "已恢复默认 2 秒")
            theme.set_color(api.tip, C.amber)
            M.refresh(api)
            sys.timerStart(function()
                theme.set_text(api.tip, "")
            end, 3000)
        end)
    end, C.line2)

    api.tip = theme.label(body, 460, 354, 540, 28, "", 16, C.ok)

    return api
end

function M.refresh(api)
    if not api or not api.cur then return end
    theme.set_text(api.cur, string.format("当前生效：%d 秒，序列状态：%s",
        conf.seq.gap_s, seq.busy and "启动中" or "空闲"))
end

function M.on_show(api)
    M.refresh(api)
end

return M
