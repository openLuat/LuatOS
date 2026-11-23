--[[
@module  router
@summary 页面路由（整页容器推到屏外负方向切换）+ 全局 toast + 主题胶囊
@version 1.0.0
@note 1) 页面切换不用 hide()/open()（真机 open() 恢复不回来），也不把页面摆到屏外正方向
         （会撑出滚动条）；统一把非当前页推到 (-屏宽, 0)，负方向只裁剪不产生滚动条。
      2) 切页动作延后 20ms 执行：点击回调里直接销毁正在派发事件的控件树不安全。
      3) toast 是 airui.screen 的直系子控件，绘制顺序 = 创建顺序；页面容器也是 screen 的
         子控件，每次切页都会新建、排在 toast 之后，把旧 toast 永久压在下面（点「保存设置」
         没输密码时提示看不见就是这个原因）。所以切页时一律拆掉 toast，等真正要提示时
         再按需重建，保证它一定是最后一个子控件。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local WP = require "wallpaper"
local C = T.c
local M = {}

local SW = T.screen.w
local pages = {}
local cur, cur_args
local pending = false
local toast_box, toast_lbl, toast_seq = nil, nil, 0

function M.register(name, mod)
    pages[name] = mod
end

local function place(active)
    for n, mod in pairs(pages) do
        if mod.root then
            local root = mod.root()
            if root then
                pcall(function() root:set_pos((n == active) and 0 or -SW, 0) end)
            end
        end
    end
end

local function do_go(name, args)
    local mod = pages[name]
    if not mod then
        log.error("router", "未知页面", name)
        return
    end
    -- toast 先拆：页面容器是 screen 的新子控件，会排在旧 toast 之后把它盖死
    M.drop_toast()
    -- 先建目标页再拆旧页：建与拆在同一次回调里完成，LVGL 只在回调返回后重绘，
    -- 中间不会出现一帧空屏（页面根容器是透明的，背景由 wallpaper 负责）
    mod.create(args or {})
    for n, other in pairs(pages) do
        if other ~= mod and other.destroy then other.destroy() end
    end
    cur, cur_args = name, args
    place(name)
end

-- 切页：延时到下一拍，避免在控件自己的点击回调里拆树
function M.go(name, args, immediate)
    if immediate then
        do_go(name, args)
        return
    end
    if pending then return end
    pending = true
    sys.timerStart(function()
        pending = false
        do_go(name, args)
    end, 20)
end

-- 切页 + 切完再提示：toast 必须在目标页创建之后建立，否则会被目标页的卡片盖住
function M.go_toast(name, args, msg)
    if pending then return end
    pending = true
    sys.timerStart(function()
        pending = false
        do_go(name, args)
        if msg then M.toast(msg) end
    end, 20)
end

function M.drop_toast()
    if toast_box then pcall(function() toast_box:destroy() end) end
    toast_box, toast_lbl = nil, nil
end

-- 全屏重建（切主题、数据大改后）
function M.rebuild()
    local name, args = cur, cur_args
    M.drop_toast()
    for _, mod in pairs(pages) do
        if mod.destroy then mod.destroy() end
    end
    do_go(name or "home", args)
end

-- 切主题：令牌已原地更新，背景纱层跟着换色（不重新解码照片），延后一帧重建并提示
function M.retheme(msg)
    if pending then return end
    pending = true
    sys.timerStart(function()
        pending = false
        WP.apply()
        M.rebuild()
        if msg then M.toast(msg) end
    end, 50)
end

function M.current()
    return cur, cur_args
end

-- 顶栏主题胶囊：文字显示「点击后进入」的外观
function M.theme_chip(parent, cfg)
    local dark = (T.mode == "dark")
    return W.chip(parent, {
        x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        text = dark and "浅色" or "深色",
        off_color = C.tile, off_opa = T.glass.tile_opa, off_tcolor = C.text_sub,
        on_click = function()
            local nm = dark and "light" or "dark"
            T.set_mode(nm)
            M.retheme("已切换到" .. (nm == "light" and "浅色" or "深色") .. "主题")
        end,
    })
end

-- 全局 toast：屏幕正中偏上的深色胶囊，2.4 秒后自动淡出
function M.toast(msg)
    if not toast_box then
        toast_box = airui.container({ parent = airui.screen, x = 302, y = 272, w = 420, h = 44,
            color = C.deep, radius = 22, border_width = 0 })
        W.glass(toast_box, C.deep, 0)
        toast_lbl = W.text_mid(toast_box, { text = "", x = 0, y = 0, w = 420, h = 44,
            size = T.f.body, color = C.text, align = airui.TEXT_ALIGN_CENTER })
    end
    toast_seq = toast_seq + 1
    local seq = toast_seq
    W.set(toast_lbl, msg)
    W.color(toast_lbl, C.text)
    W.glass(toast_box, C.deep, 238)
    sys.timerStart(function()
        if seq == toast_seq then
            W.glass(toast_box, C.deep, 0)
            W.set(toast_lbl, "")
        end
    end, 2400)
end

return M
