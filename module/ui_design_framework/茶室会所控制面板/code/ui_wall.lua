--[[
场景墙：1 张大卡（茶台灯光）+ 4 张小卡
点任意卡片 → 进详情

本页建在 stage 内（stage = 88,58 起 936×412），坐标相对 stage 内容区：
  大卡  16..436 × 18..394  (420×376)
  小卡  452..668 / 684..900 × 18..198 与 214..394 (216×180)

两套长相（按主题分支，切主题走全量重建）：
  暖夜：暗调照片满铺 + 底部压暗 + 浅色字（照片是暗的，字必须浅）
  宣纸：晨光浅调照片满铺 + 底部暖白薄纱 + 深墨字（图是亮的，字必须深）
        两套素材互不染色：dev_*.jpg / p_*.jpg，见 make_assets.py
        （JPG 不是随便选的：硬件 PNG 解码不吃多 IDAT 块，PIL 存的图必然分块）
        纸面卡多 1px 描边：外层 card_line 实心块 + 内层内缩 1px 卡面，
        不用 border_width，避免子控件再按 w-2 重算（G1/G2）
]]

local T = require "ui_theme"
local W = require "ui_widget"
local K = require "ui_kit"
local CFG = require "app_config"
local S = require "app_state"

local M = {}

-- 大卡
local BX, BY, BW, BH = 16, 18, 420, 376
-- 小卡
local SX1, SX2, SY1, SY2, SW, SH = 452, 684, 18, 214, 216, 180

-- 大卡档位段：10 段 37 宽，段间距 2 → 388
local SEG_W, SEG_H, SEG_GAP = 37, 5, 2

local function level_text(i)
    local v = S.levels[i] or 0
    if v <= 0 then return "已关" end
    return v .. " " .. CFG.txt.seg_level
end

-- 卡上胶囊：夜间压在照片上（深底浅字），纸面在浅卡上（浅底深字）
local function cap_style(paper)
    if paper then
        return { bg = T.c.chip, opa = 255, txt = T.c.dim }
    end
    return { bg = 0x080604, opa = 150, txt = T.c.gold }
end

local function build_big(page, cb, H)
    local dev = CFG.DEVICES[1]
    local paper = T.is_paper()
    local cap = cap_style(paper)

    -- 外层：纸面时这层就是 1px 边线（实心块，无描边参数）
    local card = W.box(page, {
        x = BX, y = BY, w = BW, h = BH, radius = 12,
        color = paper and T.c.card_line or T.c.btn, border_width = 0,
        on_click = function() cb.on_card(1) end, tag = "bigcard",
    })

    -- 内容挂载点：纸面内缩 1px 的卡面，范围 418×374
    local host
    if paper then
        host = W.box(card, {
            x = 1, y = 1, w = BW - 2, h = BH - 2, radius = 11,
            color = T.c.card_in, border_width = 0, tag = "bigcard-in",
        })
        -- 图只留上半（0..262），下半是实心纸签：文字永远落在干净纸面上，
        -- 不会被器物木纹抢读（薄纱护不住 27 号字压在图上的那种杂乱）
        W.image(host, { x = 0, y = 0, w = BW - 2, h = BH - 2, src = dev.img_p,
                        fit = "stretch", tag = "big-img" })
        W.box(host, { x = 0, y = 262, w = BW - 2, h = 112, color = T.c.card_in,
                      border_width = 0, tag = "big-slip" })
        W.shape(host, {
            x = 0, y = 262, w = BW - 2, h = 1,
            items = { { type = "line", x1 = 0, y1 = 0, x2 = BW - 2, y2 = 0,
                        color = T.c.card_line, width = 1, opacity = 200 } },
            tag = "big-slip-line",
        })
        W.text(host, {
            x = 19, y = 272, w = 380, h = 30, text = dev.name, size = CFG.FONT.hero,
            color = T.c.text, align = airui.TEXT_ALIGN_CENTER, tag = "big-name",
        })
        W.text(host, {
            x = 19, y = 306, w = 380, h = 19, text = dev.en, size = CFG.FONT.mini,
            color = T.c.gold_dim, align = airui.TEXT_ALIGN_CENTER, tag = "big-en",
        })
    else
        host = card
        W.image(host, { x = 0, y = 0, w = BW, h = BH, src = dev.img, fit = "stretch", tag = "big-img" })
        -- 底部渐隐：两层半透明压暗（CSS 渐变在真机上用阶梯近似，静态层只建一次）
        W.box(host, { x = 0, y = 160, w = BW, h = 140, color = 0x080604, color_opacity = 70,
                      border_width = 0, tag = "big-sh1" })
        W.box(host, { x = 0, y = 256, w = BW, h = 120, color = 0x080604, color_opacity = 130,
                      border_width = 0, tag = "big-sh2" })
        W.text(host, {
            x = 24, y = 286, w = 260, h = 30, text = dev.name, size = CFG.FONT.hero,
            color = T.c.text, tag = "big-name",
        })
        W.text(host, {
            x = 24, y = 320, w = 260, h = 19, text = dev.en, size = CFG.FONT.mini,
            color = T.c.gold_dim, tag = "big-en",
        })
    end

    -- 左上"主位"（坐标按宿主内容区算：纸面宿主是 418 宽的内层）
    local ox = paper and 27 or 24
    K.pill(host, {
        x = ox, y = 16, w = 66, h = 24, bg = cap.bg, bg_opa = cap.opa,
        text = "主位", color = cap.txt, size = CFG.FONT.mini,
        align = airui.TEXT_ALIGN_CENTER, tag = "big-tag",
    })
    local _, lv = K.pill(host, {
        x = paper and 313 or 316, y = 16, w = 84, h = 24, bg = cap.bg, bg_opa = cap.opa,
        border = true, border_color = T.c.card_line,
        dot_color = T.c.celadon, dot_x = 11, text_x = 22, text_w = 54,
        text = level_text(1), color = cap.txt, size = CFG.FONT.mini, tag = "big-lv",
    })

    -- 纸面段居中在纸签上：388 宽 → x = (418-388)/2 = 15，344..349
    local segs = K.segs(host, {
        x = paper and 15 or 24, y = paper and 344 or 346,
        w = SEG_W, h = SEG_H, gap = SEG_GAP,
        level = S.levels[1] or 0, on_color = T.c.gold,
        off_color = paper and T.c.track or 0x6E5C42, tag = "big-segs",
    })
    -- 按压高亮压在图标与文字之上，必须最后建
    W.hl(card, 12, "bigcard")

    H.big = { box = card, segs = segs, lv = lv }
end

local function build_mini(page, cb, H, i, x, y)
    local dev = CFG.DEVICES[i]
    local paper = T.is_paper()
    local cap = cap_style(paper)

    local card = W.box(page, {
        x = x, y = y, w = SW, h = SH, radius = 10,
        color = paper and T.c.card_line or T.c.btn, border_width = 0,
        on_click = function() cb.on_card(i) end, tag = "mini-" .. i,
    })

    local host
    if paper then
        host = W.box(card, {
            x = 1, y = 1, w = SW - 2, h = SH - 2, radius = 9,
            color = T.c.card_in, border_width = 0, tag = "mini-in-" .. i,
        })
        -- 图 0..112 + 实心纸签 112..178（与大卡同一套"照片 + 题跋"版式）
        -- 小卡专用 214×178 素材：与控件 1:1，绘制走直接拷贝而不是缩放采样
        W.image(host, { x = 0, y = 0, w = SW - 2, h = SH - 2, src = dev.img_p_s,
                        fit = "stretch", tag = "mini-img-" .. i })
        W.box(host, { x = 0, y = 112, w = SW - 2, h = SH - 114, color = T.c.card_in,
                      border_width = 0, tag = "mini-slip-" .. i })
        W.shape(host, {
            x = 0, y = 112, w = SW - 2, h = 1,
            items = { { type = "line", x1 = 0, y1 = 0, x2 = SW - 2, y2 = 0,
                        color = T.c.card_line, width = 1, opacity = 200 } },
            tag = "mini-slip-line-" .. i,
        })
        W.text(host, {
            x = 16, y = 118, w = 150, h = 21, text = dev.name, size = CFG.FONT.body,
            color = T.c.text, tag = "mini-name-" .. i,
        })
        W.text(host, {
            x = 16, y = 142, w = 150, h = 19, text = dev.en, size = CFG.FONT.mini,
            color = T.c.gold_dim, tag = "mini-en-" .. i,
        })
    else
        host = card
        -- 小卡专用 216×180 素材（与控件 1:1），不能复用大卡的 420×376：
        -- 0.51x 下采样是每帧逐像素采样，全屏重绘时是最贵的一项
        W.image(host, { x = 0, y = 0, w = SW, h = SH, src = dev.img_s, fit = "stretch", tag = "mini-img-" .. i })
        W.box(host, { x = 0, y = 96, w = SW, h = 84, color = 0x080604, color_opacity = 120,
                      border_width = 0, tag = "mini-sh-" .. i })
        W.text(host, {
            x = 14, y = 126, w = 150, h = 21, text = dev.name, size = CFG.FONT.body,
            color = T.c.text, tag = "mini-name-" .. i,
        })
        W.text(host, {
            x = 14, y = 150, w = 150, h = 19, text = dev.en, size = CFG.FONT.mini,
            color = T.c.gold_dim, tag = "mini-en-" .. i,
        })
    end

    local _, lv = K.pill(host, {
        x = paper and 127 or 130, y = 12, w = 72, h = 22, bg = cap.bg, bg_opa = cap.opa,
        dot_color = T.c.celadon, dot_x = 9, text_x = 19, text_w = 48,
        text = level_text(i), color = cap.txt, size = CFG.FONT.mini, tag = "mini-lv-" .. i,
    })
    W.hl(card, 10, "mini-" .. i)

    H.mini[i] = { box = card, lv = lv }
end

function M.build(root, cb)
    local H = { mini = {} }

    local page = W.box(root, {
        x = 0, y = 0, w = CFG.LAY.stage_w, h = CFG.LAY.stage_h, color = -1, border_width = 0,
        tag = "page-wall",
    })
    -- 绝对坐标由 box 沿父链自动算出（stage 在 88,58），此处不能再 mark 成 0,0

    build_big(page, cb, H)
    build_mini(page, cb, H, 2, SX1, SY1)
    build_mini(page, cb, H, 3, SX2, SY1)
    build_mini(page, cb, H, 4, SX1, SY2)
    build_mini(page, cb, H, 5, SX2, SY2)

    H.page = page

    --[[
    增量刷新：只改段与胶囊文字，不动图片层（P1），并且值没变就不下发（P5）。
    refresh 在每次调档、每次从详情页返回时都会走到，
    没有这层短路就是 5 张卡片各重排一次文字 + 大卡重建 10 个刻度图元。
    ]]
    local cache = {}
    function H.refresh()
        local v = S.levels[1] or 0
        if cache[1] ~= v then
            cache[1] = v
            if H.big then
                if H.big.segs then H.big.segs.set(v) end
                if H.big.lv then pcall(function() H.big.lv:set_text(level_text(1)) end) end
            end
        end
        for i = 2, 5 do
            local m = H.mini[i]
            local lv = S.levels[i] or 0
            if m and m.lv and cache[i] ~= lv then
                cache[i] = lv
                pcall(function() m.lv:set_text(level_text(i)) end)
            end
        end
    end

    return H
end

return M
