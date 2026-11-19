--[[
@module  page_entry
@summary 入口两屏：首页（取件 / 存件分流）与取件码输入
@note 按 docs/共享储物柜中控UI.html 折算：stage padding 22/40/18 →
      内容区 1024×440 起于 body y=22；首页两卡 461×440 间距 22；
      取件屏左栏 40..654，键盘 684..984（3 列 92 + gap 12，行高 88 + 12）。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local P = require "page_locker"

local C, F, R = T.c, T.f, T.r
local S = P.S

local digit_lb, cell_ref, cell_on = {}, {}, {}
local ok_bg, ok_t, ok_on
local digit_cache = {}

-- ==================== 首页 ====================

-- 柜机图标 140×140：箭头 + 柜体 + 灯带 + 3×2 柜格 + 一盏亮格。
-- up = 取件（箭头朝上、亮格在上排），否则存件。opacity 走 0..255。
local function locker_art(up)
    local items = {
        { type = "rect", x = 6, y = 30, w = 128, h = 104, radius = 30, width = 3,
          color = C.white, opacity = 87 },
        { type = "line", x1 = 26, y1 = 40, x2 = 114, y2 = 40, width = 2,
          color = C.white, opacity = 77 },
    }
    local cells = { { 18, 45 }, { 55, 45 }, { 92, 45 }, { 18, 86 }, { 55, 86 }, { 92, 86 } }
    local lit = up and 2 or 5
    for i = 1, 6 do
        local c = cells[i]
        if i == lit then
            items[#items + 1] = { type = "rect", x = c[1], y = c[2], w = 30, h = 33,
                radius = 9, width = 4, color = C.white,
                fill = true, fill_color = C.white, fill_opacity = 128 }
        else
            items[#items + 1] = { type = "rect", x = c[1], y = c[2], w = 30, h = 33,
                radius = 9, width = 2, color = C.white, opacity = 56,
                fill = true, fill_color = C.white, fill_opacity = 33 }
        end
    end
    local ty = up and 24 or 8
    local hy = up and 8 or 24
    items[#items + 1] = { type = "line", x1 = 70, y1 = ty, x2 = 70, y2 = hy,
        width = 3, color = C.white, round_start = true, round_end = true }
    items[#items + 1] = { type = "line", x1 = 60, y1 = 16, x2 = 70, y2 = hy,
        width = 3, color = C.white, round_start = true, round_end = true }
    items[#items + 1] = { type = "line", x1 = 80, y1 = 16, x2 = 70, y2 = hy,
        width = 3, color = C.white, round_start = true, round_end = true }
    return items
end

-- 入口卡 461×440（.card：radius 28 / padding 28 32 26）
local function entry_card(body, cfg)
    local card = W.box(body, { x = cfg.x, y = cfg.y, w = 461, h = 440,
        color = cfg.color, radius = R.card, tag = cfg.tag })

    -- 角标胶囊（.pill）：白 18% 底 + 6px 圆点
    W.box(card, { x = 32, y = 28, w = cfg.pill_w, h = 30, color = C.white,
        radius = 15, opa = 46, border_w = 1, border_color = C.white, tag = "pill" })
    W.box(card, { x = 45, y = 40, w = 6, h = 6, color = C.white, radius = 3, tag = "pill_dot" })
    W.text_mid(card, { x = 59, y = 28, w = cfg.pill_w - 34, h = 30, text = cfg.pill,
        size = F.small, color = C.white, align = airui.TEXT_ALIGN_LEFT, tag = "pill_t" })

    W.text(card, { x = 32, y = 147, w = 219, h = 75, text = cfg.title,
        size = F.hero, color = C.white, tag = "hero" })
    W.text_mid(card, { x = 32, y = 232, w = 219, h = 16, text = cfg.en,
        size = F.mono, color = C.white, align = airui.TEXT_ALIGN_LEFT, tag = "en" })
    W.text(card, { x = 32, y = 258, w = 219, h = 19, text = cfg.desc,
        size = F.small, color = C.white, tag = "desc" })

    if cfg.chips == 4 then
        for i = 1, 4 do
            W.box(card, { x = 32 + (i - 1) * 20, y = 279, w = 14, h = 19, color = C.white,
                radius = 5, opa = 51, border_w = 1, border_color = C.white, tag = "chip" })
        end
    else
        local hh = { 11, 17, 24 }
        for i = 1, 3 do
            W.box(card, { x = 32 + (i - 1) * 14, y = 303 - hh[i], w = 8, h = hh[i],
                color = C.white, radius = 3, opa = 51,
                border_w = 1, border_color = C.white, tag = "chip" })
        end
    end

    W.shape(card, { x = 285, y = 160, w = 140, h = 140,
        items = locker_art(cfg.up), tag = "deco" })

    W.shape(card, { x = 32, y = 380, w = 397, h = 2, tag = "rule", items = {
        { type = "line", x1 = 0, y1 = 1, x2 = 397, y2 = 1, width = 1,
          color = C.white, opacity = 64 },
    } })
    W.text_mid(card, { x = 32, y = 395, w = 397, h = 19, text = cfg.bot,
        size = F.small, color = C.white, align = airui.TEXT_ALIGN_LEFT, tag = "bot" })

    -- 右上圆形箭头钮（.go 46×46）
    W.box(card, { x = 389, y = 24, w = 46, h = 46, color = C.white, radius = 23,
        opa = 51, border_w = 1, border_color = C.white, tag = "go" })
    W.shape(card, { x = 403, y = 38, w = 18, h = 18, tag = "go_ic", items = {
        { type = "line", x1 = 1, y1 = 9, x2 = 17, y2 = 9, width = 2,
          color = C.white, round_start = true, round_end = true },
        { type = "line", x1 = 10, y1 = 2, x2 = 17, y2 = 9, width = 2,
          color = C.white, round_start = true, round_end = true },
        { type = "line", x1 = 17, y1 = 9, x2 = 10, y2 = 16, width = 2,
          color = C.white, round_start = true, round_end = true },
    } })

    W.press(card, { x = 0, y = 0, w = 461, h = 440, radius = R.card,
        on_click = cfg.on_click, tag = "card_hit" })
    return card
end

P.build("home", function(body)
    entry_card(body, {
        x = 40, y = 22, color = C.orange, tag = "c1", up = true,
        pill = "自助取件", pill_w = 118,
        title = "取 件", en = "PICK UP", desc = "输入短信中的取件码",
        chips = 4, bot = "4 位码 · 即时开柜",
        on_click = function() P.nav("code") end,
    })
    entry_card(body, {
        x = 523, y = 22, color = C.teal, tag = "c2", up = false,
        pill = "自助存件", pill_w = 118,
        title = "存 件", en = "DEPOSIT", desc = "选择柜格规格",
        chips = 3, bot = "按实际时长计费",
        on_click = function() P.nav("spec") end,
    })
end)

-- ==================== 取件码 ====================

local function refresh_digits()
    for i = 1, P.CODE_LEN do
        local ch = S.digits:sub(i, i)
        local txt = (ch ~= "") and ch or " "
        if digit_cache[i] ~= txt then
            digit_cache[i] = txt
            local lb = digit_lb[i]
            if lb then pcall(function() lb:set_text(txt) end) end
        end
        local on = (#S.digits >= i)
        if cell_on[i] ~= on then
            cell_on[i] = on
            local cel = cell_ref[i]
            if cel then
                W.glass(cel, on and C.orange or C.card)
                local lb = digit_lb[i]
                if lb then pcall(function() lb:set_color(on and C.white or C.ink) end) end
            end
        end
    end
    local full = (#S.digits >= P.CODE_LEN)
    if ok_on ~= full then
        ok_on = full
        if ok_bg then W.glass(ok_bg, full and C.orange or C.mute_bg) end
        if ok_t then pcall(function() ok_t:set_color(full and C.white or C.ink2) end) end
    end
end

local function push(ch)
    if #S.digits >= P.CODE_LEN then return end
    S.digits = S.digits .. ch
    refresh_digits()
    if #S.digits == P.CODE_LEN then
        sys.timerStart(function() P.submit() end, 300)
    end
end

local function backspace()
    if #S.digits == 0 then return end
    S.digits = S.digits:sub(1, -2)
    refresh_digits()
end

local function keypad(parent)
    local rows = {
        { "1", "2", "3" },
        { "4", "5", "6" },
        { "7", "8", "9" },
        { "删除", "0", "确认" },
    }
    for r = 1, 4 do
        for c = 1, 3 do
            local v = rows[r][c]
            local x = 684 + (c - 1) * 104
            local y = 48 + (r - 1) * 100
            if v == "删除" then
                W.box(parent, { x = x, y = y, w = 92, h = 88, color = C.card,
                    radius = R.key, border_w = 1, border_color = C.line2, tag = "key" })
                W.text_mid(parent, { x = x, y = y, w = 92, h = 88, text = v,
                    size = F.small, color = C.ink2, tag = "key_t" })
                W.press(parent, { x = x, y = y, w = 92, h = 88, radius = R.key,
                    tag = "key_p", on_click = backspace })
            elseif v == "确认" then
                -- 未就绪态底 mute_bg 与页面 bg 同为米白，原先配 mute_ln 细边等于隐形；
                -- 底色保留（它表达"还差几位"），描边提到 line2 让键始终看得见
                ok_bg = W.box(parent, { x = x, y = y, w = 92, h = 88, color = C.mute_bg,
                    radius = R.key, border_w = 1, border_color = C.line2, tag = "key_ok" })
                ok_t = W.text_mid(parent, { x = x, y = y, w = 92, h = 88, text = v,
                    size = F.small, color = C.ink2, tag = "key_ok_t" })
                W.press(parent, { x = x, y = y, w = 92, h = 88, radius = R.key,
                    tag = "key_ok_p", on_click = function() P.submit() end })
                ok_on = false
            else
                W.box(parent, { x = x, y = y, w = 92, h = 88, color = C.card,
                    radius = R.key, border_w = 1, border_color = C.line2, tag = "key" })
                W.text_mid(parent, { x = x, y = y, w = 92, h = 88, text = v,
                    size = F.h3, color = C.ink, tag = "key_t" })
                W.press(parent, { x = x, y = y, w = 92, h = 88, radius = R.key,
                    tag = "key_p", on_click = function() push(v) end })
            end
        end
    end
end

P.build("code", function(body)
    -- 左栏：返回 / eyebrow / 大标题 / 4 个码格 / 提示，整体垂直居中（总高 297，88..385）
    -- 120×46 / 22px：原 90×34 配 16px 在 1024 宽的屏上偏小，指按目标也太窄。
    -- 上提到 y=88（底边 134），下方 eyebrow 在 147，净间距 13px，左栏其余元素不用挪
    P.button(body, { x = 40, y = 88, w = 120, h = 46, text = "返回",
        size = F.body, color = C.card, tcolor = C.ink2,
        border_w = 1, border_color = C.line2,
        on_click = function() P.nav("home") end })

    W.box(body, { x = 40, y = 155, w = 18, h = 3, color = C.orange, radius = 1, tag = "eb_bar" })
    W.text_mid(body, { x = 66, y = 147, w = 120, h = 19, text = "取件",
        size = F.small, color = C.orange, align = airui.TEXT_ALIGN_LEFT, tag = "eb" })

    W.text(body, { x = 40, y = 183, w = 460, h = 41, text = "输入 4 位取件码",
        size = F.h1, color = C.ink, tag = "h2" })

    for i = 1, P.CODE_LEN do
        local x = 40 + (i - 1) * 88
        cell_on[i] = nil
        digit_cache[i] = nil
        cell_ref[i] = W.box(body, { x = x, y = 252, w = 74, h = 88, color = C.card,
            radius = R.box, border_w = 2, border_color = C.line2, tag = "slot" })
        digit_lb[i] = W.text_mid(body, { x = x, y = 252, w = 74, h = 88,
            text = " ", size = F.num_m, color = C.ink, tag = "slot_t" })
    end

    W.text_mid(body, { x = 40, y = 366, w = 560, h = 19,
        text = "取件码见短信通知，遇到问题请拨 400-820-1234",
        size = F.small, color = C.ink2, align = airui.TEXT_ALIGN_LEFT, tag = "hint" })

    keypad(body)
    refresh_digits()
end)

return true
