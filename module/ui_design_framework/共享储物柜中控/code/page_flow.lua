--[[
@module  page_flow
@summary 流程两屏：存件规格选择、开门引导、结果确认
@note 按 docs/共享储物柜中控UI.html 折算，内容区 1024×440 起于 body y=22：
      规格屏 head 22..139 / 三卡 150..378（302 宽 gap 19）/ opbar 396..446；
      开门屏内容居中，总高 415（35..450）；结果屏总高 342（71..413）。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local P = require "page_locker"

local C, F, R = T.c, T.f, T.r
local S = P.S

-- ==================== 存件：规格选择 ====================

-- 柜格图 96×96：按档位画 1 / 2 / 3 个横格，选中的那格点亮
local function cab_art(size, on)
    local lay = {
        S = { { 12, 28, 72, 40 } },
        M = { { 12, 14, 72, 30 }, { 12, 52, 72, 30 } },
        L = { { 12, 10, 72, 20 }, { 12, 38, 72, 20 }, { 12, 66, 72, 20 } },
    }
    local items = {}
    for i, b in ipairs(lay[size]) do
        if on then
            items[#items + 1] = { type = "rect", x = b[1], y = b[2], w = b[3], h = b[4],
                radius = 10, width = 3, color = C.orange,
                fill = true, fill_color = C.orange, fill_opacity = 33 }
        else
            items[#items + 1] = { type = "rect", x = b[1], y = b[2], w = b[3], h = b[4],
                radius = 10, width = 3, color = C.cab }
        end
    end
    return items
end

local function spec_card(body, key, x)
    local sp = P.SPECS[key]
    local on = (S.spec == key)
    -- 卡面 C.card（#FFFFFF）与页面 bg（#FFF7F1）明度只差一档，靠 2px 浅描边在真机上
    -- 几乎看不出边界。先在卡下 3px 处铺一层 line 色圆角块，卡片压上去后只露出底部 3px
    -- 下沿，视觉上就是一道软阴影，把卡片从背景里抬起来。
    W.box(body, { x = x, y = 153, w = 302, h = 228, color = C.line,
        radius = R.box, tag = "spec_sh" })

    local card = W.box(body, { x = x, y = 150, w = 302, h = 228,
        color = on and C.orange_l or C.card, radius = R.box,
        border_w = 2, border_color = on and C.orange or C.line2, tag = "spec" })

    -- 右上勾徽标（.tick 26×26）：仅选中时出现
    if on then
        W.box(card, { x = 260, y = 14, w = 26, h = 26, color = C.orange,
            radius = R.chip, tag = "tick" })
        W.shape(card, { x = 266, y = 20, w = 14, h = 14, tag = "tick_ic", items = {
            { type = "line", x1 = 2, y1 = 7, x2 = 6, y2 = 11, width = 2,
              color = C.white, round_start = true, round_end = true },
            { type = "line", x1 = 6, y1 = 11, x2 = 12, y2 = 3, width = 2,
              color = C.white, round_start = true, round_end = true },
        } })
    end

    W.shape(card, { x = 103, y = 24, w = 96, h = 96,
        items = cab_art(key, on), tag = "cab" })

    W.text_mid(card, { x = 16, y = 132, w = 270, h = 29, text = sp.name,
        size = F.body, color = on and C.orange or C.ink, tag = "nm" })
    W.text_mid(card, { x = 16, y = 168, w = 270, h = 19, text = sp.goods,
        size = F.small, color = on and C.orange or C.ink3, tag = "sz" })

    -- 底行：左「2 元/时」，右「余6格」。
    -- ① 不用 ¥：hzfont 走 GB2312，¥ 常缺字形（真机上就是空白）。
    -- ② 两个字号必须按行底对齐，不能用 text_mid 各自居中：
    --    26px 行高 29、16px 行高 19，各自居中会让两条基线错开 5px，看着就是"没对齐"。
    --    这里用 W.text 直接给 y —— 大数字 190..219，小单位 200..219，底部同线。
    W.text(card, { x = 16, y = 190, w = 40, h = 29, text = tostring(sp.price),
        size = F.h3, color = on and C.orange or C.ink,
        align = airui.TEXT_ALIGN_LEFT, tag = "pr" })
    W.text(card, { x = 60, y = 200, w = 56, h = 19, text = "元/时",
        size = F.small, color = C.ink3, align = airui.TEXT_ALIGN_LEFT, tag = "per" })
    W.text(card, { x = 186, y = 200, w = 100, h = 19, text = sp.left,
        size = F.small, color = C.ink3, align = airui.TEXT_ALIGN_RIGHT, tag = "qty" })

    -- 热区按内容区铺（302−2×2、228−2×2）：照外框写会越过 cw/ch 被收敛并打越界日志
    W.press(card, { x = 0, y = 0, w = 298, h = 224, radius = R.box, tag = "spec_p",
        on_click = function()
            S.spec = key
            P.nav("spec")
        end })
    return card
end

P.build("spec", function(body)
    -- 120×46 / 22px：原 90×34 配 16px 在 1024 宽的屏上偏小，指按目标也太窄。
    -- 往上提到 y=8（底边 54）而不是往下压，下方 eyebrow 在 62，净间距 8px 不必挪其他元素
    P.button(body, { x = 40, y = 8, w = 120, h = 46, text = "返回",
        size = F.body, color = C.card, tcolor = C.ink2,
        border_w = 1, border_color = C.line2,
        on_click = function() P.nav("home") end })

    W.box(body, { x = 40, y = 70, w = 18, h = 3, color = C.teal, radius = 1, tag = "eb_bar" })
    W.text_mid(body, { x = 66, y = 62, w = 120, h = 19, text = "存件",
        size = F.small, color = C.teal, align = airui.TEXT_ALIGN_LEFT, tag = "eb" })
    W.text(body, { x = 40, y = 98, w = 460, h = 41, text = "选择柜格规格",
        size = F.h1, color = C.ink, tag = "h2" })

    spec_card(body, "S", 40)
    spec_card(body, "M", 361)
    spec_card(body, "L", 682)

    -- opbar：上分隔线 + 计费说明 + 主按钮
    W.shape(body, { x = 40, y = 388, w = 944, h = 2, tag = "rule", items = {
        { type = "line", x1 = 0, y1 = 1, x2 = 944, y2 = 1, width = 1, color = C.line },
    } })
    W.text_mid(body, { x = 40, y = 411, w = 640, h = 19,
        text = "按实际存放时长计费 · 取件时结算",
        size = F.small, color = C.ink3, align = airui.TEXT_ALIGN_LEFT, tag = "note" })

    P.button(body, { x = 784, y = 396, w = 200, h = 50, text = "确认存件",
        size = F.sub, color = C.orange, tcolor = C.white, radius = 15,
        on_click = function() P.submit() end })
end)

-- ==================== 开门引导 ====================

-- 开门图 120×120：右侧柜体 + 左侧张开成梯形的门板。
-- 关键在三条门边线都必须站在柜体左边缘 x=44 上（原来门线从 x=30 甩到 x=4，
-- 与柜体不共边，看起来是几根浮着的斜线而不是一扇门）。
-- shape 没有多边形，梯形只能靠 line 逐边拼；门板比柜体矮，斜视透视才立得住。
local function door_art()
    return {
        -- 柜体：淡橙填充。fill_opacity 取 20 —— 固件按 0-255 或 0-100 解析都得到"很淡"，
        -- 不像 128 那样在两种量级下一个看不见、一个糊成实心。
        { type = "rect", x = 44, y = 6, w = 68, h = 108, radius = 12, width = 3,
          color = C.orange, fill = true, fill_color = C.orange, fill_opacity = 20 },
        -- 柜内隔板：暗示里面分格，否则就是一个空框
        { type = "line", x1 = 52, y1 = 60, x2 = 104, y2 = 60, width = 2, color = C.line2 },
        -- 门板三步收口：柜体左上角 → 外沿上端 → 外沿下端 → 柜体左下角
        { type = "line", x1 = 44, y1 = 6, x2 = 10, y2 = 20, width = 3,
          color = C.orange, round_start = true, round_end = true },
        { type = "line", x1 = 10, y1 = 20, x2 = 10, y2 = 94, width = 3,
          color = C.orange, round_start = true, round_end = true },
        { type = "line", x1 = 10, y1 = 94, x2 = 44, y2 = 108, width = 3,
          color = C.orange, round_start = true, round_end = true },
        -- 门把手：贴在门板自由边内侧
        { type = "line", x1 = 17, y1 = 52, x2 = 17, y2 = 64, width = 3,
          color = C.orange, round_start = true, round_end = true },
    }
end

P.build("open", function(body)
    local pick = (S.mode == "pick")
    W.shape(body, { x = 452, y = 35, w = 120, h = 120, items = door_art(), tag = "art" })

    -- 大柜号：A6 用 102px，右对齐到 512；「号柜」跟在右侧
    W.text_mid(body, { x = 372, y = 145, w = 140, h = 105, text = S.box_no,
        size = F.num_xl, color = C.orange, align = airui.TEXT_ALIGN_RIGHT, tag = "no" })
    W.text_mid(body, { x = 518, y = 214, w = 80, h = 32, text = "号柜",
        size = F.h3, color = C.ink2, align = airui.TEXT_ALIGN_LEFT, tag = "unit" })

    W.text_mid(body, { x = 312, y = 264, w = 400, h = 29, text = "柜门已弹开",
        size = F.h3, color = C.ink, tag = "h3" })
    W.text_mid(body, { x = 312, y = 303, w = 400, h = 19,
        text = pick and "请取走物品，然后用力关好柜门" or "请放入物品，然后用力关好柜门",
        size = F.small, color = C.ink2, tag = "p" })

    -- 等待确认胶囊
    W.box(body, { x = 427, y = 340, w = 170, h = 40, color = C.card,
        radius = 20, border_w = 1, border_color = C.line2, tag = "scan" })
    W.box(body, { x = 445, y = 355, w = 9, h = 9, color = C.teal, radius = 4, tag = "scan_dot" })
    W.text_mid(body, { x = 462, y = 340, w = 122, h = 40, text = "等待关门确认",
        size = F.small, color = C.ink2, align = airui.TEXT_ALIGN_LEFT, tag = "scan_t" })

    P.button(body, { x = 386, y = 394, w = 252, h = 56, text = "我已关好门",
        size = F.sub, color = C.orange, tcolor = C.white, radius = R.btn,
        on_click = function() P.submit() end })
end)

-- ==================== 结果 ====================

P.build("done", function(body)
    local ok = S.ok
    local pick = (S.mode == "pick")

    -- 状态圆：成功青绿 + 白勾；失败改用警示橙
    local tone = ok and C.teal or C.orange
    W.box(body, { x = 464, y = 71, w = 96, h = 96, color = tone, radius = 48, tag = "ico" })
    W.shape(body, { x = 490, y = 97, w = 44, h = 44, tag = "ico_ic", items = ok and {
        { type = "line", x1 = 8, y1 = 23, x2 = 18, y2 = 33, width = 6,
          color = C.white, round_start = true, round_end = true },
        { type = "line", x1 = 18, y1 = 33, x2 = 36, y2 = 12, width = 6,
          color = C.white, round_start = true, round_end = true },
    } or {
        { type = "line", x1 = 12, y1 = 12, x2 = 32, y2 = 32, width = 6,
          color = C.white, round_start = true, round_end = true },
        { type = "line", x1 = 32, y1 = 12, x2 = 12, y2 = 32, width = 6,
          color = C.white, round_start = true, round_end = true },
    } })

    W.text_mid(body, { x = 262, y = 183, w = 500, h = 35,
        text = ok and (S.box_no .. " 号柜已" .. (pick and "打开" or "锁好")) or "操作失败",
        size = F.h2, color = C.ink, tag = "h3" })
    W.text_mid(body, { x = 262, y = 228, w = 500, h = 19,
        text = ok and (pick and "请取走物品，并随手关好柜门" or "柜门已锁好，请妥善保管取件码")
            or "请重试或联系客服",
        size = F.small, color = C.ink2, tag = "p" })

    -- 两枚标签：柜格号 + 取件码
    if ok then
        -- 描边由 line 提到 line2：白底标签放在米白页面上，1px 的 line 几乎隐形
        W.box(body, { x = 376, y = 265, w = 120, h = 60, color = C.card,
            radius = R.tag, border_w = 1, border_color = C.line2, tag = "tag1" })
        W.text_mid(body, { x = 376, y = 273, w = 120, h = 19, text = "柜格",
            size = F.small, color = C.ink3, tag = "tag1_l" })
        W.text_mid(body, { x = 376, y = 291, w = 120, h = 29, text = S.box_no,
            size = F.h3, color = C.orange, tag = "tag1_v" })

        W.box(body, { x = 510, y = 265, w = 140, h = 60, color = C.card,
            radius = R.tag, border_w = 1, border_color = C.line2, tag = "tag2" })
        W.text_mid(body, { x = 510, y = 273, w = 140, h = 19, text = "取件码",
            size = F.small, color = C.ink3, tag = "tag2_l" })
        W.text_mid(body, { x = 510, y = 291, w = 140, h = 29, text = S.digits,
            size = F.h3, color = C.orange, tag = "tag2_v" })
    end

    P.button(body, { x = 376, y = 351, w = 272, h = 62, text = "完成",
        size = F.sub, color = C.orange, tcolor = C.white, radius = R.btn,
        on_click = function() P.nav("home") end })
end)

return true
