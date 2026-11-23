--[[
场景详情：左大图 + 右控制面板（开关 / 档位刻度 / 连续调节 / 快捷档位）
本页按设备每次重建（切设备是低频操作），页内调档只做增量刷新
]]

local T = require "ui_theme"
local W = require "ui_widget"
local K = require "ui_kit"
local CFG = require "app_config"
local S = require "app_state"

local M = {}

-- 本页建在 stage 内（stage = 88,58 起 936×412），坐标相对 stage 内容区
-- 左图区（与场景墙大卡同位置，视觉上是同一张卡"展开"）
local HX, HY, HW, HH = 16, 18, 420, 376
-- 右面板
local PX, PY, PW, PH = 452, 18, 460, 376

-- 面板内容区（描边 1 → 458×374）
local CW = PW - 2          -- 458
local SW_ON, SW_H = K.SW_W, K.SW_H
local SW_X = CW - 24 - SW_ON   -- 382
-- 档位段：10 段 32 宽 + 6 间距 = 374，落在 24..434
local PG_W, PG_H, PG_GAP = 32, 12, 6
-- 快捷档位：3 个 124×40
local CH_W, CH_H, CH_GAP, CH_X = 124, 40, 19, 24

local function status_text(i)
    local v = S.levels[i] or 0
    if v <= 0 then return "已关闭" end
    return "已开启 · " .. v .. " 档"
end

function M.build(root, i, cb)
    local dev = CFG.DEVICES[i]
    local H = { chips = {} }

    --[[
    页面自铺一层底：详情页盖在场景墙上，图卡与面板之间有 16px 缝，
    不铺底就会从缝里透出下面的卡片边缘。

    用不透明（opacity 255）而不是半透明：这块区域盖满整个舞台，
    半透明时 LVGL 必须把下面的场景墙（1 张大图 + 4 张小图 + 文字）
    全部合成一遍再混色，等于详情页每帧多画一整页；不透明矩形可以走跳过下层的路径。
    ]]
    local page = W.box(root, {
        x = 0, y = 0, w = CFG.LAY.stage_w, h = CFG.LAY.stage_h,
        color = T.c.scrim, color_opacity = 255, border_width = 0,
        -- 铺满舞台并吃掉缝隙上的点击：否则从 16px 缝里会点到下面的场景墙卡片
        on_click = function() end, tag = "page-detail",
    })

    ------------------------------------------------------------------
    -- 左：大图
    ------------------------------------------------------------------
    -- 左图区同样是两套长相：暖夜暗调照片，宣纸晨光照片（见 ui_wall 顶部说明）
    local paper = T.is_paper()
    local art = W.box(page, {
        x = HX, y = HY, w = HW, h = HH, radius = 12,
        color = paper and T.c.card_line or T.c.btn, border_width = 0, tag = "detail-art",
    })
    local host
    if paper then
        -- 卡面 418×374：浅调图 + 实心纸签（与场景墙大卡同参数）
        host = W.box(art, {
            x = 1, y = 1, w = HW - 2, h = HH - 2, radius = 11,
            color = T.c.card_in, border_width = 0, tag = "detail-art-in",
        })
        W.image(host, { x = 0, y = 0, w = HW - 2, h = HH - 2, src = dev.img_p,
                        fit = "stretch", tag = "detail-img" })
        W.box(host, { x = 0, y = 262, w = HW - 2, h = 112, color = T.c.card_in,
                      border_width = 0, tag = "detail-slip" })
        W.shape(host, {
            x = 0, y = 262, w = HW - 2, h = 1,
            items = { { type = "line", x1 = 0, y1 = 0, x2 = HW - 2, y2 = 0,
                        color = T.c.card_line, width = 1, opacity = 200 } },
            tag = "detail-slip-line",
        })
        W.text(host, {
            x = 19, y = 272, w = 380, h = 30, text = dev.name, size = CFG.FONT.hero,
            color = T.c.text, align = airui.TEXT_ALIGN_CENTER, tag = "detail-name",
        })
        W.text(host, {
            x = 19, y = 306, w = 380, h = 19, text = dev.en, size = CFG.FONT.mini,
            color = T.c.gold_dim, align = airui.TEXT_ALIGN_CENTER, tag = "detail-en",
        })
    else
        host = art
        W.image(host, { x = 0, y = 0, w = HW, h = HH, src = dev.img, fit = "stretch", tag = "detail-img" })
        W.box(host, { x = 0, y = 160, w = HW, h = 140, color = 0x080604, color_opacity = 70,
                      border_width = 0, tag = "detail-sh1" })
        W.box(host, { x = 0, y = 256, w = HW, h = 120, color = 0x080604, color_opacity = 130,
                      border_width = 0, tag = "detail-sh2" })
        W.text(host, {
            x = 24, y = 286, w = 300, h = 30, text = dev.name, size = CFG.FONT.hero,
            color = T.c.text, tag = "detail-name",
        })
        W.text(host, {
            x = 24, y = 320, w = 300, h = 19, text = dev.en, size = CFG.FONT.mini,
            color = T.c.gold_dim, tag = "detail-en",
        })
    end

    ------------------------------------------------------------------
    -- 右：控制面板
    ------------------------------------------------------------------
    local panel = W.box(page, {
        x = PX, y = PY, w = PW, h = PH, radius = 12,
        color = T.c.panel, color_opacity = 238,
        border_width = 1, border_color = T.c.card_line, tag = "detail-panel",
    })

    local eyebrow = W.text(panel, {
        x = 24, y = 18, w = 220, h = 19, text = status_text(i), size = CFG.FONT.mini,
        color = T.c.celadon, tag = "detail-eyebrow",
    })

    local sw = K.switch(panel, {
        x = SW_X, y = 14, on = S.on(i),
        on_click = function() cb.on_power(i) end, tag = "detail-sw",
    })

    W.text(panel, {
        x = 24, y = 48, w = 410, h = 19, text = dev.desc, size = CFG.FONT.mini,
        color = T.c.dim, tag = "detail-desc",
    })

    W.shape(panel, {
        x = 24, y = 84, w = 410, h = 1,
        items = { { type = "line", x1 = 0, y1 = 0, x2 = 410, y2 = 0,
                    color = T.c.line, width = 1, opacity = 150 } },
        tag = "detail-line",
    })

    W.text(panel, {
        x = 24, y = 100, w = 60, h = 19, text = CFG.txt.panel_strength, size = CFG.FONT.mini,
        color = T.c.dim, tag = "detail-l1",
    })
    local lv_txt = W.text(panel, {
        x = 344, y = 100, w = 90, h = 19, text = (S.levels[i] or 0) .. " / " .. CFG.MAX_LEVEL,
        size = CFG.FONT.mini, color = T.c.gold, align = airui.TEXT_ALIGN_RIGHT, tag = "detail-lv",
    })

    local segs = K.segs(panel, {
        x = 24, y = 128, w = PG_W, h = PG_H, gap = PG_GAP,
        level = S.levels[i] or 0, tag = "detail-segs",
    })

    K.round_btn(panel, {
        x = 24, y = 164, d = 42, icon = "minus", color = T.c.text,
        on_click = function() cb.on_step(i, -1) end, tag = "detail-minus",
    })
    W.text(panel, {
        x = 76, y = 176, w = 290, h = 19, text = CFG.txt.panel_step, size = CFG.FONT.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_CENTER, tag = "detail-step",
    })
    K.round_btn(panel, {
        x = CW - 24 - 42, y = 164, d = 42, icon = "plus", color = T.c.text,
        on_click = function() cb.on_step(i, 1) end, tag = "detail-plus",
    })

    W.text(panel, {
        x = 24, y = 232, w = 410, h = 19, text = CFG.txt.panel_quote, size = CFG.FONT.mini,
        color = T.c.faint, tag = "detail-quote",
    })
    W.text(panel, {
        x = 24, y = 264, w = 150, h = 19, text = CFG.txt.panel_quick, size = CFG.FONT.mini,
        color = T.c.faint, tag = "detail-l2",
    })

    for c = 1, #CFG.QUICK do
        local v = CFG.QUICK[c]
        local box, lbl = K.pill(panel, {
            x = CH_X + (c - 1) * (CH_W + CH_GAP), y = 290, w = CH_W, h = CH_H,
            bg = T.c.chip, border = true, border_color = T.c.line,
            text = v .. " 档", color = T.c.dim, size = CFG.FONT.mini,
            align = airui.TEXT_ALIGN_CENTER, tag = "chip-" .. c, hl = true,
            on_click = function() cb.on_quick(i, v) end,
        })
        H.chips[v] = { box = box, lbl = lbl }
    end

    --[[
    返回：面板底部整宽一条（内容区 408×34，控件 410×36 落在 334..370）。

    为什么放这儿，而不是左上角一个圆形返回箭头：
      · 这是本页操作流线的终点——调完档位手还停在面板上，往下就是出口；
      · 左上角那 44px 圆钮在 1024 宽的横屏上离右手很远，且真要画箭头
        得拿 line 折线拼（GB2312 没有 →‹ 这类字形，直接打字是空心框）；
      · 整条 410 宽命中区，不会像小图标那样点空。
    原来只能点左轴「场景」返回，而它此刻还亮着，看着像"当前就在场景里"
    而不是一个能按的出口，这才是退不出去的原因。
    ]]
    local back = W.box(panel, {
        x = 24, y = 334, w = 410, h = 36, radius = 10,
        color = T.c.btn, border_width = 1, border_color = T.c.line,
        on_click = function() cb.on_back() end, tag = "detail-back",
    })
    -- 文字用金而不是正文色：上面三颗快捷档位是同尺寸同边框的"选项"，
    -- 颜色一致时这条会被看成第四颗胶囊，用强调色才读得出"这是一个动作"
    W.text(back, {
        x = 0, y = (36 - CFG.FONT.body - 3) // 2, w = 410 - 2, h = CFG.FONT.body + 3,
        text = CFG.txt.panel_back, size = CFG.FONT.body,
        color = T.c.gold, align = airui.TEXT_ALIGN_CENTER, tag = "detail-back-t",
    })
    W.hl(back, 18, "detail-back")

    H.page = page
    H.panel = panel

    ------------------------------------------------------------------
    -- 增量刷新：本页内的高频操作只走这里
    ------------------------------------------------------------------
    --[[
    增量刷新：档位值没变直接返回（P5）。
    ± 连点与快捷档最终都落到这里，没有短路的话每点一次都要
    重建 10 段刻度图元 + 4 处文字重排 + 3 个胶囊改色。
    ]]
    local shown
    function H.sync()
        local v = S.levels[i] or 0
        if shown == v then return end
        shown = v
        if segs then segs.set(v) end
        pcall(function() lv_txt:set_text(v .. " / " .. CFG.MAX_LEVEL) end)
        pcall(function() eyebrow:set_text(status_text(i)) end)
        if sw then sw.set(v > 0) end
        for value, h in pairs(H.chips) do
            local on = (v == value)
            if h.box then pcall(function() h.box:set_color(on and T.c.chip_on or T.c.chip, 255) end) end
            if h.lbl then pcall(function() h.lbl:set_color(on and T.c.gold or T.c.dim, 255) end) end
        end
    end

    return H
end

return M
