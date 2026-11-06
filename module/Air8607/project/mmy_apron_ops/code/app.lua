--[[
@module  app
@summary AeroDeck 页面路由、全局节拍与轻提示
@version 1.0
@date    2026.11.05
]]
local conf = require "conf"
local theme = require "theme"
local sim = require "sim"
local art = require "art"

local M = {}
local C = theme.C
local SZ = theme.SZ

local pages = {}
local cur, cur_name, root = nil, nil, nil
local tick_n = 0
local toast_obj = nil
local toast_timer = nil

-- 收掉提示条及其定时器：页面切换后旧定时器不能再动已销毁的组件
local function clear_toast()
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    if toast_obj then
        pcall(function() toast_obj:destroy() end)
        toast_obj = nil
    end
end

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
    clear_toast()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    root = theme.backdrop(nil)
    local ok, page = pcall(pages[name], root, arg)
    if not ok then
        -- 构建失败绝不能留下"没人管"的半成品页面
        log.error("app", "页面构建失败", name, page)
        clear_toast()
        pcall(function() root:destroy() end)
        root = theme.backdrop(nil)
        page = M.error_page(root, name, tostring(page))
    end
    cur = page
    if cur and cur.refresh then pcall(cur.refresh) end
end

function M.error_page(p, name, err)
    local w = 660
    local card = theme.card(p, math.floor((conf.W - w) / 2), 190, w, 210, {
        color = C.panel, radius = 16, border_color = C.red, border_width = 1,
    })
    theme.label(card, 20, 18, w - 40, 28, "页面构建失败：" .. tostring(name), SZ.l, C.ink)
    theme.label(card, 20, 58, w - 40, 60, err or "", SZ.xs, C.ink3)
    theme.ghost(card, 20, 148, 130, 36, "返回机坪", {
        on_click = function() M.go("apron") end,
    })
    return {}
end

function M.root() return root end

-- ===================== 轻提示 =====================
function M.toast(text, color)
    if not root then return end
    clear_toast()
    local w, h = 420, 44
    local x, y = math.floor((conf.W - w) / 2), 64
    local box = theme.card(root, x, y, w, h, {
        color = C.panel3, radius = 22, border_color = color or C.cyan, border_width = 1,
    })
    theme.label(box, 16, 0, w - 32, h, text, SZ.s, color or C.ink, airui.TEXT_ALIGN_CENTER)
    toast_obj = box
    local ref = box
    toast_timer = sys.timerStart(function()
        toast_timer = nil
        if ref then pcall(function() ref:destroy() end) end
        if toast_obj == ref then toast_obj = nil end
    end, 2600)
end

-- ===================== 通用小组件 =====================
-- 子页面顶栏：返回键 + 标题 + 时钟
function M.subbar(p, title, subtitle, on_back)
    local bar = airui.container({ parent = p, x = 0, y = 0, w = conf.W, h = 56, color = C.bg0, radius = 0 })
    theme.box(bar, 0, 55, conf.W, 1, C.line, 0)

    local back = theme.card(bar, 16, 10, 36, 36, {
        color = C.panel2, radius = 18, border_color = C.line, border_width = 1,
        on_click = on_back or function() M.go("apron") end,
    })
    art.icon(back, "back", 9, 9, 18, C.ink2)

    theme.label(bar, 62, 6, 340, 26, title, SZ.l, C.ink)
    if subtitle then
        theme.label(bar, 62, 30, 480, 20, subtitle, SZ.xs, C.ink3)
    end

    local clock = theme.label(bar, conf.W - 190, 15, 100, 26, sim.clock(), SZ.m, C.ink,
        airui.TEXT_ALIGN_RIGHT)
    local date = theme.label(bar, conf.W - 330, 20, 132, 20, sim.date_text(), SZ.xs, C.ink3,
        airui.TEXT_ALIGN_RIGHT)
    return bar, clock, date
end

function M.card_title(parent, x, y, w, text, right_text, right_color)
    theme.label(parent, x, y, w, 22, text, SZ.m, C.ink)
    if right_text then
        return theme.label(parent, x, y, w, 22, right_text, SZ.xs, right_color or C.ink3,
            airui.TEXT_ALIGN_RIGHT)
    end
end

-- 圆形状态点
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

-- 闪烁点：按帧计数在亮/暗之间切换，用于报警呼吸灯
function M.blink(shape, r, color, on)
    if not shape then return end
    pcall(function()
        shape:set_items({
            { type = "circle", cx = r, cy = r, r = r, color = color, fill = true,
              fill_color = color, width = 1, opacity = on and 255 or 70 },
        })
    end)
end

function M.remain_text(min)
    min = math.floor(min)
    if min >= 0 then
        if min < 60 then return min .. " 分钟后" end
        local h = math.floor(min / 60)
        local m = min % 60
        return h .. " 小时" .. (m > 0 and (m .. " 分") or "") .. "后"
    end
    min = -min
    if min < 60 then return "已超时 " .. min .. " 分" end
    return "已超时 " .. math.floor(min / 60) .. " 小时"
end

-- ===================== 启动 =====================
function M.start()
    math.randomseed(os.time() % 100000)
    sim.init()

    M.register("apron", function(p) return require("ui_apron").build(p) end)
    M.register("flight", function(p, arg) return require("ui_flight").build(p, arg) end)
    M.register("weather", function(p) return require("ui_weather").build(p) end)
    M.register("settings", function(p) return require("ui_settings").build(p) end)

    M.go("apron")

    -- 全局动画节拍：只驱动"当前页"的 anim，页面自己不起定时器，
    -- 从根上避免切页后旧页回调访问已销毁组件
    sys.timerLoopStart(function()
        if cur and cur.anim then pcall(cur.anim) end
    end, conf.anim.frame_ms)

    -- 全局推理节拍：驱动航班保障推进与气象演化
    -- 注意：这里必须把异常打出来。sim.tick() 一旦裸调用抛错，
    -- 后面的 refresh 就不会执行，表现为"界面有数据但永远不刷新"且日志无痕。
    sys.timerLoopStart(function()
        tick_n = tick_n + 1
        local ok, err = pcall(sim.tick)
        if not ok then
            log.error("app", "sim.tick 抛错", err)
        end
        if cur and cur.refresh then
            local ok2, err2 = pcall(cur.refresh)
            if not ok2 then
                log.error("app", "页面 refresh 抛错", cur_name, err2)
            end
        end
        -- 心跳：每 10 个周期打一行，用来判断"数据在跑但 UI 没动"还是"数据没跑"
        if tick_n % 10 == 0 then
            log.info("app", string.format("tick=%d sim=%s 在坪=%d 页=%s",
                tick_n, sim.clock(), sim.on_stand(), tostring(cur_name)))
        end
    end, conf.sim.interval_ms)

    -- 分钟级轻刷新（时钟/倒计时）
    sys.timerLoopStart(function()
        if cur and cur.tick_minute then pcall(cur.tick_minute) end
    end, 20000)

    log.info("app", "AeroDeck 启动完成")
end

return M
