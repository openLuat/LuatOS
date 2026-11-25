--[[
@module  page_star
@summary 页4 星星奖励：今日任务打勾 / 星星数与主题奖励贴纸 / 本周 7 柱 / 睡觉起床闹钟
@version 2.0.0
@note 坐标按 docs/儿童房面板效果稿.html 页4 逐项对齐：左卡 16/480，右卡 496/496。
      柱状图用 7 个圆角容器拼（不用 airui.chart：X 轴线关不干净、只吃整数）；
      container 不能改尺寸，柱高在创建时按数据一次算好，刷新只改颜色与文字。
      奖励贴纸取当前主题套图的对应格（ui_cast.reward_sticker），切主题整页重建后自动换。
]]
local T = require "ui_theme"
local C = T.c
local W = require "ui_widget"
local S = require "app_state"
local CAST = require "ui_cast"

local M = {}
local ui = { tasks = {}, star_lbl = nil, need = nil, bars = {}, days = {},
    alarm_txt = {} }

local WEEK_BASE = 250          -- 柱底（效果稿周标签 top:256）
local WEEK_W = 40
local WEEK_GAP = 58

local function refresh()
    -- 任务：勾选态只改 checkbox 底色、标题色与副文案
    for i, t in ipairs(ui.tasks) do
        local d = S.tasks[i]
        W.glass(t.box, d.done and C.pri or C.card, 255)
        pcall(function() t.name:set_color(d.done and C.ink3 or C.ink) end)
        pcall(function() t.sub:set_text(d.sub) end)
    end

    -- 星星数 = 10 + 已完成数（与效果稿 renderPage4 一致）
    local n = S.stars()
    if ui.star_lbl then pcall(function() ui.star_lbl:set_text(tostring(n)) end) end
    if ui.need then pcall(function() ui.need:set_text("再攒 " .. math.max(0, 20 - n) .. " 颗") end) end

    if ui.alarm_txt.sleep then
        pcall(function() ui.alarm_txt.sleep:set_text(S.alarm_text("sleep")) end)
    end
    if ui.alarm_txt.wake then
        pcall(function() ui.alarm_txt.wake:set_text(S.alarm_text("wake")) end)
    end
end

function M.create(root)
    -- ===== 左：今天的任务 =====
    local c1 = W.card(root, { x = 16, y = 0, w = 480, h = 428 })
    W.text_mid(c1.inner, { text = "今天的任务", x = 24, y = 16, w = 240, h = 28,
        size = T.f.h3, color = C.ink })
    W.deco(c1.inner, { name = CAST.sticker(3), x = 424, y = 12, w = 32, h = 32 })

    for i, t in ipairs(S.tasks) do
        local y = 58 + (i - 1) * 84
        local row = W.box(c1.inner, 16, y, 448, 76, C.card2, 20)
        W.glass(row, C.card2, 255)
        local box = W.box(row, 14, 14, 48, 48, C.card, 16)
        W.glass(box, C.card, 255)
        -- ✓ 恒为白色：未完成时底也是白色，自然不可见（等价 .checkbox span opacity:0）
        W.icon(row, { symbol = airui.SYMBOL_OK, x = 14, y = 14, w = 48, h = 48,
            size = 26, color = C.white })
        local name = W.text_mid(row, { text = t.name, x = 76, y = 10, w = 350, h = 28,
            size = T.f.body, color = C.ink })
        local sub = W.text_mid(row, { text = t.sub, x = 76, y = 40, w = 350, h = 22,
            size = T.f.sub, color = C.ink2 })
        W.press(c1.inner, { x = 16, y = y, w = 448, h = 76, radius = 20,
            target = row, tx = 16, ty = y, flash = C.pri, flash_opa = 30,
            on_click = function()
                S.task_toggle(i)
                refresh()
            end })
        ui.tasks[i] = { box = box, name = name, sub = sub }
    end
    W.deco(c1.inner, { name = CAST.sticker(5), x = 398, y = 390, w = 30, h = 30 })

    -- ===== 右：奖励 / 本周 / 闹钟 =====
    -- 左卡到 496 结束，右卡 508..992（原 496 起是紧贴，肉眼像一张卡）
    local c2 = W.card(root, { x = 508, y = 0, w = 484, h = 428 })
    W.text_mid(c2.inner, { text = "我的奖励", x = 24, y = 12, w = 240, h = 28,
        size = T.f.h3, color = C.ink })
    ui.star_lbl = W.text_mid(c2.inner, { text = "", x = 24, y = 40, w = 86, h = 54,
        size = T.f.h1, color = C.pri })
    W.text_mid(c2.inner, { text = "颗星星", x = 110, y = 58, w = 80, h = 24,
        size = T.f.sub, color = C.ink2 })

    -- 三枚奖励贴纸：大中小，随主题换格（.kr 在效果稿里按主题切背景位置）
    local kr = CAST.reward_sticker()
    W.deco(c2.inner, { name = kr, x = 198, y = 44, w = 46, h = 46 })
    W.deco(c2.inner, { name = kr, x = 250, y = 52, w = 36, h = 36 })
    W.deco(c2.inner, { name = kr, x = 292, y = 58, w = 28, h = 28 })

    ui.need = W.text_mid(c2.inner, { text = "", x = 356, y = 40, w = 116, h = 22,
        size = T.f.sub, color = C.ink2, align = airui.TEXT_ALIGN_RIGHT })
    W.text_mid(c2.inner, { text = "换小贴纸", x = 356, y = 66, w = 116, h = 22,
        size = T.f.sub, color = C.ink2, align = airui.TEXT_ALIGN_RIGHT })

    -- 本周 7 柱：柱底 250，柱高 20 + 值*16（最大 6 → 116）
    local today = S.week_today()
    for i = 1, 7 do
        local v = S.week[i] or 0
        local bh = 20 + v * 16
        local x = 44 + (i - 1) * WEEK_GAP
        local on = (i == today)
        local b = W.box(c2.inner, x, WEEK_BASE - bh, WEEK_W, bh, on and C.pri or C.pri2, 10)
        W.glass(b, on and C.pri or C.pri2, 255)
        local lbl = W.text_mid(c2.inner, { text = S.week_day_names[i], x = x, y = 256,
            w = WEEK_W, h = 20, size = T.f.sub,
            color = on and C.pri or C.ink2, align = airui.TEXT_ALIGN_CENTER })
        ui.bars[i] = b
        ui.days[i] = lbl
    end

    -- 睡觉 / 起床闹钟（±15 分钟回绕，跨天不乱）
    local function alarm_row(y, kind, label, icon)
        local row = W.box(c2.inner, 24, y, 448, 44, C.card2, 16)
        W.glass(row, C.card2, 255)
        W.sticker(row, { name = icon, x = 12, y = 8, w = 28, h = 28 })
        W.text_mid(row, { text = label, x = 46, y = 0, w = 60, h = 44,
            size = T.f.sub, color = C.ink2 })
        W.button(row, { x = 290, y = 4, w = 36, h = 36, radius = 12, text = "-",
            size = 22, bg = C.card, fg = C.pri,
            on_click = function() S.alarm_delta(kind, -1); refresh() end })
        local txt = W.text_mid(row, { text = "", x = 336, y = 0, w = 72, h = 44,
            size = T.f.h3, color = C.ink, align = airui.TEXT_ALIGN_CENTER })
        W.button(row, { x = 412, y = 4, w = 36, h = 36, radius = 12, text = "+",
            size = 22, bg = C.card, fg = C.pri,
            on_click = function() S.alarm_delta(kind, 1); refresh() end })
        ui.alarm_txt[kind] = txt
    end
    alarm_row(290, "sleep", "睡觉", "ic_moon")
    alarm_row(346, "wake", "起床", "ic_sun")

    refresh()
    return { refresh = refresh }
end

return M
