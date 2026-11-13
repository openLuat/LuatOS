--[[
@module  ui_settings
@summary 系统页：背光 / 演示模型 / 系统信息 / 设备体检 / 装置档案
@version 1.0
@date    2026.11.12
]]
local theme = require "theme"
local art   = require "art"
local sim   = require "sim"
local conf  = require "conf"

local C = theme.C
local SZ = theme.SZ
local A_LEFT, A_CENTER, A_RIGHT = theme.align_left(), theme.align_center(), theme.align_right()

local M = {}

local L = {
    display = { x = 14,  y = 10,  w = 320, h = 170 },
    demo    = { x = 346, y = 10,  w = 320, h = 170 },
    system  = { x = 678, y = 10,  w = 332, h = 170 },
    health  = { x = 14,  y = 192, w = 996, h = 206 },
    profile = { x = 14,  y = 410, w = 996, h = 124 },
}

local function mk_slider(parent, x, y, w, h, min, max, value, color, cb)
    return theme.slider({
        parent = parent, x = x, y = y, w = w, h = h,
        min = min, max = max, value = value,
        style = {
            bg_color = C.panel3, bg_opa = 255, border_width = 0,
            indicator_color = color, indicator_opa = 255,
            knob_color = color, knob_opa = 255,
            knob_border_color = color, knob_border_width = 0,
            radius = 99, pad = 3,
        },
        on_change = cb,
    })
end

local function fmt_uptime(sec)
    sec = math.max(0, theme.n(sec))
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
end

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 显示 ====================
    local dc = theme.card(root, L.display.x, L.display.y, L.display.w, L.display.h, { radius = 14 })
    theme.label(dc, 14, 8, 140, 18, "显示与背光", SZ.s, C.ink)
    local bri_val = theme.label(dc, 220, 8, 84, 18, "82%", SZ.xs, C.ink2, A_RIGHT)

    local function set_brightness(v)
        v = theme.clamp(theme.n(v), 10, 100)
        pcall(function()
            pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, v)
            pwm.start(conf.backlight.pwm_ch)
        end)
        bri_val:set_text(string.format("%d%%", v))
    end

    local bar = mk_slider(dc, 14, 34, 292, 26, 10, 100, conf.backlight.default, C.gold, function(self)
        set_brightness(self:get_value())
    end)

    theme.label(dc, 14, 64, 200, 14, "PWM3（GPIO13），1000 Hz", SZ.xs, C.ink3)

    local PRE = {
        { name = "夜间", v = 35 },
        { name = "标准", v = 82 },
        { name = "明亮", v = 100 },
    }
    for i, p in ipairs(PRE) do
        theme.ghost(dc, 14 + (i - 1) * 100, 88, 92, 28, p.name, {
            size = SZ.xs,
            on_click = function()
                set_brightness(p.v)
                if bar then theme.setbar(bar, p.v, true) end
            end,
        })
    end
    theme.label(dc, 14, 126, 292, 14, "触摸屏亮度直接写 PWM 占空比，不经过 UI 缓存", SZ.xs, C.ink3)

    -- ==================== 演示模型 ====================
    local mc = theme.card(root, L.demo.x, L.demo.y, L.demo.w, L.demo.h, { radius = 14 })
    theme.label(mc, 14, 8, 140, 18, "演示模型", SZ.s, C.ink)
    local mstate = theme.label(mc, 200, 8, 104, 18, "运行中", SZ.xs, C.green, A_RIGHT)

    local cells = {}
    local CELL = {
        { cap = "采样次数", key = "tick" },
        { cap = "仿真时长", key = "uptime" },
        { cap = "事件条数", key = "events" },
    }
    for i, d in ipairs(CELL) do
        local x = 14 + (i - 1) * 98
        theme.label(mc, x, 36, 94, 14, d.cap, SZ.xs, C.ink3)
        cells[i] = theme.label(mc, x, 52, 94, 20, "--", SZ.m, C.ink)
    end
    page.cells = cells

    local btn_pause = theme.ghost(mc, 14, 84, 140, 28, "暂停模型", {
        size = SZ.xs,
        on_click = function()
            sim.pause(not sim.is_paused())
            page.refresh()
        end,
    })
    local btn_reset = theme.ghost(mc, 164, 84, 140, 28, "重置数据", {
        size = SZ.xs,
        fg = C.gold,
        border = theme.mix(C.gold, C.panel, 0.5),
        on_click = function()
            sim.reset()
            page.refresh()
        end,
    })
    page.btn_pause = btn_pause

    theme.label(mc, 14, 122, 292, 14, "1 Hz 采样，每拍推进 30 s 装置时间", SZ.xs, C.ink3)
    page.mstate = mstate

    -- ==================== 系统信息 ====================
    local sc = theme.card(root, L.system.x, L.system.y, L.system.w, L.system.h, { radius = 14 })
    theme.label(sc, 14, 8, 140, 18, "系统信息", SZ.s, C.ink)
    local mem = theme.label(sc, 220, 8, 96, 18, "", SZ.xs, C.ink3, A_RIGHT)

    local INFO = {
        { k = "分辨率", v = string.format("%d × %d", conf.W, conf.H) },
        { k = "显示驱动", v = "RGB-1024x600-10i" },
        { k = "触摸", v = "GT911，I2C1" },
        { k = "字库", v = "hzfont × 6 档" },
        { k = "固件", v = "LuatOS，helios1 " .. conf.version },
        { k = "运行时长", v = "--" },
    }
    local infos = {}
    for i, it in ipairs(INFO) do
        local y = 32 + (i - 1) * 22
        theme.label(sc, 14, y, 90, 14, it.k, SZ.xs, C.ink3)
        infos[i] = theme.label(sc, 108, y, 210, 14, it.v, SZ.xs, C.ink2, A_RIGHT)
    end
    page.infos = infos
    page.mem = mem

    -- ==================== 设备体检 ====================
    local hc = theme.card(root, L.health.x, L.health.y, L.health.w, L.health.h, { radius = 14 })
    theme.label(hc, 14, 8, 200, 18, "设备体检", SZ.s, C.ink)
    local hsum = theme.label(hc, 760, 8, 220, 18, "", SZ.xs, C.ink3, A_RIGHT)

    local hrows = {}
    for i = 1, #conf.health do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 14 + col * 492
        local y = 36 + row * 52
        local dot = theme.box(hc, x, y + 4, 6, 6, C.green, 3)
        local name = theme.label(hc, x + 14, y, 240, 16, conf.health[i].name, SZ.s, C.ink)
        local val = theme.label(hc, x + 220, y, 120, 16, "--", SZ.s, C.ink, A_RIGHT)
        local range = theme.label(hc, x + 346, y + 2, 132, 14, "", SZ.xs, C.ink3, A_RIGHT)
        local bar = theme.bar(hc, x + 14, y + 26, 464, 4, 0, C.green, C.panel3)
        hrows[i] = { idx = i, dot = dot, name = name, val = val, range = range, bar = bar }
    end
    page.hrows = hrows
    page.hsum = hsum

    -- ==================== 装置档案 ====================
    local pc = theme.card(root, L.profile.x, L.profile.y, L.profile.w, L.profile.h, { radius = 14 })
    theme.label(pc, 14, 8, 200, 18, "装置档案", SZ.s, C.ink)
    local pv = theme.label(pc, 700, 8, 280, 18, conf.machine.campaign, SZ.xs, C.ink3, A_RIGHT)

    local FACTS = {
        { "装置", conf.machine.name },
        { "地点", conf.machine.site },
        { "大半径 R0", string.format("%.2f m", conf.machine.R0) },
        { "小半径 a", string.format("%.2f m", conf.machine.a) },
        { "环向场 Bt", string.format("%.2f T", conf.machine.Bt) },
        { "等离子体体积", string.format("%.1f m3", conf.machine.volume) },
        { "第一壁", conf.machine.wall },
        { "投运时间", conf.machine.commission },
        { "累计放电", string.format("%d 炮", theme.n(sim.summary().shot)) },
    }
    local facts = {}
    for i, f in ipairs(FACTS) do
        local col = math.floor((i - 1) / 3)
        local row = (i - 1) % 3
        local x = 14 + col * 330
        local y = 36 + row * 28
        theme.label(pc, x, y, 100, 14, f[1], SZ.xs, C.ink3)
        facts[i] = theme.label(pc, x + 96, y, 210, 14, f[2], SZ.xs, C.ink2)
    end
    page.facts = facts
    page.pv = pv

    -- ==================== 刷新 ====================
    local function refresh()
        if not page.alive then return end
        local s = sim.summary()

        page.cells[1]:set_text(tostring(s.tick))
        page.cells[2]:set_text(fmt_uptime(s.uptime))
        page.cells[3]:set_text(tostring(#s.events))

        page.mstate:set_text(s.paused and "已暂停" or "运行中")
        page.mstate:set_color(s.paused and C.gold or C.green)
        page.btn_pause:set_text(s.paused and "恢复模型" or "暂停模型")

        page.infos[6]:set_text(fmt_uptime(s.uptime))
        page.mem:set_text(string.format("Lua %.0f KB", collectgarbage("count")))
        page.pv:set_text(conf.machine.campaign)

        local bad = 0
        for i, r in ipairs(page.hrows) do
            local h = sim.health(conf.health[i].key)
            local d = h.def
            local numfmt = d.dec > 0 and ("%." .. d.dec .. "f") or "%.0f"
            r.val:set_text(string.format(numfmt, h.value))
            r.val:set_color(h.level == "danger" and C.red or (h.level == "warn" and C.gold or C.ink))
            r.dot:set_color(theme.state_color(h.level))
            r.range:set_text(string.format("%s ~ %s %s",
                d.lo and string.format(numfmt, d.lo) or "-",
                d.hi and string.format(numfmt, d.hi) or "-", d.unit))
            local pct = theme.clamp((h.value - d.lo) / math.max(0.001, d.hi - d.lo) * 100, 0, 100)
            if r.bar then
                theme.setbar(r.bar, pct)
                r.bar:set_indicator_color(h.level == "danger" and C.red or (h.level == "warn" and C.gold or C.green))
            end
            if h.level ~= "ok" then bad = bad + 1 end
        end
        page.hsum:set_text(bad == 0 and "6 项全部正常" or string.format("%d 项需关注", bad))
        page.hsum:set_color(bad == 0 and C.green or C.gold)

        page.facts[9]:set_text(string.format("%d 炮", theme.n(s.shot)))
    end
    page.refresh = refresh

    local function slow() end
    page.slow = slow
    local function frame() end
    page.frame = frame

    function page.destroy()
        page.alive = false
    end

    refresh()
    return page
end

return M
