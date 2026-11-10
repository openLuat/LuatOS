--[[
@module  app
@summary 页面路由 / 顶部栏 / 全局采样循环 / 轻提示
@version 1.0
@date    2026.11.06
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
    { key = "lift",     title = "运营总览", module = "ui_lift" },
    { key = "line",     title = "索道线路", module = "ui_line" },
    { key = "snow",     title = "雪况造雪", module = "ui_snow" },
    { key = "settings", title = "系统设置", module = "ui_settings" },
}

-- PC 模拟器按 require 的字面量做依赖裁剪，只打包 main.lua 静态可达的文件。
-- 页面是按字符串懒加载的，必须在这里以字面量登记，否则 ui_*.lua 会被当成
-- 无用文件剔除，运行时报 module 'ui_lift' not found。
local PAGE_LOADERS = {
    ui_lift     = function() return require("ui_lift") end,
    ui_line     = function() return require("ui_line") end,
    ui_snow     = function() return require("ui_snow") end,
    ui_settings = function() return require("ui_settings") end,
}

local TOP_H = 56
local FRAME_MS = conf.anim.frame_ms
local FRAME_PER_SLOW = 4          -- ≈440ms
local FRAME_PER_SEC = 9           -- ≈990ms

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

-- ===================== 错误兜底 =====================
-- 页面回调全部 pcall 保护，避免单点异常拖垮主循环；出错时打日志便于定位
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

    -- 品牌
    art.icon(bar, "peak", 18, 15, 26, C.ice)
    theme.label(bar, 52, 9, 200, 24, conf.brand, SZ.l, C.ink)
    theme.label(bar, 52, 32, 240, 16, "云脊雪场 · 索道运营中枢", SZ.xs, C.ink3)
    theme.hline(bar, 16, TOP_H - 1, conf.W - 32, C.line)

    -- 导航
    local tab_w, tab_h, gap = 104, 30, 8
    local x = 306
    local nav = {}
    for i, r in ipairs(ROUTES) do
        local tx = x + (i - 1) * (tab_w + gap)
        local box = theme.box(bar, tx, 13, tab_w, tab_h, C.panel2, 8)
        local lb = theme.label(bar, tx, 13, tab_w, tab_h, r.title, SZ.s, C.ink2, A_CENTER)
        local item = { box = box, label = lb }
        box:set_on_click(function()
            M.open(i)
        end)
        nav[i] = item
    end
    state.tabs = nav

    -- 时钟
    local clock = theme.label(bar, 762, 6, 110, 28, "08:00", SZ.xl, C.ink, A_RIGHT)
    local phase = theme.label(bar, 762, 34, 110, 16, "上午", SZ.xs, C.ink3, A_RIGHT)

    -- 天气
    local wicon = art.icon(bar, "cloud", 878, 8, 20, C.snow)
    local temp = theme.label(bar, 900, 6, 106, 26, "-6.4℃", SZ.l, C.snow, A_RIGHT)
    local wsub = theme.label(bar, 830, 34, 176, 16, "风速 4.2 m/s · 能见度 12.0 km", SZ.xs, C.ink3, A_RIGHT)

    -- 轻提示（浮在内容区底部）
    local box = theme.box(root, 292, 546, 440, 42, C.panel2, 21)
    box:set_border_color(C.line2, 1)
    box:set_hidden(true)
    local lb = theme.label(root, 292, 546, 440, 42, "", SZ.s, C.ink, A_CENTER)
    state.toast_box = box
    state.toast_label = lb

    return {
        clock = clock,
        phase = phase,
        temp = temp,
        wsub = wsub,
        wicon = wicon,
    }
end

local function update_topbar(top)
    local s = sim.summary()
    pcall(function()
        top.clock:set_text(s.clock)
        top.phase:set_text(s.phase .. " · " .. s.cond)
        top.temp:set_text(string.format("%.1f℃", s.temp))
        top.wsub:set_text(string.format("风速 %.1f m/s · 能见度 %.1f km", s.wind, s.vis))
    end)
end

local function set_active_tab(idx)
    for i, t in ipairs(state.tabs) do
        local active = (i == idx)
        pcall(function()
            t.box:set_color(active and C.ice or C.panel2)
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
        color = C.bg1, radius = 0,
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
    if not silent then M.toast(route.title .. " · " .. sim.clock(), "ok") end
end

function M.current()
    return state.page
end

-- ===================== 启动 =====================
function M.start(parent)
    if state.started then return end
    state.started = true

    local root = theme.backdrop(parent)
    local top = build_topbar(root)

    M.content = airui.container({
        parent = root, x = 0, y = TOP_H, w = conf.W, h = conf.H - TOP_H,
        color = C.bg1, radius = 0,
    })

    update_topbar(top)
    M.open(1, true)

    sys.timerLoopStart(function()
        state.frame = state.frame + 1
        local page = state.page

        if state.frame % FRAME_PER_SEC == 0 then
            local ev = sim.tick()
            update_topbar(top)
            if page then safe(page.refresh) end
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
    end, FRAME_MS)
end

return M
