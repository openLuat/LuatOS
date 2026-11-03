--[[
@module  ui_report
@summary 月度心情报告浮层：指数 + 五档分布 + 治愈系祝福语
@author  蒋骞
@version 1.0
@date    2026.10.30

=== 内容 ===
左：本月心情指数（1.0~5.0）、定性短评、记录天数、最好的一天
右：五档心情的分布条（airui.bar，长度按次数占已记录天数的比例）
下：一句祝福语 / 安慰语（三行短句，由 app/mood_stat.lua 生成）

=== 同 ui_picker ===
必须在 ui_calendar 之后创建，靠创建顺序压在最上层，平时隐藏。
bar 的 max 每次 show 时按「已记录天数」重设，长度才是相对比例。
]]
local conf = require "conf"
local theme = require "theme"
local mood_stat = require "mood_stat"

local M = {}

local C = theme.C
local SW, SH = conf.W, conf.H
local MOODS = conf.moods

local CARD_X, CARD_Y, CARD_W, CARD_H = 152, 70, 720, 460

local root = nil
local lb_month, lb_num, lb_word, lb_days, lb_best, lb_bless
local rows = {}                     -- [score] = { bar = , lb_cnt = }

-- ==================== 构建 ====================
function M.build(parent)
    root = airui.container({
        parent = parent, x = 0, y = 0, w = SW, h = SH,
        color = C.mask, color_opacity = 130, radius = 0, border_width = 0,
    })
    root:set_on_click(function()
        theme.defer(function() M.hide() end)
    end)

    local card = airui.container({
        parent = root, x = CARD_X, y = CARD_Y, w = CARD_W, h = CARD_H,
        color = C.card, radius = 24, border_color = C.line, border_width = 2,
    })
    card:set_on_click(function() end)     -- 拦住点击，防穿透

    theme.label(card, 30, 20, 420, 40, "本月心情报告", 28, C.ink)
    lb_month = theme.label(card, 30, 62, 300, 26, "", 17, C.ink2)

    theme.button(card, CARD_W - 120, 20, 100, 42, "关闭", 18, function()
        theme.defer(function() M.hide() end)
    end)

    theme.divider(card, 30, 96, CARD_W - 60, C.line)

    -- 左：指数
    lb_num = theme.label(card, 30, 108, 180, 84, "--", 60, C.ink3)
    theme.label(card, 198, 148, 60, 30, "/ 5", 20, C.ink3)
    lb_word = theme.label(card, 30, 194, 280, 32, "", 22, C.ink)
    lb_days = theme.label(card, 30, 234, 280, 26, "", 16, C.ink2)
    lb_best = theme.label(card, 30, 264, 280, 26, "", 16, C.ink2)

    -- 右：五档分布（色块 + 名称 + 比例条 + 次数）
    for i = 1, #MOODS do
        local mo = MOODS[i]
        local y = 112 + (i - 1) * 44
        theme.box(card, 330, y + 9, 14, 14, mo.color, 7, 255)
        theme.label(card, 352, y + 2, 60, 26, mo.name, 16, C.ink2)

        local bar = airui.bar({
            parent = card, x = 416, y = y + 8, w = 200, h = 16,
            min = 0, max = 1, value = 0,
            radius = 8,
            bg_color = C.panel,
            indicator_color = mo.color,
            border_width = 0,
        })
        local lb_cnt = theme.label(card, 622, y + 2, 38, 26, "0", 16, C.ink2,
            airui.TEXT_ALIGN_RIGHT)
        rows[mo.score] = { bar = bar, lb_cnt = lb_cnt }
    end

    theme.divider(card, 30, 330, CARD_W - 60, C.line)
    theme.label(card, 30, 344, 200, 26, "给你的话", 16, C.ink3)
    lb_bless = theme.label(card, 30, 372, CARD_W - 60, 76, "", 18, C.ink)

    M.hide()
    return root
end

-- ==================== 对外 ====================
--[[显示报告
@param number y,m 年月
@param table sum mood_stat.summary() 的结果
@param table bless mood_stat.compliment() 的结果（3 行短句）
]]
function M.show(y, m, sum, bless)
    if not root or not sum then return end

    lb_month:set_text(string.format("%04d年%02d月", y, m))

    if sum.avg then
        lb_num:set_text(string.format("%.1f", sum.avg))
        lb_num:set_color(C.accent)
    else
        lb_num:set_text("--")
        lb_num:set_color(C.ink3)
    end

    lb_word:set_text(mood_stat.word(sum.avg))
    lb_days:set_text(mood_stat.summary_line(sum))

    if sum.best then
        local bm = mood_stat.mood(sum.best.score)
        lb_best:set_text(string.format("最好的一天：%d日（%s）", sum.best.day, bm.name))
    else
        lb_best:set_text("最好的一天：还没有")
    end

    -- 分布条：max 用已记录天数，条长就是「这一档占了多少天」
    local maxv = math.max(sum.n, 1)
    for i = 1, #MOODS do
        local mo = MOODS[i]
        local c = sum.cnt[mo.score] or 0
        local row = rows[mo.score]
        if row then
            row.bar:set_range(0, maxv)
            row.bar:set_value(c, false)
            row.lb_cnt:set_text(tostring(c))
        end
    end

    lb_bless:set_text(mood_stat.join(bless))

    root:set_hidden(false)
    log.info("report", "打开月度报告", string.format("%04d-%02d", y, m),
        "记录", sum.n, "平均", sum.avg and string.format("%.1f", sum.avg) or "无")
end

function M.hide()
    if root then root:set_hidden(true) end
end

return M
