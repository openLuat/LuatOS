--[[
@module  page_room
@summary 页1 我的房间：光晕+大角色+四弧角色 / 温湿度 / 空调 ± / 四场景 / 四设备磁贴
@version 2.0.0
@note 坐标全部按内容区（1024x432）核算，与 docs/儿童房面板效果稿.html 页1 对齐；
      卡片高度比槽位少 4px 留给假投影层，底部不会探出触发滚动条。
      角色切换只换 image 的 src，不重建控件（image:set_src）。
]]
local T = require "ui_theme"
local C = T.c
local W = require "ui_widget"
local S = require "app_state"
local CAST = require "ui_cast"

local M = {}
local ui = { tiles = {}, arcs = {}, ac_val = nil, ac_bar = nil, temp = nil, hum = nil,
    big = nil, room = nil }

local TILES = {
    { key = "lamp",    icon = "ic_lamp",      name = "小夜灯",   deco1 = 2, twinkle = true, deco2 = 4, deco2_w = 30 },
    { key = "proj",    icon = "ic_projector", name = "星空投影", deco1 = 5, twinkle = true, deco2 = 1, deco2_w = 32 },
    { key = "curtain", icon = "ic_curtain",   name = "窗帘",     deco1 = 3, twinkle = true, deco2 = 5, deco2_w = 30 },
    { key = "humid",   icon = "ic_humid",     name = "加湿器",   deco1 = 4, twinkle = true, deco2 = nil },
}

local function status_text(key)
    local d = S.dev[key]
    if key == "lamp" then
        return d.on and ("亮度 " .. d.bri .. "%") or "已关闭"
    elseif key == "proj" then
        return S.proj_text()
    elseif key == "curtain" then
        return d.on and "已打开" or "已合上"
    elseif key == "humid" then
        return d.on and ("湿度 " .. S.env.hum .. "%") or "已关闭"
    end
    return ""
end

local function refresh()
    for _, t in ipairs(ui.tiles) do
        local d = S.dev[t.key]
        W.glass(t.inner, d.on and C.on or C.card, 255)
        pcall(function() t.status:set_text(status_text(t.key)) end)
        pcall(function() t.status:set_color(d.on and C.pri or C.ink3) end)
        if t.sw then t.sw.set(d.on) end
    end
    if ui.ac_val then pcall(function() ui.ac_val:set_text(S.dev.ac.temp .. "°") end) end
    if ui.ac_bar then W.glass(ui.ac_bar, S.dev.ac.on and C.on or C.card2, 255) end
    if ui.temp then pcall(function() ui.temp:set_text(S.env.temp_in .. "°") end) end
    if ui.hum then pcall(function() ui.hum:set_text(S.env.hum .. "%") end) end
    if ui.room then pcall(function() ui.room:set_text(CAST.room_name()) end) end

    -- 角色：大图 + 四个弧位（只换 src）
    W.set_image(ui.big, CAST.img(true))
    for k, obj in ipairs(ui.arcs) do
        W.set_image(obj, string.format("ch_%s_%d_sm", T.key, CAST.slot(k) - 1))
    end
end

function M.create(root, ctx)
    -- ===== 左：大卡 =====
    local card = W.card(root, { x = 16, y = 0, w = 480, h = 428 })
    local inner = card.inner

    -- 光晕：真机没有 blur，用「大圆低透明 + 小圆高透明」两层近似 .glow 的 18px 羽化
    W.halo(inner, { x = 140, y = 16, d = 200, color = C.band1, opa = 45 })
    W.halo(inner, { x = 151, y = 27, d = 178, color = C.band1, opa = 150 })
    ui.big = W.sticker(inner, { name = CAST.img(true), x = 166, y = 42, w = 148, h = 148 })
    W.press(inner, { x = 166, y = 42, w = 148, h = 148, radius = 74,
        on_click = function() if ctx then ctx.on_cast_change(1) end end })

    -- 弧形四个角色（52x52 白圆 + 46x46 小人），点谁选谁
    -- 外面垫一张 54x54 的 track 色圆模拟 .cbtn 的 1.5px 描边（容器不能画环）
    local arc_pos = { { 70, 38 }, { 132, 12 }, { 298, 12 }, { 360, 38 } }
    for k = 1, 4 do
        local px, py = arc_pos[k][1], arc_pos[k][2]
        W.glass(W.box(inner, px - 1, py - 1, 54, 54, C.track, 27), C.track, 255)
        local box = W.box(inner, px, py, 52, 52, C.card, 26)
        W.glass(box, C.card, 255)
        local img = W.sticker(box, { name = string.format("ch_%s_%d_sm", T.key, CAST.slot(k) - 1),
            x = 3, y = 5, w = 46, h = 46 })
        ui.arcs[k] = img
        W.press(inner, { x = px, y = py, w = 52, h = 52, radius = 26,
            flash = C.pri, flash_opa = 30,
            on_click = function()
                if ctx then ctx.on_cast_change(nil, CAST.slot(k)) end
            end })
    end

    W.deco(inner, { name = CAST.sticker(3), x = 24, y = 20, w = 26, h = 26 })
    W.deco(inner, { name = CAST.sticker(4), x = 434, y = 22, w = 24, h = 24 })

    ui.room = W.text_mid(inner, { text = CAST.room_name(), x = 0, y = 192, w = 480, h = 26,
        size = T.f.body, color = C.ink, align = airui.TEXT_ALIGN_CENTER })

    ui.temp = W.text_mid(inner, { text = "", x = 24, y = 220, w = 204, h = 46,
        size = T.f.h1, color = C.ink, align = airui.TEXT_ALIGN_CENTER })
    W.text_mid(inner, { text = "室内温度", x = 24, y = 268, w = 204, h = 22,
        size = T.f.sub, color = C.ink2, align = airui.TEXT_ALIGN_CENTER })
    ui.hum = W.text_mid(inner, { text = "", x = 252, y = 220, w = 204, h = 46,
        size = T.f.h1, color = C.ink, align = airui.TEXT_ALIGN_CENTER })
    W.text_mid(inner, { text = "空气湿度", x = 252, y = 268, w = 204, h = 22,
        size = T.f.sub, color = C.ink2, align = airui.TEXT_ALIGN_CENTER })

    -- 空调一行：标签 + - 26° +（减号必须用 ASCII "-"：hzfont 没有 U+2212，会显示成方框）
    ui.ac_bar = W.box(inner, 24, 294, 432, 56, C.on, 20)
    W.glass(ui.ac_bar, C.on, 255)
    W.text_mid(ui.ac_bar, { text = "空调", x = 14, y = 0, w = 60, h = 56,
        size = T.f.sub, color = C.ink2 })
    W.button(ui.ac_bar, { x = 196, y = 6, w = 44, h = 44, radius = 14, text = "-",
        size = 26, bg = C.card, fg = C.pri,
        on_click = function() S.ac_delta(-1); refresh() end })
    ui.ac_val = W.text_mid(ui.ac_bar, { text = "", x = 248, y = 0, w = 88, h = 56,
        size = T.f.h2, color = C.ink, align = airui.TEXT_ALIGN_CENTER })
    W.button(ui.ac_bar, { x = 344, y = 6, w = 44, h = 44, radius = 14, text = "+",
        size = 26, bg = C.card, fg = C.pri,
        on_click = function() S.ac_delta(1); refresh() end })

    -- 四个场景按钮（一键联动多张设备卡）
    for i, sc in ipairs(S.scenes) do
        local x = 24 + (i - 1) * 110
        local box = W.box(inner, x, 356, 102, 58, C.on, 18)
        W.glass(box, C.on, 255)
        W.sticker(box, { name = sc.icon, x = 39, y = 5, w = 24, h = 24 })
        W.text_mid(box, { text = sc.name, x = 0, y = 30, w = 102, h = 24,
            size = T.f.sub, color = C.ink, align = airui.TEXT_ALIGN_CENTER })
        W.press(inner, { x = x, y = 356, w = 102, h = 58, radius = 18,
            flash = C.pri, flash_opa = 40,
            on_click = function()
                S.scene(sc.name)
                refresh()
            end })
    end

    -- ===== 右：2x2 设备磁贴 =====
    -- 左卡到 496 结束，磁贴从 508 起：留 12px 缝，别和左卡粘成一块
    -- （原稿 492 会与左卡重叠 4px，真机上两列看起来是连体的）
    local pos = { { 508, 0 }, { 756, 0 }, { 508, 222 }, { 756, 222 } }
    for i, def in ipairs(TILES) do
        local x, y = pos[i][1], pos[i][2]
        local tile = W.card(root, { x = x, y = y, w = 236, h = 206 })
        local ti = tile.inner
        W.halo(ti, { x = 9, y = 7, d = 70, color = C.card2, opa = 255 })
        W.sticker(ti, { name = def.icon, x = 16, y = 14, w = 56, h = 56 })
        W.deco(ti, { name = CAST.sticker(def.deco1), x = 102, y = 20, w = 30, h = 30,
            twinkle = def.twinkle })
        if def.deco2 then
            W.deco(ti, { name = CAST.sticker(def.deco2), x = 178, y = 20,
                w = def.deco2_w or 30, h = def.deco2_w or 30 })
        else
            -- 加湿器磁贴右上角站一个小角色（效果稿用 .ch.sm）
            local sm = W.box(ti, 180, 16, 36, 36, C.card, 18)
            W.glass(sm, C.card, 0)
            W.sticker(sm, { name = string.format("ch_%s_%d_sm", T.key, CAST.idx() - 1),
                x = 0, y = 0, w = 36, h = 36 })
        end
        W.text_mid(ti, { text = def.name, x = 16, y = 80, w = 200, h = 26,
            size = T.f.body, color = C.ink })
        local status = W.text_mid(ti, { text = "", x = 16, y = 108, w = 200, h = 22,
            size = T.f.sub, color = C.ink2 })
        local sw = W.switch(ti, { x = 160, y = 156, w = 60, h = 34, on = S.dev[def.key].on,
            tappable = false })
        -- 整张卡就是热区（孩子一指就点中），热区在内容之上，switch 只是视觉
        W.press(ti, { x = 0, y = 0, w = 236, h = 206, radius = T.r.tile, tag = "tile_" .. def.key,
            target = tile.root, tx = x, ty = y, flash = C.pri, flash_opa = 34,
            on_click = function()
                S.toggle(def.key)
                refresh()
            end })
        ui.tiles[i] = { key = def.key, inner = ti, status = status, sw = sw }
    end

    refresh()
    return { refresh = refresh }
end

return M
