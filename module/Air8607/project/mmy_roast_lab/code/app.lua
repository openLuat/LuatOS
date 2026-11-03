--[[
@module  app
@summary ROAST LAB 页面路由、全局采样循环与轻提示
@version 1.0
@date    2026.10.30
]]
local conf = require("conf")
local theme = require("theme")
local sim = require("sim")

local M = {}
local C, SZ = theme.C, theme.SZ

local pages = {}
local cur, cur_name, root = nil, nil, nil
local toast_obj = nil

-- ===================== 页面注册与切换 =====================
function M.register(name, builder) pages[name] = builder end
function M.current() return cur_name end
function M.root() return root end

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
    root = theme.backdrop(nil, conf.W, conf.H)
    local ok, page = pcall(pages[name], root, arg)
    if not ok then
        -- 构建失败必须清掉半成品页面，避免旧定时器访问已销毁组件
        log.error("app", "页面构建失败", name, page)
        pcall(function() root:destroy() end)
        root = theme.backdrop(nil, conf.W, conf.H)
        page = M.error_page(root, name, tostring(page))
    end
    cur = page
    if cur and cur.refresh then pcall(cur.refresh) end
    M.touch_text()
end

function M.error_page(p, name, err)
    local w = 660
    local card = theme.card(p, math.floor((conf.W - w) / 2), 190, w, 200, {
        color = C.panel, radius = 16, border_color = C.red, border_width = 1,
    })
    theme.label(card, 20, 18, w - 40, 28, "页面构建失败：" .. tostring(name), SZ.l, C.ink)
    theme.label(card, 20, 56, w - 40, 60, err or "", SZ.xs, C.ink3)
    theme.ghost(card, 20, 140, 130, 36, "返回主页", { on_click = function() M.go("dash") end })
    return {}
end

-- ===================== 轻提示 =====================
function M.toast(text, color)
    if not root then return end
    if toast_obj then
        pcall(function() toast_obj:destroy() end)
        toast_obj = nil
    end
    local w, h = 420, 44
    local x, y = math.floor((conf.W - w) / 2), 62
    local box = theme.card(root, x, y, w, h, {
        color = C.panel3, radius = 22, border_color = color or C.copper2, border_width = 1,
    })
    theme.label(box, 16, 0, w - 32, h, text, SZ.s, color or C.ink, theme.CT)
    toast_obj = box
    local ref = box
    sys.timerStart(function()
        pcall(function() ref:destroy() end)
        if toast_obj == ref then toast_obj = nil end
    end, 2400)
end

-- ===================== 触摸自检 =====================
--[[订阅触摸事件，把最新坐标打在屏幕右下角并写串口。
不接串口也能判断故障层：
  右下角坐标不跳动 -> 触摸没进 AirUI，问题在驱动/接线/绑定
  坐标跳动但点按钮无反应 -> 控件被遮挡（container 默认可点击）或回调没挂上]]
local touch_txt
local touch_state = "TP 待机 · 点按屏幕"

-- 自检文字挂在屏幕层，切页后需要重建才能压在新页面之上
function M.touch_text()
    if not conf.touch.debug then return end
    if touch_txt then pcall(function() touch_txt:destroy() end) end
    touch_txt = theme.label(airui.screen, conf.W - 270, conf.H - 20, 260, 18,
        touch_state, SZ.xs, C.copper2, theme.RT)
end

function M.touch_debug()
    if not conf.touch.debug then return end
    M.touch_text()
    local names = { [0] = "NONE", "DOWN", "HOLD", "UP" }
    local ok = airui.touch_subscribe(function(state, x, y)
        touch_state = (names[state] or tostring(state)) .. " " .. tostring(x) .. "," .. tostring(y)
        pcall(function() touch_txt:set_text(touch_state) end)
        log.info("touch", names[state] or state, "x=" .. tostring(x), "y=" .. tostring(y))
    end)
    if not ok then
        touch_state = "TP 订阅不可用"
        pcall(function() touch_txt:set_text(touch_state) end)
        log.warn("app", "touch_subscribe 不可用，跳过触摸自检")
    end
end

-- ===================== 通用组件 =====================
function M.subbar(p, title, subtitle, on_back)
    local bar = airui.container({ parent = p, x = 0, y = 0, w = conf.W, h = 56, color = C.bg0, radius = 0 })
    theme.box(bar, 0, 55, conf.W, 1, C.line, 0)

    local back = theme.card(bar, 16, 10, 36, 36, {
        color = C.panel2, radius = 18, border_color = C.line, border_width = 1,
        on_click = on_back or function() M.go("dash") end,
    })
    require("art").icon(back, "back", 9, 9, 18, C.ink2)

    theme.label(bar, 62, 6, 360, 26, title, SZ.l, C.ink)
    if subtitle then theme.label(bar, 62, 31, 520, 18, subtitle, SZ.xs, C.ink3) end

    local clock = theme.label(bar, conf.W - 190, 15, 100, 26, M.clock(), SZ.m, C.ink,
        airui.TEXT_ALIGN_RIGHT)
    theme.label(bar, conf.W - 340, 20, 140, 20, M.date_text(), SZ.xs, C.ink3, airui.TEXT_ALIGN_RIGHT)
    return bar, clock
end

function M.dot(parent, x, y, r, color)
    return theme.shape(parent, x, y, r * 2, r * 2, {
        { type = "circle", cx = r, cy = r, r = r, color = color, fill = true, fill_color = color, width = 1 },
    })
end

-- shape 无 set_color，改色要重设 items
function M.dot_paint(dot, r, color)
    if not dot then return end
    pcall(function()
        dot:set_items({ { type = "circle", cx = r, cy = r, r = r, color = color,
            fill = true, fill_color = color, width = 1 } })
    end)
end

function M.clock()
    return os.date("%H:%M")
end

function M.date_text()
    return os.date("%Y-%m-%d")
end

-- ===================== 启动 =====================
-- 只建首屏，不起定时器：触摸绑定必须在界面搭好之后、刷新循环之前
function M.start()
    math.randomseed(os.time() % 100000)

    M.register("dash", function(p) return require("ui_dashboard").build(p) end)
    M.register("curve", function(p, arg) return require("ui_curve").build(p, arg) end)
    M.register("beans", function(p) return require("ui_beans").build(p) end)
    M.register("settings", function(p) return require("ui_settings").build(p) end)

    M.go("dash")
    log.info("app", "首屏构建完成")
end

-- 刷新循环：必须在 touch_init 之后调用
function M.loop()
    -- 全局采样：驱动数据模型与当前页刷新（页面不自己起定时器）
    sys.timerLoopStart(function()
        sim.tick()
        if cur and cur.refresh then pcall(cur.refresh) end
    end, conf.sim.interval_ms)

    -- 时钟刷新
    sys.timerLoopStart(function()
        if cur and cur.refresh_clock then pcall(cur.refresh_clock) end
    end, 15000)

    log.info("app", "ROAST LAB 启动完成")
end

return M
