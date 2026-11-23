--[[
@module  app
@summary 页面路由 / 顶部栏 / 全局采样循环 / 轻提示
@version 1.0
@date    2026.11.12
]]
local sys   = require "sys"
local theme = require "theme"
local art   = require "art"
local sim   = require "sim"
local conf  = require "conf"

local C = theme.C
local SZ = theme.SZ
local A_LEFT, A_CENTER, A_RIGHT = theme.align_left(), theme.align_center(), theme.align_right()

local M = {}

local ROUTES = {
    { key = "overview", title = "总览",   module = "ui_overview" },
    { key = "shot",     title = "放电",   module = "ui_shot" },
    { key = "magnetic", title = "磁约束", module = "ui_magnetic" },
    { key = "cryo",     title = "低温真空", module = "ui_cryo" },
    { key = "settings", title = "系统",   module = "ui_settings" },
}

-- PC 模拟器按 require 字面量做依赖裁剪，页面懒加载必须在这里登记
local PAGE_LOADERS = {
    ui_overview = function() return require("ui_overview") end,
    ui_shot     = function() return require("ui_shot") end,
    ui_magnetic = function() return require("ui_magnetic") end,
    ui_cryo     = function() return require("ui_cryo") end,
    ui_settings = function() return require("ui_settings") end,
}

local TOP_H = 56
local FRAME_MS = conf.anim.frame_ms
local FRAME_PER_SLOW = 4
local FRAME_PER_SEC = 9

local state = {
    page = nil,
    index = 1,
    frame = 0,
    tabs = {},
    toast_box = nil,
    toast_label = nil,
    toast_until = 0,
    started = false,
}

local function safe(fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        log.warn("app", "回调异常", tostring(err))
    end
end

-- ===================== 轻提示 =====================
function M.toast(text, level)
    if not state.toast_box then return end
    local color = theme.state_color(level or "ok")
    pcall(function()
        state.toast_box:set_color(C.panel2)
        state.toast_box:set_border_color(color, 1)
        state.toast_label:set_text(text or "")
        state.toast_label:set_color(C.ink)
        state.toast_box:set_hidden(false)
    end)
    state.toast_until = state.frame + 30
end

-- ===================== 顶部栏 =====================
local function build_topbar(root)
    local bar = theme.box(root, 0, 0, conf.W, TOP_H, C.bg0, 0)

    art.icon(bar, "torus", 18, 14, 28, C.plasma)
    theme.label(bar, 54, 7, 200, 24, conf.brand, SZ.l, C.ink)
    theme.label(bar, 54, 31, 260, 16, conf.name .. "，聚变放电控制", SZ.xs, C.ink3)

    local tab_w, tab_h, gap = 92, 30, 6
    local x = 322
    local nav = {}
    for i, r in ipairs(ROUTES) do
        local tx = x + (i - 1) * (tab_w + gap)
        local box = theme.box(bar, tx, 13, tab_w, tab_h, C.panel2, 8)
        local lb = theme.label(bar, tx, 13, tab_w, tab_h, r.title, SZ.s, C.ink2, A_CENTER)
        box:set_on_click(function()
            M.open(i)
        end)
        nav[i] = { box = box, label = lb }
    end
    state.tabs = nav

    local clock = theme.label(bar, 886, 3, 122, 30, "08:42", SZ.xl, C.ink, A_RIGHT)
    local phase = theme.label(bar, 806, 33, 202, 16, "", SZ.xs, C.ink3, A_RIGHT)

    theme.hline(bar, 0, TOP_H - 1, conf.W, C.line)

    return { clock = clock, phase = phase }
end

-- 轻提示必须最后创建：LVGL 后创建的对象在上层，
-- 若在 content 之前创建，会被内容区整块盖住。
local function build_toast(root)
    local box = theme.box(root, 292, 546, 440, 42, C.panel2, 21)
    box:set_border_color(C.line2, 1)
    box:set_hidden(true)
    local lb = theme.label(root, 292, 546, 440, 42, "", SZ.s, C.ink, A_CENTER)
    state.toast_box = box
    state.toast_label = lb
end

local top_cache = {}
local function update_topbar(top)
    local s = sim.summary()
    local p = sim.phase()
    local ck = sim.clock()
    if top_cache.clock ~= ck then
        top_cache.clock = ck
        pcall(function() top.clock:set_text(ck) end)
    end
    local pt = string.format("%d 炮，%s", theme.n(s.shot), p.name)
    if top_cache.phase ~= pt then
        top_cache.phase = pt
        pcall(function() top.phase:set_text(pt) end)
    end
    local col = (p.key == "cooldown") and C.ink3 or C.ink2
    if top_cache.col ~= col then
        top_cache.col = col
        pcall(function() top.phase:set_color(col) end)
    end
end

local function set_active_tab(idx)
    for i, t in ipairs(state.tabs) do
        local active = (i == idx)
        pcall(function()
            t.box:set_color(active and C.plasma or C.panel2)
            t.label:set_color(active and C.bg0 or C.ink2)
        end)
    end
end

-- ===================== 路由 =====================
function M.open(idx, silent)
    if idx < 1 or idx > #ROUTES then return end
    local route = ROUTES[idx]
    if state.page and state.index == idx then
        set_active_tab(idx)
        return
    end

    if state.page then
        local old = state.page
        state.page = nil
        pcall(function()
            if old.destroy then old.destroy() end
        end)
        pcall(function()
            if old.root and not old.root:is_destroyed() then old.root:destroy() end
        end)
    end

    state.index = idx
    set_active_tab(idx)

    local loader = PAGE_LOADERS[route.module]
    local ok, mod = false, "未登记的页面"
    if loader then ok, mod = pcall(loader) end
    if not ok or type(mod) ~= "table" then
        log.warn("app", "页面加载失败", route.module, tostring(mod))
        theme.label(M.content, 0, 200, conf.W, 40, "页面加载失败：" .. route.module, SZ.l, C.red, A_CENTER)
        return
    end

    local root = airui.container({
        parent = M.content, x = 0, y = 0, w = conf.W, h = conf.H - TOP_H,
        color = C.bg1, color_opacity = 0, radius = 0,
    })

    local ok2, page = pcall(mod.create, root)
    if not ok2 or not page then
        log.warn("app", "页面构建失败", route.title, tostring(page))
        theme.label(root, 0, 200, conf.W, 40, "页面构建失败：" .. route.title, SZ.l, C.red, A_CENTER)
        return
    end
    page.root = root
    page.alive = true
    state.page = page

    safe(page.refresh)
    safe(page.slow)
    if not silent then M.toast(route.title .. "，" .. sim.clock(), "ok") end
end

function M.go(key)
    for i, r in ipairs(ROUTES) do
        if r.key == key then
            M.open(i)
            return
        end
    end
end

function M.current() return state.page end
function M.routes() return ROUTES end

-- ===================== 帧耗时探针 =====================
-- 只在 conf.debug.profile 打开时生效，关闭时零开销。
-- 用途：定位“soc_send_event_to_task no free static event”这类事件池告警——
-- 该告警说明 luatos 任务消费慢于 110 ms 的定时投递，需要知道是哪一段慢。
local prof = { on = false, sum = 0, n = 0, max = 0, rmax = 0, warn_at = -999 }
if conf.debug and conf.debug.profile then
    local ok, f = pcall(function() return mcu and mcu.ticks end)
    if ok and type(f) == "function" then
        prof.on = true
        prof.fn = f
        log.info("prof", "帧耗时探针已启用（conf.debug.profile）")
    else
        log.warn("prof", "固件没有 mcu.ticks，帧耗时探针未启用")
    end
end

-- ===================== 启动 =====================
function M.start(parent)
    if state.started then return end
    state.started = true

    local root = theme.backdrop(parent)
    local top = build_topbar(root)

    M.content = airui.container({
        parent = root, x = 0, y = TOP_H, w = conf.W, h = conf.H - TOP_H,
        color = C.bg1, color_opacity = 0, radius = 0,
    })

    build_toast(root)

    update_topbar(top)
    M.open(1, true)

    sys.timerLoopStart(function()
        local t0 = prof.on and prof.fn() or 0
        local tr = 0
        state.frame = state.frame + 1
        local page = state.page

        if state.frame % FRAME_PER_SEC == 0 then
            local r0 = prof.on and prof.fn() or 0
            local ev = sim.tick()
            update_topbar(top)
            if page then safe(page.refresh) end
            if prof.on then tr = prof.fn() - r0 end
            if ev and ev.level ~= "ok" then
                M.toast(ev.text, ev.level)
            end
        end

        if state.frame % FRAME_PER_SLOW == 0 then
            if page then safe(page.slow) end
        end

        if page then safe(page.frame, state.frame) end

        if state.toast_until > 0 and state.frame > state.toast_until then
            state.toast_until = 0
            pcall(function() state.toast_box:set_hidden(true) end)
        end

        if prof.on then
            local dt = prof.fn() - t0
            prof.sum = prof.sum + dt
            prof.n = prof.n + 1
            if dt > prof.max then prof.max = dt end
            if tr > prof.rmax then prof.rmax = tr end

            -- 单帧超过 90 ms 就告警，最多 5 秒一条，避免探针本身刷屏
            if dt > 90 and state.frame - prof.warn_at >= 45 then
                prof.warn_at = state.frame
                log.warn("prof", string.format("帧耗时 %d ms（refresh %d ms）", dt, tr))
            end

            -- 每 10 秒汇总一次：avg 看常态，max 看尖峰
            if state.frame % 90 == 0 then
                log.info("prof", string.format("10s 帧耗时 avg %.1f ms / max %d ms / refresh max %d ms",
                    prof.sum / math.max(1, prof.n), prof.max, prof.rmax))
                prof.sum, prof.n, prof.max, prof.rmax = 0, 0, 0, 0
            end
        end
    end, FRAME_MS)
end

return M
