--[[
@module  ui
@summary 界面装配：顶栏导航 + 5 个页面切换 + 1Hz 数据刷新 + 自动轮播 + 报警徽标
@version 1.0
@date    2026.11.10
]]
local conf  = require("conf")
local theme = require("theme")
local store = require("store")
local model = require("model")

local C = theme.C
local T = theme
local M = {}

local v = { tabs = {}, items = {}, cur = 1, idle = 0, flush_cnt = 0 }

-- 注意：这里必须用字面量 require！
-- Luatools 打包/编译脚本时会做静态依赖扫描，只收集 require("xxx") 字面量形式引用的文件。
-- 若写成 require(pg.mod) 这种动态形式，页面文件不会被下载进 luadb，
-- 运行时会报 module 'ui_overview' not found。
local ui_overview = require("ui_overview")
local ui_process  = require("ui_process")
local ui_mold     = require("ui_mold")
local ui_alarm    = require("ui_alarm")
local ui_settings = require("ui_settings")

local PAGES = {
    { key = "overview", mod = ui_overview },
    { key = "process",  mod = ui_process },
    { key = "mold",     mod = ui_mold },
    { key = "alarm",    mod = ui_alarm },
    { key = "settings", mod = ui_settings },
}

-- ==================== 页面切换 ====================
function M.show(i)
    if i < 1 or i > #PAGES then return end
    v.cur = i
    v.idle = 0
    for k, p in ipairs(M.pages) do
        if p.root then p.root:set_hidden(k ~= i) end
    end
    for k, btn in ipairs(v.tabs) do
        local on = (k == i)
        pcall(btn.set_style, btn, {
            bg_color = on and C.panel3 or C.panel, bg_opa = 255,
            text_color = on and C.cyan or C.ink2, radius = 8,
            border_color = on and C.panel3 or C.panel, border_width = 0,
            pressed_bg_color = C.line2, pressed_text_color = C.white,
        })
        if v.items[k] then v.items[k]:set_hidden(not on) end
    end
    local p = M.pages[i]
    if p and p.refresh then pcall(p.refresh) end
end

function M.current() return v.cur end

-- ==================== 顶栏 ====================
local function build_top(root)
    local top = airui.container({
        parent = root, x = 0, y = 0, w = conf.W, h = conf.top_h,
        color = C.panel, radius = 0,
    })
    T.hline(top, 0, conf.top_h - 1, conf.W, C.line)

    -- 品牌
    T.dot(top, 20, 26, 10, C.cyan)
    T.label(top, 38, 16, 220, 26, conf.name, 18, C.ink)
    T.label(top, 38, 42, 240, 18, conf.shop, 11, C.ink3)

    -- 导航
    local n = #PAGES
    local bw, gap, x0 = 100, 6, 260
    for i, pg in ipairs(PAGES) do
        local x = x0 + (i - 1) * (bw + gap)
        v.tabs[i] = T.button(top, x, 16, bw, 40, conf.tabs[i], 15,
            C.panel, C.ink2, function() M.show(i) end, 8)
        v.items[i] = T.box(top, x + 24, 58, bw - 48, 3, C.cyan, 2)
        v.items[i]:set_hidden(true)
    end

    -- 报警徽标
    v.badge_box = airui.container({
        parent = top, x = 792, y = 20, w = 84, h = 34,
        color = C.panel2, radius = 8, border_color = C.line2, border_width = 1,
        on_click = function() M.show(4) end,
    })
    T.dot(v.badge_box, 12, 13, 8, C.red)
    v.badge_lb = T.label(v.badge_box, 26, 6, 50, 22, "0", 14, C.ink)

    -- 时钟与班次
    v.clock = T.label(top, 886, 8, 120, 26, os.date("%H:%M:%S"), 18, C.ink,
        T.TEXT_RIGHT)
    v.shift = T.label(top, 886, 36, 120, 18, "", 11, C.ink3, T.TEXT_RIGHT)
    return top
end

local function update_top()
    v.clock:set_text(os.date("%H:%M:%S"))
    local s = store.settings()
    v.shift:set_text(conf.shifts[s.shift or 1])
    local n = store.unacked_count()
    v.badge_lb:set_text(tostring(n))
    v.badge_lb:set_color(n > 0 and C.red or C.ink3)
    pcall(v.badge_box.set_color, v.badge_box,
        n > 0 and T.dim(C.red, 0.22) or C.panel2)
end

-- ==================== 主循环 ====================
local function tick()
    model.tick(1)

    v.flush_cnt = v.flush_cnt + 1
    if v.flush_cnt >= 60 then
        v.flush_cnt = 0
        store.flush()
        model.flush_molds()
    end

    update_top()
    local p = M.pages[v.cur]
    if p and p.refresh then pcall(p.refresh) end

    -- 无操作 30s 自动轮播
    if (store.settings().rotate or 1) ~= 0 then
        v.idle = v.idle + 1
        if v.idle >= 30 then
            v.idle = 0
            M.show(v.cur % #PAGES + 1)
        end
    end
end

function M.start(root)
    store.init()
    model.init()

    -- 页面（全屏透明容器，先建）
    M.pages = {}
    for i, pg in ipairs(PAGES) do
        local ok, err = pcall(pg.mod.build, root)
        if not ok then
            log.error("ui", "页面构建失败", pg.key, tostring(err))
        end
        M.pages[i] = pg.mod
    end

    -- 顶栏最后建，保证在页面之上接收点击
    build_top(root)

    -- 跨页回调
    M.pages[1].on_pick = function(idx)
        model.select(idx)
        M.show(2)
    end
    M.pages[5].on_backlight = function(val)
        pcall(function()
            pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, val)
            pwm.start(conf.backlight.pwm_ch)
        end)
    end

    M.show(1)
    update_top()

    sys.timerLoopStart(function()
        local ok, err = pcall(tick)
        if not ok then log.error("ui", "tick", tostring(err)) end
    end, conf.tick_ms)

    log.info("ui", "界面启动完成")
end

return M
