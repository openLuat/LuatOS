--[[
@module  page_light
@summary 页2 灯光乐园：8 色色点 / 夜灯预览（圆里坐角色）/ 亮度 / 模式 chip / 投影与定时
@version 2.0.0
@note 预览圆底色 = mix(白, 选中色, 亮度/100)，与效果稿 mix(col,'#FFFFFF',bright/100) 等价；
      亮度条填充色跟选中色走（bar:set_indicator_color）。
]]
local T = require "ui_theme"
local C = T.c
local W = require "ui_widget"
local S = require "app_state"
local CAST = require "ui_cast"

local M = {}
local ui = {
    dots = {}, mode_chips = {}, timer_chips = {},
    prev = nil, prev_char = nil, bri_lbl = nil, bar = nil, proj_sw = nil,
}

local function cur_color()
    local def = T.colors[S.dev.lamp.color] or T.colors[1]
    return def.c
end

local function refresh()
    -- 色点选中环（效果稿是 64px 的 3px 主色描边，这里用同尺寸实心圆垫在下面近似）
    for i, d in ipairs(ui.dots) do
        W.glass(d.ring, C.pri, (i == S.dev.lamp.color) and 255 or 0)
    end

    -- 预览圆：颜色与亮度混色（亮度越低越接近白）
    local c = cur_color()
    local k = S.dev.lamp.bri / 100
    local shown = W.mix(C.white, c, k)
    if ui.prev then W.glass(ui.prev, shown, 255) end
    if ui.bri_lbl then
        pcall(function() ui.bri_lbl:set_text("亮度 " .. S.dev.lamp.bri .. "%") end)
    end
    if ui.bar then
        ui.bar.set(S.dev.lamp.bri)
        ui.bar.set_color(c)
    end

    -- 模式 / 投影 / 定时
    for _, mc in ipairs(ui.mode_chips) do mc.set_active(mc.idx == S.mode) end
    if ui.proj_sw then ui.proj_sw.set(S.dev.proj.on) end
    for _, tc in ipairs(ui.timer_chips) do tc.set_active(tc.min == S.proj_timer) end

    -- 圆里的角色跟着换
    W.set_image(ui.prev_char, CAST.img(true))
end

function M.create(root, ctx)
    -- ===== 左：颜色乐园 =====
    local c1 = W.card(root, { x = 16, y = 0, w = 300, h = 428 })
    W.text_mid(c1.inner, { text = "颜色乐园", x = 24, y = 18, w = 200, h = 28,
        size = T.f.h3, color = C.ink })
    W.deco(c1.inner, { name = CAST.sticker(2), x = 238, y = 16, w = 28, h = 28, twinkle = true })

    -- 两列居中：56 点 + 40 列距，左右各留 74，卡片不会被挤到左边
    for i = 1, 8 do
        local col = T.colors[i]
        local cx = (i % 2 == 1) and 74 or 170
        local cy = 70 + math.floor((i - 1) / 2) * 86
        local ring = W.box(c1.inner, cx - 4, cy - 4, 64, 64, C.pri, 32)
        W.glass(ring, C.pri, 0)
        local dot = W.box(c1.inner, cx, cy, 56, 56, col.c, 28)
        W.glass(dot, col.c, 255)
        W.press(c1.inner, { x = cx - 4, y = cy - 4, w = 64, h = 64, radius = 32,
            target = dot, tx = cx, ty = cy, flash = C.pri, flash_opa = 40,
            on_click = function()
                S.dev.lamp.color = i
                refresh()
            end })
        ui.dots[i] = { ring = ring, dot = dot }
    end

    -- ===== 中：小夜灯 =====
    local c2 = W.card(root, { x = 328, y = 0, w = 340, h = 428 })
    W.text_mid(c2.inner, { text = "小夜灯", x = 24, y = 18, w = 200, h = 28,
        size = T.f.h3, color = C.ink })
    W.deco(c2.inner, { name = CAST.sticker(4), x = 288, y = 18, w = 28, h = 28, twinkle = true })
    W.deco(c2.inner, { name = CAST.sticker(1), x = 246, y = 186, w = 44, h = 44 })

    ui.prev = W.box(c2.inner, 70, 32, 200, 200, C.pri, 100)
    W.glass(ui.prev, C.pri, 255)
    ui.prev_char = W.sticker(ui.prev, { name = CAST.img(true), x = 25, y = 20, w = 150, h = 150 })

    ui.bri_lbl = W.text_mid(c2.inner, { text = "", x = 26, y = 246, w = 200, h = 26,
        size = T.f.body, color = C.ink })
    ui.bar = W.bar(c2.inner, { x = 26, y = 280, w = 288, h = 18, value = 60, tag = "bri" })
    W.button(c2.inner, { x = 26, y = 316, w = 76, h = 56, radius = 18, text = "-",
        size = 26, bg = C.on, fg = C.pri,
        on_click = function() S.bri_delta(-1); refresh() end })
    W.button(c2.inner, { x = 238, y = 316, w = 76, h = 56, radius = 18, text = "+",
        size = 26, bg = C.on, fg = C.pri,
        on_click = function() S.bri_delta(1); refresh() end })
    W.text_mid(c2.inner, { text = "点色点换颜色，± 调亮度", x = 26, y = 386, w = 288, h = 22,
        size = T.f.sub, color = C.ink3 })

    -- ===== 右：模式与投影 =====
    -- 右卡收窄到 992 收边（与顶栏/底部 Tab 同一条右边线；原 328 会探出 16px）
    local c3 = W.card(root, { x = 680, y = 0, w = 312, h = 428 })
    W.text_mid(c3.inner, { text = "模式", x = 16, y = 18, w = 200, h = 28,
        size = T.f.h3, color = C.ink })
    W.deco(c3.inner, { name = CAST.sticker(5), x = 266, y = 16, w = 30, h = 30, twinkle = true })

    -- 三枚 chip 等分居中：16 + 96*i，右侧收在 296（左右各 16）
    for i, name in ipairs(S.modes) do
        local chip = W.chip(c3.inner, { x = 16 + (i - 1) * 96, y = 62, w = 88, h = 40,
            text = name, on_click = function()
                S.mode = i
                refresh()
            end })
        chip.idx = i
        ui.mode_chips[i] = chip
    end

    W.text_mid(c3.inner, { text = "星空投影", x = 16, y = 126, w = 150, h = 28,
        size = T.f.body, color = C.ink })
    ui.proj_sw = W.switch(c3.inner, { x = 236, y = 124, w = 60, h = 34, on = S.dev.proj.on,
        on_click = function() S.toggle("proj"); refresh() end })
    ui.proj_sw.set(S.dev.proj.on)

    W.text_mid(c3.inner, { text = "投影定时", x = 16, y = 186, w = 150, h = 22,
        size = T.f.sub, color = C.ink2 })
    for i, m in ipairs(S.PROJ_TIMERS) do
        local chip = W.chip(c3.inner, { x = 16 + (i - 1) * 96, y = 212, w = 88, h = 40,
            text = m .. " 分", on_click = function()
                S.proj_timer = m
                refresh()
            end })
        chip.min = m
        ui.timer_chips[i] = chip
    end

    W.deco(c3.inner, { name = CAST.sticker(3), x = 108, y = 282, w = 96, h = 96 })

    refresh()
    return { refresh = refresh }
end

return M
