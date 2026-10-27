--[[
@module  ui_page_takeout
@summary 今天吃什么 - 页面三：外卖（50 选 1，原表无菜谱，只出菜名）
@version 1.0
@date    2026.10.26
@usage
与减脂餐同构：左转盘 + 右面板。面板少了一段菜谱，换成一张「小票」样式的心情卡，
写菜名 + 一句随机文案（app/foods.lua 里的 takeout_lines），保持版面不空。

右侧面板（页面内坐标）：
  y  30..62   类别胶囊「外卖」 + #编号
  y  72..124  菜名（36px，外卖菜名最长 5 个字）
  y 132..162  一句随机文案
  y 172..398  奶油小票卡（MEAL TICKET + 三行提示）
  y 418..490  底部提示条
]]

local T = require "ui_theme"
local D = require "ui_draw"
local F = require "foods"
local Wheel = require "ui_wheel"

local C = T.c
local M = {}

local wheel, lb_idx, lb_name, lb_line, lb_mood, ctx
local busy = false

function M.build(box, c)
    ctx = c
    local P = T.panel
    local x0 = P.x + P.pad
    local CW = P.w - P.pad * 2

    D.box(box, P.x, P.y, P.w, P.h, { color = C.card, radius = P.radius, border = C.line, border_w = 1 })

    local chip = D.box(box, x0, P.y + 20, 84, 32, { color = C.out_chip, radius = 16 })
    D.label_mid(chip, 0, 16, 84, "外卖", T.f.small, C.out_chip_t, D.ALIGN_CENTER)

    lb_idx = D.label_mid(box, x0 + CW - 146, P.y + 36, 146, "#--", T.f.mid, C.accent, D.ALIGN_RIGHT)

    lb_name = D.label(box, x0, P.y + 62, CW, 56, "点一下转盘吧", T.f.huge, C.ink)
    lb_line = D.label_mid(box, x0, P.y + 146, CW, "今天不用再想了", T.f.card, C.sub)

    -- 小票卡
    D.box(box, x0, P.y + 172, CW, 226, { color = C.cream, radius = 20 })
    D.label_mid(box, x0, P.y + 202, CW, "M E A L   T I C K E T", T.f.mini, C.faint, D.ALIGN_CENTER)
    lb_mood = D.label_mid(box, x0, P.y + 248, CW, "就它了，别犹豫", T.f.mid, C.accent, D.ALIGN_CENTER)
    D.box(box, x0 + 60, P.y + 276, CW - 120, 2, { color = C.line })
    D.label_mid(box, x0, P.y + 302, CW, "打开外卖软件，搜一下就好", T.f.small, C.sub, D.ALIGN_CENTER)
    D.label_mid(box, x0, P.y + 332, CW, "一个人也要好好吃饭", T.f.small, C.mute, D.ALIGN_CENTER)
    D.label_mid(box, x0, P.y + 370, CW, "剩下的交给骑手", T.f.mini, C.faint, D.ALIGN_CENTER)

    -- 底部提示条
    D.box(box, x0, P.y + 418, CW, 72, { color = C.tint, radius = 18 })
    D.label_mid(box, x0, P.y + 442, CW, "共 50 家店，转到哪个吃哪个", T.f.small, C.sub, D.ALIGN_CENTER)
    D.label_mid(box, x0, P.y + 466, CW, "ORDER SOMETHING", T.f.mini, C.faint, D.ALIGN_CENTER)

    wheel = Wheel.new({
        parent = box,
        rings = T.rings.out,
        button_text = "开饭",
        on_button = function() M.start() end,
    })
    M.wheel = wheel -- 供离屏预览 / 现场调试拿到句柄
end

function M.start()
    if busy or not wheel then return end
    busy = true
    if ctx and ctx.set_busy then ctx.set_busy(true) end
    sys.taskInit(function()
        local t0 = D.now_ms()
        local n = #F.takeout
        local idx = math.random(1, n)
        wheel:reset_hits()
        wheel:set_button("转动中", true)
        wheel:spin_to(1, idx, { duration = T.spin.single_ms, turns = T.spin.single_turns })

        local name = F.takeout[idx]
        wheel:mark_hit(1, idx)
        lb_idx:set_text(string.format("#%02d", idx))
        lb_name:set_text(name)
        lb_line:set_text("今天就吃这个")
        local lines = F.takeout_lines
        lb_mood:set_text(lines[math.random(1, #lines)])
        wheel:set_button("再转一次", false)

        busy = false
        if ctx and ctx.set_busy then ctx.set_busy(false) end
        log.info("page.takeout", "落点", idx, name, "耗时", D.now_ms() - t0, "ms")
    end)
end

return M
