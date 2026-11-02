--[[
@module  ui_picker
@summary 心情选择浮层：五档心情（超棒/不错/一般/不好/糟糕 = 5~1 分）
@author  蒋骞
@version 1.0
@date    2026.10.30

=== 为什么是一个常驻的隐藏浮层 ===
airui 没有暴露「把控件提到最前」的接口（只有 set_hidden），
所以浮层必须在 ui_calendar 之后创建，靠创建顺序保证它在最上层，
平时隐藏，需要时 set_hidden(false)。

=== 遮罩必须吃掉点击 ===
遮罩容器和卡片都绑了 on_click：
  遮罩 -> 关闭浮层
  卡片 -> 空函数（只为了拦住事件，防止点卡片空白处被当成点遮罩）
否则点击会穿透到下面的日历格子，误改心情。
]]
local conf = require "conf"
local theme = require "theme"
local mood_stat = require "mood_stat"

local M = {}

local C = theme.C
local SW, SH = conf.W, conf.H
local MOODS = conf.moods

-- 卡片尺寸与位置（屏幕正中偏上，下面留出视觉呼吸）
local CARD_X, CARD_Y, CARD_W, CARD_H = 202, 150, 620, 250

local root = nil
local lb_title, lb_hint
local btns = {}                     -- [score] = button

local sel_y, sel_m, sel_d           -- 正在编辑的日期

M.on_select = nil                   -- function(y, m, d, score)

-- ==================== 内部 ====================
local function paint_selection(score)
    for i = 1, #MOODS do
        local m = MOODS[i]
        local b = btns[m.score]
        if b then
            if score == m.score then
                b:set_style({ border_width = 4, border_color = theme.shade(m.color, 0.48) })
            else
                b:set_style({ border_width = 2, border_color = theme.tint(m.color, 0.35) })
            end
        end
    end
end

local function pick(score)
    local y, m, d = sel_y, sel_m, sel_d
    M.hide()
    if M.on_select then M.on_select(y, m, d, score) end
end

-- ==================== 构建 ====================
function M.build(parent)
    root = airui.container({
        parent = parent, x = 0, y = 0, w = SW, h = SH,
        color = C.mask, color_opacity = 120, radius = 0, border_width = 0,
    })
    root:set_on_click(function()
        theme.defer(function() M.hide() end)
    end)

    local card = airui.container({
        parent = root, x = CARD_X, y = CARD_Y, w = CARD_W, h = CARD_H,
        color = C.card, radius = 22, border_color = C.line, border_width = 2,
    })
    card:set_on_click(function() end)     -- 只为拦住点击，不做任何事

    lb_title = theme.label(card, 20, 18, CARD_W - 40, 36, "", 24, C.ink,
        airui.TEXT_ALIGN_CENTER)
    lb_hint = theme.label(card, 20, 56, CARD_W - 40, 26, "选一个此刻的心情吧",
        16, C.ink3, airui.TEXT_ALIGN_CENTER)

    local bw, bh, gap = 104, 76, 8
    local total = #MOODS * bw + (#MOODS - 1) * gap
    local x0 = math.floor((CARD_W - total) / 2)
    for i = 1, #MOODS do
        local mo = MOODS[i]
        local x = x0 + (i - 1) * (bw + gap)
        btns[mo.score] = theme.mood_button(card, x, 92, bw, bh, mo, function()
            theme.defer(function() pick(mo.score) end)
        end)
    end

    theme.button(card, math.floor((CARD_W - 160) / 2), 186, 160, 44, "取消", 20,
        function()
            theme.defer(function() M.hide() end)
        end)

    M.hide()
    return root
end

-- ==================== 对外 ====================
--[[打开浮层
@param number y,m,d 日期
@param number|nil score 当前已有分数（用于高亮），没有传 nil
]]
function M.show(y, m, d, score)
    if not root then return end
    sel_y, sel_m, sel_d = y, m, d
    lb_title:set_text(string.format("%d月%d日  的心情", m, d))
    if score then
        local mo = mood_stat.mood(score)
        lb_hint:set_text(string.format("已经记过了，现在是%s，换了也没关系", mo.name))
    else
        lb_hint:set_text("选一个此刻的心情吧")
    end
    paint_selection(score)
    root:set_hidden(false)
    log.info("picker", "打开心情选择", string.format("%04d-%02d-%02d", y, m, d),
        "当前", score or "无")
end

function M.hide()
    if root then root:set_hidden(true) end
end

return M
