--[[
@module  ui_main
@summary 今天吃什么 - 界面骨架（顶栏 + 三页签 + 页容器显隐 + 全局互斥）
@version 1.0
@date    2026.10.26
@usage
app_main 在 airui.init() 与字库加载之后调 require("ui_main").build()：
1、铺全屏奶油底 + 几个柔和的装饰圆（一共 6 个图元，一次画完不再动）；
2、搭顶栏：圆形图标 + 「今天吃什么 / WHAT TO EAT TODAY」+ 三枚胶囊页签 + 滑动指示条；
3、建三个页面容器（y 从 68 起，**不能盖住顶栏**，否则会吃掉页签的点击），
   默认进「减脂餐」，其它页首次点开时才 build（懒加载，开机只付一页的开销）；
4、页签切换 = set_hidden，各页的上一次结果原样保留；
5、转盘转动期间 busy=true，页签点击与其它转盘一律忽略。

页面模块统一接口：M.build(页面容器, ctx)，ctx 里只有一件东西：
  ctx.set_busy(bool)  —— 让 ui_main 知道现在是否正在转，用于页签互斥。
]]

local T = require "ui_theme"
local D = require "ui_draw"

local C = T.c
local M = {}

local TAB_TEXT = { "减脂餐", "家常菜", "外卖" }
local MODS = {
    require "ui_page_diet",
    require "ui_page_home",
    require "ui_page_takeout",
}

local boxes, tabs, indicator = {}, {}, nil
local built = {}
local cur = 0
local busy = false

-- 传给页面模块的控制面板
local ctx = {}
function ctx.set_busy(v)
    busy = v and true or false
end
function ctx.is_busy()
    return busy
end

-- ==================== 背景 ====================

local function build_bg()
    D.box(nil, 0, 0, T.screen.w, T.screen.h, { color = C.bg })
    -- 装饰圆只放在视觉空档（转盘左侧竖条、转盘与面板之间的缝），
    -- 全部一块 shape 画完，之后再也不 set_items。
    D.shape(nil, 0, 0, T.screen.w, T.screen.h, {
        D.disc(34, 196, 46, C.bg_dot, 255),
        D.disc(28, 430, 30, C.bg_dot2, 255),
        D.disc(616, 150, 26, C.bg_dot2, 255),
        D.disc(614, 470, 38, C.bg_dot, 255),
        D.disc(150, 596, 40, C.bg_dot2, 255),
        D.disc(910, 596, 30, C.bg_dot, 255),
    })
end

-- ==================== 顶栏 ====================

local function build_topbar()
    local top = D.box(nil, 0, 0, T.screen.w, T.topbar.h, { color = C.bg })
    D.box(top, 0, T.topbar.h - 1, T.screen.w, 1, { color = C.line })

    local icon = D.box(top, 24, 14, 40, 40, { color = C.accent, radius = 20 })
    D.label_mid(icon, 0, 20, 40, "吃", T.f.mid, C.white, D.ALIGN_CENTER)

    D.label_mid(top, 76, 24, 320, "今天吃什么", T.f.big, C.ink)
    D.label_mid(top, 78, 52, 320, "WHAT TO EAT TODAY", T.f.mini, C.mute)

    indicator = D.box(top, T.tab[1].x + (T.tab.w - T.tab_indicator.w) / 2,
        T.tab_indicator.y, T.tab_indicator.w, T.tab_indicator.h,
        { color = C.accent, radius = 3 })

    for i = 1, 3 do
        tabs[i] = D.button(top, T.tab[i].x, T.tab[i].y, T.tab.w, T.tab.h,
            TAB_TEXT[i], T.f.card, {
                bg = C.white, text_color = C.sub, radius = 21,
                border = C.line, border_w = 1,
                on_click = function() M.switch(i) end,
            })
    end
end

-- ==================== 页签切换 ====================

local function style_tab(k, active)
    if not tabs[k] then return end
    tabs[k]:set_style({
        bg_color = active and C.accent or C.white,
        text_color = active and C.white or C.sub,
        border_color = active and C.accent or C.line,
        border_width = 1,
    })
end

function M.switch(i, force)
    if not force then
        if busy then
            log.info("ui_main", "转盘转动中，忽略页签切换", i)
            return
        end
        if cur == i then return end
    end

    if not built[i] then
        local t0 = D.now_ms()
        MODS[i].build(boxes[i], ctx)
        built[i] = true
        log.info("ui_main", "页面构建", TAB_TEXT[i], D.now_ms() - t0, "ms")
    end

    for k = 1, 3 do
        boxes[k]:set_hidden(k ~= i)
        style_tab(k, k == i)
    end
    D.set_pos(indicator, T.tab[i].x + (T.tab.w - T.tab_indicator.w) / 2, T.tab_indicator.y)
    cur = i
    log.info("ui_main", "切到页面", i, TAB_TEXT[i])
end

-- ==================== 构建 ====================

function M.build()
    build_bg()
    build_topbar()
    for i = 1, 3 do
        boxes[i] = D.box(nil, T.page.x, T.page.y, T.page.w, T.page.h, {})
        boxes[i]:set_hidden(true)
    end
    M.switch(1, true)
    log.info("ui_main", "界面就绪")
end

return M
