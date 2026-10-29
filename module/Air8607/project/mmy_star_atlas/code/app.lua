--[[
@module  app
@summary 星野观测台 - 应用骨架：页面路由、仿真天文时钟、全局状态、Toast
@version 1.0
@date    2026.10.28
]]
local conf   = require("conf")
local theme  = require("theme")
local astro  = require("astro")
local star_data = require("star_data")

local M = {}

local C = theme.C

M.conf = conf
M.theme = theme
M.astro = astro
M.data = star_data

-- ==================== 全局状态 ====================
M.state = {
    t        = 0,                 -- 仿真时间（UTC unix 秒）
    speed_i  = conf.time.default,
    paused   = false,
    page     = "sky",
    selected = nil,               -- 当前选中天体 {id, cn, ra, dec, mag, ...}
    queue    = {},                -- 观测队列（天体对象）
    mag_limit= conf.sky.mag_limit,
    labels   = conf.sky.labels,
    lines    = conf.sky.lines,
    exposure = { focal = 400, aperture = 80, iso = 3200 },
    last_tick= 0,
}

M.pages = {}
M.root = nil
M.page = nil
M.page_name = nil

-- ==================== 仿真时钟 ====================

--[[把系统时间对齐到当地 start_hour 作为起点；系统时间不可用时退回固定日期
]]
local function make_start_time()
    local now = os.time()
    if not now or now < 1600000000 then
        -- 固定一个秋季夜晚作为兜底
        return os.time({ year = 2026, month = 10, day = 28, hour = 20 }) or 1793200000
    end
    local tz = conf.site.tz
    local local_sec = (now + tz * 3600) % 86400
    local base = now - local_sec                       -- 当地 00:00 对应的 UTC
    return base + conf.time.start_hour * 3600
end

function M.speed()
    return conf.time.speeds[M.state.speed_i] or 1
end

function M.now()
    return M.state.t
end

function M.site()
    return conf.site
end

function M.lat() return conf.site.lat end
function M.lon() return conf.site.lon end
function M.tz()  return conf.site.tz end

-- 当前地方恒星时
function M.lst()
    return astro.lst(M.state.t, conf.site.lon)
end

-- 计算某个天体的当前地平坐标
function M.altaz(obj)
    local alt, az = astro.horizon(obj.ra, obj.dec, conf.site.lat, M.lst())
    return alt, az
end

-- ==================== 观测队列 ====================

function M.in_queue(id)
    for _, o in ipairs(M.state.queue) do
        if o.id == id then return true end
    end
    return false
end

function M.queue_add(obj)
    if M.in_queue(obj.id) then return false, "已在观测队列中" end
    if #M.state.queue >= conf.session.max_queue then return false, "队列已满（上限 6 个）" end
    local item = {
        id = obj.id, cn = obj.cn, kind = obj.kind or "恒星",
        ra = obj.ra, dec = obj.dec, mag = obj.mag, desc = obj.desc,
    }
    M.state.queue[#M.state.queue + 1] = item
    return true, "已加入观测队列：" .. obj.cn
end

function M.queue_remove(id)
    for i = #M.state.queue, 1, -1 do
        if M.state.queue[i].id == id then
            table.remove(M.state.queue, i)
            return true
        end
    end
    return false
end

-- ==================== 环境数据 ====================

--[[当前环境（云量/视宁度/透明度/观测指数）
]]
function M.env()
    local cloud, seeing, trans = astro.atmos(M.state.t, conf.site.bortle)
    local _, _, illum = astro.moon(M.state.t)
    local idx = astro.seeing_index(cloud, seeing, illum, conf.site.bortle)
    local sun_alt = astro.sun_horizon(M.state.t, conf.site.lat, conf.site.lon)
    local night = sun_alt < -12
    return {
        cloud = cloud, seeing = seeing, trans = trans,
        moon_illum = illum, index = idx,
        sun_alt = sun_alt, night = night,
    }
end

-- ==================== Toast ====================

local toast_box, toast_label, toast_timer

function M.toast(text, color)
    if not toast_box then return end
    toast_label:set_text(text)
    toast_box:set_color(theme.tint(color or C.line2))
    -- open() 会清隐藏并把 Toast 提到最前，保证盖在页面之上
    if toast_box.open then toast_box:open() else toast_box:set_hidden(false) end
    if toast_timer then sys.timerStop(toast_timer) end
    toast_timer = sys.timerStart(function()
        toast_box:set_hidden(true)
    end, conf.toast.ms)
end

local function build_toast()
    local w, h = 520, 54
    toast_box = airui.container({
        parent = M.root, x = (conf.W - w) / 2, y = conf.H - 118, w = w, h = h,
        color = theme.tint(C.line2), color_opacity = 235,
        radius = 27, border_width = 1, border_color = theme.tint(C.cyan),
    })
    toast_label = airui.label({
        parent = toast_box, x = 0, y = 14, w = w, h = h - 20,
        text = "", font = "hzfont", font_size = 18, color = theme.tint(C.ink),
    })
    if toast_label.set_align then
        pcall(toast_label.set_align, toast_label, airui.TEXT_ALIGN_CENTER)
    end
    toast_box:set_hidden(true)
end

-- ==================== 页面路由 ====================

function M.register(name, factory)
    M.pages[name] = factory
end

local function destroy_page()
    if M.page and M.page.root then
        pcall(function() M.page.root:destroy() end)
    end
    M.page = nil
end

--[[切换页面
@param name  sky / object / session / settings
@param arg   传给页面工厂的参数
]]
function M.go(name, arg)
    local factory = M.pages[name]
    if not factory then
        log.error("app", "页面不存在", name)
        return
    end
    destroy_page()
    M.page_name = name
    M.state.page = name
    local ok, page = pcall(factory, M, arg)
    if not ok then
        log.error("app", "页面创建失败 " .. name, tostring(page))
        return
    end
    M.page = page
    if page.after then
        theme.defer(page.after, 20)
    end
end

function M.refresh()
    M.go(M.page_name, M.page and M.page.arg)
end

-- ==================== 公共 UI 片段 ====================

--[[页面顶部标题区（返回文字时间标签，用于自刷新）
]]
function M.header(parent, title, subtitle, opts)
    opts = opts or {}
    local w = conf.W
    -- 顶部渐变条
    theme.gradient(parent, 0, 0, w, 64, C.bg2, C.bg1, 8)
    theme.hline(parent, 0, 63, w, C.line)

    -- 左侧品牌标记
    local mark = theme.box(parent, 26, 20, 4, 24, C.cyan, 2)
    mark = mark
    theme.label(parent, 42, 16, 420, 34, title, 24, C.ink)
    if subtitle then
        theme.label(parent, 44, 42, 520, 18, subtitle, 13, C.ink3)
    end

    -- 右侧时间
    local tl = theme.label(parent, w - 430, 12, 400, 26, "", 20, C.cyan,
        airui.TEXT_ALIGN_RIGHT)
    local sl = theme.label(parent, w - 430, 38, 400, 18, "", 13, C.ink3,
        airui.TEXT_ALIGN_RIGHT)
    return tl, sl
end

-- 时间文本（供各页面 tick 更新）
function M.clock_text()
    local s = M.state.t
    local tz = conf.site.tz
    return astro.fmt_hms(s, tz), "LST " .. astro.fmt_lst(M.lst()) ..
        "   地方时 UTC" .. (tz >= 0 and "+" or "") .. tz
end

-- 左侧导航条（只用中文文字，避免图标字体缺字）
local NAV = {
    { key = "sky",      text = "星图", sub = "SKY" },
    { key = "session",  text = "计划", sub = "PLAN" },
    { key = "settings", text = "设置", sub = "SET" },
}

function M.nav(parent, active)
    local x, y = 0, 64
    local w = 92
    local h = conf.H - 64
    theme.box(parent, x, y, w, h, C.bg3, 0)
    theme.box(parent, w, y, 1, h, C.line, 0)

    local items = {}
    for i, item in ipairs(NAV) do
        local iy = y + 26 + (i - 1) * 84
        local on = (item.key == active)
        local bg = airui.container({
            parent = parent, x = x + 12, y = iy, w = w - 24, h = 68,
            color = theme.tint(on and C.panel3 or C.bg3), color_opacity = 255,
            radius = 14, border_width = on and 1 or 0,
            border_color = theme.tint(C.line2),
        })
        if on then
            theme.box(bg, 0, 20, 3, 28, C.cyan, 2)
        end
        local tx = theme.label(bg, 0, 16, w - 24, 24, item.text, 18,
            on and C.ink or C.ink3, airui.TEXT_ALIGN_CENTER)
        local sb = theme.label(bg, 0, 42, w - 24, 14, item.sub, 10,
            on and C.cyan or C.ink3, airui.TEXT_ALIGN_CENTER)
        items[i] = { box = bg, text = tx, sub = sb }
        local key = item.key
        bg:set_on_click(function()
            if M.state.page ~= key then M.go(key) end
        end)
    end
    return items
end

-- 带框的数值卡（返回 label 供刷新）
function M.stat_card(parent, x, y, w, h, caption, value, unit, color)
    local card = theme.card(parent, x, y, w, h, C.panel, 12)
    theme.label(card, 14, 10, w - 28, 16, caption, 12, C.ink3)
    local v = theme.label(card, 14, h - 42, w - 28, 32, value, 28, color or C.ink)
    if unit then
        theme.label(card, 14, h - 46, w - 28, 18, "", 12, C.ink3)
    end
    return v, card
end

-- ==================== 生命周期 ====================

function M.start(root)
    M.root = root
    M.state.t = make_start_time()
    M.state.last_tick = mcu and mcu.ticks and mcu.ticks() or 0

    build_toast()

    -- 全局触摸分发（只订阅一次，页面各自处理）
    if airui.touch_subscribe then
        airui.touch_subscribe(function(state, x, y)
            if M.page and M.page.touch then
                pcall(M.page.touch, state, x, y)
            end
        end)
    end

    M.go("sky")

    -- 全局时钟：驱动仿真时间，并让当前页面重绘动态内容
    sys.timerLoopStart(function()
        local dt = 0.2 * M.speed()
        if not M.state.paused then
            M.state.t = M.state.t + dt
        end
        if M.page and M.page.tick then
            local ok, err = pcall(M.page.tick, 0.2)
            if not ok then
                log.error("app", "tick error", tostring(err))
            end
        end
    end, 200)
end

return M
