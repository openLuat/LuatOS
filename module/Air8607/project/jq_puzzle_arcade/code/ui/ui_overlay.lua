--[[
@module  ui_overlay
@summary 通用弹窗（遮罩 + 面板 + 两个按钮），七款游戏与排行榜共用
@version 1.0
@date    2026.11.03
@usage
全屏唯一一套弹窗，避免每款游戏各建一套 LVGL 对象：
1、overlay.build(base)          在 ui_shell 搭骨架时调用一次（建好后默认隐藏）
2、overlay.set_back(fn)         指定"返回大厅"的默认动作
3、overlay.open{...}            显示：title / body / color / p1 / f1 / p2 / f2
4、overlay.close()              隐藏
5、overlay.is_open()            是否正在显示（触摸分发据此屏蔽棋盘点击）
@note
按钮不能在代码里增删（Button 没有 set_hidden 接口），所以固定两个按钮：
左按钮语义由调用方决定（再玩一次 / 接着玩 / 知道啦），右按钮恒为"回大厅"。
文字用 set_text 换，回调用闭包变量换。
标题色取调用方给的主题色再压暗 28%：糖果色当字写在白底上会糊。
]]

local fx = require "fx"
local T = require "theme"

local M = {}

local w = {}          -- 控件
local opened = false
local fn1, fn2        -- 当前两个按钮的动作
local on_back         -- 默认"返回大厅"

local function button(parent, x, y, ww, hh, text, style, fn)
    return airui.button({
        parent = parent, x = x, y = y, w = ww, h = hh,
        text = text, font_size = T.f.text,
        style = style,
        on_click = function() fn() end,
    })
end

--[[搭弹窗骨架（在 airui 初始化之后、界面首次显示之前调用）
@param object base 全屏根容器
]]
function M.build(base)
    -- 遮罩：盖住整个舞台（含外框）。浅色界面不用黑幕，用暖棕薄纱，
    -- 压得下去但不会突然变黑吓到孩子
    w.mask = airui.container({
        parent = base,
        x = T.stage.x, y = T.stage.y, w = T.stage.w, h = T.stage.h,
        color = 0x8A6E4E, color_opacity = 96, radius = 12, border_width = 0,
    })

    local o = T.overlay
    w.panel = airui.container({
        parent = w.mask,
        x = o.px, y = o.py, w = o.pw, h = o.ph,
        color = T.c.panel, color_opacity = 255, radius = 24,
        border_color = T.paint.board_ln, border_width = 3,
    })
    -- 顶部色条：颜色随结果变（胜/负/提示），set_color 换
    w.bar = airui.container({
        parent = w.panel, x = 24, y = 18, w = o.pw - 48, h = 6,
        color = T.c.cyan, color_opacity = 255, radius = 3, border_width = 0,
    })

    w.title = airui.label({
        parent = w.panel, x = 24, y = 34, w = o.pw - 48, h = 44,
        text = "", font_size = T.f.val, color = T.c.cyan,
        align = airui.TEXT_ALIGN_CENTER,
    })
    -- 正文给到 126px：16 号字一行约 21px，够放 5~6 行，
    -- 玩法说明和成绩结算都不会被下边缘切掉
    w.body = airui.label({
        parent = w.panel, x = 24, y = 84, w = o.pw - 48, h = 126,
        text = "", font_size = T.f.text, color = T.c.dim,
        align = airui.TEXT_ALIGN_CENTER,
    })

    w.b1 = button(w.panel, 40, 224, 180, 48, "再玩一次", T.style.btn_go, function()
        local f = fn1
        if f then f() end
    end)
    w.b2 = button(w.panel, 244, 224, 180, 48, "回大厅", T.style.btn_ghost, function()
        local f = fn2 or on_back
        if f then f() end
    end)

    w.mask:set_hidden(true)
end

function M.set_back(fn)
    on_back = fn
end

--[[显示弹窗
@param table opt {
    title = "无路可走",
    body  = "本局得分 1024\n步数 128",     -- 换行用 \n，LVGL label 支持
    color = T.c.red,                      -- 顶部色条与标题色
    p1    = "再来一局",                   -- 左按钮文字
    f1    = function() end,               -- 左按钮动作
    p2    = "返回大厅",                   -- 右按钮文字（默认沿用）
    f2    = function() end,               -- 右按钮动作（默认返回大厅）
}
]]
function M.open(opt)
    opt = opt or {}
    local color = opt.color or T.c.cyan
    w.bar:set_color(color, 255)
    w.title:set_text(opt.title or "")
    w.title:set_color(fx.shade(color, -0.3))
    w.body:set_text(opt.body or "")
    w.b1:set_text(opt.p1 or "知道啦")
    w.b2:set_text(opt.p2 or "回大厅")
    fn1 = opt.f1
    fn2 = opt.f2
    opened = true
    w.mask:set_hidden(false)
end

function M.close()
    opened = false
    fn1, fn2 = nil, nil
    if w.mask then w.mask:set_hidden(true) end
end

function M.is_open()
    return opened
end

return M
