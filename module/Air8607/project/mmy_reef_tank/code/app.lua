--[[
@module  app
@summary ReefOS 页面路由、全局采样循环与轻提示
@version 1.0
@date    2026.10.27
]]
local conf = require "conf"
local theme = require "theme"
local sim = require "sim"

local M = {}
local C = theme.C
local SZ = theme.SZ

local pages = {}
local cur, cur_name, root = nil, nil, nil
local toast_obj = nil

-- ===================== 页面注册与切换 =====================
function M.register(name, builder)
    pages[name] = builder
end

function M.current() return cur_name end

function M.go(name, arg)
    if not pages[name] then
        log.warn("app", "未知页面", name)
        return
    end
    local old = cur
    cur, cur_name = nil, name
    if old and old.destroy then pcall(old.destroy) end
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    root = theme.backdrop(nil)
    local ok, page = pcall(pages[name], root, arg)
    if not ok then
        -- 构建失败绝不能留下"没人管"的半成品页面：清掉重画错误页，
        -- 否则旧页残留的动画/定时器会持续访问已销毁的组件
        log.error("app", "页面构建失败", name, page)
        pcall(function() root:destroy() end)
        root = theme.backdrop(nil)
        page = M.error_page(root, name, tostring(page))
    end
    cur = page
    if cur and cur.refresh then pcall(cur.refresh) end
end

-- 页面构建失败时的兜底页：给出错误信息 + 回主页入口，且不持有任何定时器
function M.error_page(p, name, err)
    local w = 660
    local card = theme.card(p, math.floor((conf.W - w) / 2), 190, w, 200, {
        color = C.panel, radius = 16, border_color = C.coral, border_width = 1,
    })
    theme.label(card, 20, 18, w - 40, 28, "页面构建失败：" .. tostring(name), SZ.l, C.ink)
    theme.label(card, 20, 56, w - 40, 56, err or "", SZ.xs, C.ink3)
    theme.ghost(card, 20, 140, 130, 36, "返回主页", {
        on_click = function() M.go("tank") end,
    })
    return {}
end

function M.root() return root end

-- ===================== 轻提示 =====================
function M.toast(text, color)
    if not root then return end
    if toast_obj then
        pcall(function() toast_obj:destroy() end)
        toast_obj = nil
    end
    local w, h = 380, 44
    local x, y = math.floor((conf.W - w) / 2), 64
    local box = theme.card(root, x, y, w, h, {
        color = C.panel3, radius = 22, border_color = color or C.cyan, border_width = 1,
    })
    theme.label(box, 16, 0, w - 32, h, text, SZ.s, color or C.ink, airui.TEXT_ALIGN_CENTER)
    toast_obj = box
    local ref = box
    sys.timerStart(function()
        if ref then pcall(function() ref:destroy() end) end
        if toast_obj == ref then toast_obj = nil end
    end, 2600)
end

-- ===================== 通用小组件 =====================
-- 顶部栏（子页面）：返回键 + 标题 + 时钟
function M.subbar(p, title, subtitle, on_back)
    local bar = airui.container({ parent = p, x = 0, y = 0, w = conf.W, h = 56, color = C.bg0, radius = 0 })
    theme.box(bar, 0, 55, conf.W, 1, C.line, 0)

    local back = theme.card(bar, 16, 10, 36, 36, {
        color = C.panel2, radius = 18, border_color = C.line, border_width = 1,
        on_click = on_back or function() M.go("tank") end,
    })
    require("art").icon(back, "back", 9, 9, 18, C.ink2)

    theme.label(bar, 62, 6, 300, 26, title, SZ.l, C.ink)
    if subtitle then
        theme.label(bar, 62, 30, 420, 20, subtitle, SZ.xs, C.ink3)
    end

    local clock = theme.label(bar, conf.W - 190, 15, 100, 26, sim.clock(), SZ.m, C.ink,
        airui.TEXT_ALIGN_RIGHT)
    local date = theme.label(bar, conf.W - 330, 20, 132, 20, sim.date_text(), SZ.xs, C.ink3,
        airui.TEXT_ALIGN_RIGHT)
    return bar, clock, date
end

-- 卡片标题行：图标 + 标题 + 可选右侧文字
function M.card_title(parent, x, y, w, text, right_text, right_color)
    theme.label(parent, x, y, w, 22, text, SZ.m, C.ink)
    if right_text then
        return theme.label(parent, x, y, w, 22, right_text, SZ.xs, right_color or C.ink3,
            airui.TEXT_ALIGN_RIGHT)
    end
end

-- 状态点（呼吸感靠颜色区分）
function M.dot(parent, x, y, r, color)
    return theme.shape(parent, x, y, r * 2, r * 2, {
        { type = "circle", cx = r, cy = r, r = r, color = color, fill = true, fill_color = color, width = 1 },
    })
end

-- shape 没有 set_color，改色必须重设 items
function M.dot_paint(dot, r, color)
    if not dot then return end
    pcall(function()
        dot:set_items({
            { type = "circle", cx = r, cy = r, r = r, color = color, fill = true, fill_color = color, width = 1 },
        })
    end)
end

function M.fmt_signed(v)
    if v >= 0 then return "+" .. string.format("%.1f", v) end
    return string.format("%.1f", v)
end

-- ===================== 启动 =====================
function M.start()
    math.randomseed(os.time() % 100000)
    sim.init()

    M.register("tank", function(p) return require("ui_tank").build(p) end)
    M.register("metric", function(p, arg) return require("ui_metric").build(p, arg) end)
    M.register("light", function(p) return require("ui_light").build(p) end)
    M.register("settings", function(p) return require("ui_settings").build(p) end)

    M.go("tank")

    -- 全局动画节拍：只驱动"当前页"的 anim，页面自己不再起定时器，
    -- 从根上避免切页后旧页回调访问已销毁组件
    sys.timerLoopStart(function()
        if cur and cur.anim then pcall(cur.anim) end
    end, conf.anim.frame_ms)

    -- 全局采样：1.2s 一次，驱动数据模型与当前页面刷新
    sys.timerLoopStart(function()
        sim.tick()
        if cur and cur.refresh then pcall(cur.refresh) end
    end, conf.sim.interval_ms)

    -- 分钟级轻刷新（实时时钟/倒计时）
    sys.timerLoopStart(function()
        if cur and cur.tick_minute then pcall(cur.tick_minute) end
    end, 20000)

    log.info("app", "ReefOS 启动完成")
end

return M
