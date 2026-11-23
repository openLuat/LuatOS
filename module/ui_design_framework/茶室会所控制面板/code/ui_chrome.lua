--[[
常驻框架：左轴导航 + 顶栏 + 底部场景条
必须晚于页面创建（保证盖在页面上层）；本层不放全屏遮罩，避免吞掉页面点击

版面（绝对坐标，父为 chrome 1024×600 内容区）：
  左轴   0..88     顶栏 88..1024 × 0..58
  舞台   88..1024 × 58..470（页面用，本层不占）
  场景条 88..1024 × 470..600
]]

local T = require "ui_theme"
local W = require "ui_widget"
local K = require "ui_kit"
local CFG = require "app_config"

local M = {}

local RAIL_W = CFG.LAY.rail_w          -- 88
local HEAD_H = CFG.LAY.head_h          -- 58
local HEAD_X = RAIL_W                  -- 88
local HEAD_W = CFG.W - RAIL_W          -- 936
local TRAY_Y = CFG.LAY.tray_y          -- 470
local TRAY_H = CFG.LAY.tray_h          -- 130

-- 左轴导航按钮：60×58 放在 88 宽里，左右各 14
local NAV = {
    { key = "scene",   text = CFG.txt.rail_scene,   y = 120 },
    { key = "service", text = CFG.txt.rail_service, y = 182 },
    { key = "mute",    text = CFG.txt.rail_mute,    y = 470 },
    { key = "theme",   text = CFG.txt.rail_theme,   y = 532 },
}
local NAV_X, NAV_W, NAV_H = 14, 60, 58

-- 场景条按钮：218×76，间距 10，左右各留 16（16+218*4+10*3=918 ≤ 936-16）
local TB_W, TB_H, TB_Y, TB_GAP, TB_X = 218, 76, 40, 10, 16

--------------------------------------------------------------------------
-- 图标：21×21 的 shape 图元，颜色固定（选中态由竖条 + 文字表达，避免运行期重建）
--------------------------------------------------------------------------
local function icon_items(key, color)
    if key == "scene" then
        local it = {}
        for r = 0, 1 do
            for c = 0, 1 do
                it[#it + 1] = { type = "rect", x = 1 + c * 11, y = 1 + r * 11, w = 9, h = 9,
                                radius = 2, color = color, width = 0,
                                fill = true, fill_color = color, fill_opacity = 255 }
            end
        end
        return it
    elseif key == "service" then
        -- 铃：环形钟体 + 底部横线
        return {
            { type = "circle", cx = 10, cy = 9, r = 7, width = 2, color = color },
            { type = "line", x1 = 2, y1 = 17, x2 = 18, y2 = 17, color = color, width = 2, opacity = 255 },
            { type = "line", x1 = 10, y1 = 1, x2 = 10, y2 = 2, color = color, width = 2, opacity = 255 },
        }
    elseif key == "mute" then
        -- 喇叭：方箱 + 三角口 + 斜杠
        return {
            { type = "rect", x = 2, y = 8, w = 6, h = 6, radius = 1, color = color, width = 0,
              fill = true, fill_color = color, fill_opacity = 255 },
            { type = "line", x1 = 8, y1 = 11, x2 = 15, y2 = 5, color = color, width = 2, opacity = 255 },
            { type = "line", x1 = 8, y1 = 11, x2 = 15, y2 = 17, color = color, width = 2, opacity = 255 },
            { type = "line", x1 = 15, y1 = 5, x2 = 15, y2 = 17, color = color, width = 2, opacity = 255 },
            { type = "line", x1 = 5, y1 = 14, x2 = 16, y2 = 3, color = color, width = 2, opacity = 255 },
        }
    elseif key == "theme" then
        --[[
        主题：左「日」右「月」，两套主题本来就是明/暗两态。

        上一版是"圆环 + 左半实心矩形"，想表达半明半暗，但 21px 的圆里
        塞一个 7×15 的直角矩形，四个角全戳到圆弧外面，渲染出来是个烂方块。
        shape 图元只有 line/circle/ellipse/rect，没有 arc，做不出真正的半月，
        所以改用日/月并置：两个干净图元，远看也能读出"换装"。
        ]]
        return {
            { type = "circle", cx = 5.5, cy = 10, r = 3, width = 0,
              fill = true, fill_color = color, fill_opacity = 255 },
            { type = "circle", cx = 14.5, cy = 10, r = 4, width = 2, color = color },
        }
    else
        return {
            { type = "circle", cx = 10, cy = 10, r = 8, width = 2, color = color },
        }
    end
end

--------------------------------------------------------------------------
-- 左轴
--------------------------------------------------------------------------
local function build_rail(chrome, cb, H)
    local rail = W.box(chrome, {
        x = 0, y = 0, w = RAIL_W, h = CFG.H,
        color = T.c.rail, color_opacity = 96, border_width = 0, tag = "rail",
    })

    -- 印章：44×44 圆角块 + 「松」
    local seal = W.box(rail, {
        x = 22, y = 22, w = 44, h = 44, radius = 6,
        color = T.c.seal, border_width = 0, tag = "seal",
    })
    W.text(seal, {
        x = 0, y = 10, w = 44, h = 25, text = "松", size = CFG.FONT.brand,
        color = T.c.seal_txt, align = airui.TEXT_ALIGN_CENTER, tag = "seal-t",
    })

    -- 当前场景名（切场景时只改这一条文字）
    H.scene_name = W.text(rail, {
        x = 0, y = 250, w = RAIL_W, h = 22, text = "", size = CFG.FONT.body,
        color = T.c.gold, align = airui.TEXT_ALIGN_CENTER, tag = "rail-scene",
    })

    for i = 1, #NAV do
        local n = NAV[i]
        local box = W.box(rail, {
            x = NAV_X, y = n.y, w = NAV_W, h = NAV_H, radius = 10,
            color = T.c.rail_on, color_opacity = 0, border_width = 0,
            on_click = function() cb.on_rail(n.key) end, tag = "rail-" .. n.key,
        })
        W.shape(box, {
            x = 19, y = 10, w = 21, h = 21,
            items = icon_items(n.key, T.c.dim), tag = "rail-ic-" .. n.key,
        })
        local lbl = W.text(box, {
            x = 0, y = 34, w = NAV_W, h = 19, text = n.text, size = CFG.FONT.mini,
            color = T.c.dim, align = airui.TEXT_ALIGN_CENTER, tag = "rail-lb-" .. n.key,
        })
        -- 选中竖条：常驻在按钮内，未选中用 opacity 0 藏起来（不重建对象）
        local tick = W.box(box, {
            x = 0, y = 16, w = 2, h = 26, radius = 1,
            color = T.c.gold, color_opacity = 0, border_width = 0, tag = "rail-tick-" .. n.key,
        })
        W.hl(box, 10, "rail-" .. n.key)
        H.nav[n.key] = { box = box, lbl = lbl, tick = tick }
    end
    H.rail = rail
end

--------------------------------------------------------------------------
-- 顶栏
--------------------------------------------------------------------------
local function build_head(chrome, H)
    local head = W.box(chrome, {
        x = HEAD_X, y = 0, w = HEAD_W, h = HEAD_H,
        color = T.c.scrim, color_opacity = 108, border_width = 0, tag = "head",
    })
    -- 内容区 936×58
    W.text(head, {
        x = 18, y = 16, w = 110, h = 25, text = CFG.ROOM.name, size = CFG.FONT.brand,
        color = T.c.text, tag = "room",
    })
    W.text(head, {
        x = 132, y = 19, w = 250, h = 19, text = CFG.ROOM.meta, size = CFG.FONT.mini,
        color = T.c.dim, tag = "room-meta",
    })

    local badge_box, badge_lbl = K.pill(head, {
        x = 396, y = 17, w = 80, h = 24,
        bg = T.c.btn, bg_opa = 170, border = true, border_color = T.c.line,
        dot_color = T.c.celadon, dot_x = 11, text_x = 22, text_w = 50,
        text = CFG.ROOM.badge, color = T.c.gold, size = CFG.FONT.mini, tag = "badge",
    })
    H.badge = badge_lbl
    H.badge_box = badge_box

    -- 时钟：会变的数字走等宽格（F5）
    H.clock = W.num(head, {
        x = 840, y = 6, w = 76, h = 28,
        template = "99:99", size = CFG.FONT.time, color = T.c.text, align = "center", tag = "clock",
    })
    H.date = W.text(head, {
        x = 706, y = 36, w = 210, h = 19, text = "", size = CFG.FONT.mini,
        color = T.c.dim, align = airui.TEXT_ALIGN_RIGHT, tag = "date",
    })
    H.head = head
end

--------------------------------------------------------------------------
-- 底部场景条
--------------------------------------------------------------------------
local function build_tray(chrome, cb, H)
    local tray = W.box(chrome, {
        x = HEAD_X, y = TRAY_Y, w = HEAD_W, h = TRAY_H,
        color = T.c.scrim, color_opacity = 150, border_width = 0, tag = "tray",
    })
    -- 内容区 936×130
    W.text(tray, {
        x = 16, y = 10, w = 110, h = 19, text = CFG.txt.tray_title, size = CFG.FONT.mini,
        color = T.c.dim, tag = "tray-t",
    })
    W.text(tray, {
        x = 700, y = 10, w = 220, h = 19, text = CFG.txt.tray_note, size = CFG.FONT.mini,
        color = T.c.faint, align = airui.TEXT_ALIGN_RIGHT, tag = "tray-note",
    })

    for k = 1, #CFG.SCENES do
        local sc = CFG.SCENES[k]
        local bx = TB_X + (k - 1) * (TB_W + TB_GAP)
        local btn = W.box(tray, {
            x = bx, y = TB_Y, w = TB_W, h = TB_H, radius = 12,
            color = T.c.btn, border_width = 1, border_color = T.c.line,
            on_click = function() cb.on_scene(k) end, tag = "scene-" .. k,
        })
        -- 内容区 216×74
        local tick = W.box(btn, {
            x = 0, y = 8, w = 3, h = 58, radius = 2,
            color = T.c.gold, color_opacity = 0, border_width = 0, tag = "scene-tick-" .. k,
        })
        local title = W.text(btn, {
            x = 18, y = 12, w = 120, h = 21, text = sc.name, size = CFG.FONT.body,
            color = T.c.text, tag = "scene-t-" .. k,
        })
        W.text(btn, {
            x = 18, y = 38, w = 140, h = 19, text = sc.en, size = CFG.FONT.mini,
            color = T.c.faint, tag = "scene-en-" .. k,
        })
        W.text(btn, {
            x = 166, y = 6, w = 34, h = 34, text = sc.num, size = 28,
            color = T.c.mark, align = airui.TEXT_ALIGN_CENTER, tag = "scene-num-" .. k,
        })
        W.hl(btn, 12, "scene-" .. k)
        H.scene[k] = { box = btn, title = title, tick = tick }
    end
    H.tray = tray
end

--------------------------------------------------------------------------
-- 对外接口
--------------------------------------------------------------------------
function M.build(root, cb)
    local H = { nav = {}, scene = {} }

    local chrome = W.box(root, {
        x = 0, y = 0, w = CFG.W, h = CFG.H,
        color = -1, border_width = 0, tag = "chrome",
    })
    W.mark(chrome, 0, 0)

    build_rail(chrome, cb, H)
    build_head(chrome, H)
    build_tray(chrome, cb, H)

    H.chrome = chrome

    --[[
    左轴 / 场景条 / 徽标都做「值没变就不下发」的短路（P5）：
    调一次档位要连带刷新这三处，若每次都 set_color，LVGL 会把这 4+4 个
    218×76 的按钮全部标脏重绘，连点 ± 时就是整条底栏在反复刷。
    ]]
    function H.set_rail(key)
        if H.rail_key == key then return end
        H.rail_key = key
        for k, v in pairs(H.nav) do
            local on = (k == key)
            if v.box then pcall(function() v.box:set_color(T.c.rail_on, on and 210 or 0) end) end
            if v.lbl then pcall(function() v.lbl:set_color(on and T.c.gold or T.c.dim, 255) end) end
            if v.tick then pcall(function() v.tick:set_color(T.c.gold, on and 255 or 0) end) end
        end
    end

    -- 场景条选中态
    function H.set_scene(k)
        if H.scene_key == k then return end
        H.scene_key = k
        for i, v in pairs(H.scene) do
            local on = (i == k)
            if v.box then pcall(function() v.box:set_color(on and T.c.btn_on or T.c.btn, 255) end) end
            if v.title then pcall(function() v.title:set_color(on and T.c.gold or T.c.text, 255) end) end
            if v.tick then pcall(function() v.tick:set_color(T.c.gold, on and 255 or 0) end) end
        end
        --[[
        手动调过档位后 S.scene = 0，不属于任何预设：左轴原来会写「自定义」，
        用户明确要求去掉，现在留空（label 常驻，只清文字，不动对象）。
        ]]
        if H.scene_name then
            local sc = CFG.SCENES[k]
            pcall(function() H.scene_name:set_text(sc and sc.name or "") end)
        end
    end

    function H.set_clock(hh, mm)
        -- hh 为 nil 时摆 "--:--"（num 块按位填字符，'-' 会落进数字格，
        -- 冒号格保持不动）。现在不传 nil，留着给以后"时间暂不可用"的场合
        if hh then
            W.num_set(H.clock, string.format("%02d:%02d", hh, mm))
        else
            W.num_set(H.clock, "--:--")
        end
    end

    function H.set_date(s)
        if H.date then pcall(function() H.date:set_text(s) end) end
    end

    function H.set_badge(s)
        if H.badge_txt == s then return end
        H.badge_txt = s
        if H.badge then
            local t = H.badge
            pcall(function() t:set_text(s) end)
        end
    end

    return H
end

return M
