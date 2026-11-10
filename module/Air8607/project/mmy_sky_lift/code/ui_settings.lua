--[[
@module  ui_settings
@summary 设置页：背光调节、演示模型控制、机械体检、系统信息、站点档案
@version 1.0
@date    2026.11.06
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
    light  = { x = 16,  y = 8,   w = 560, h = 176 },
    demo   = { x = 16,  y = 192, w = 560, h = 176 },
    health = { x = 16,  y = 376, w = 560, h = 162 },
    sysinfo = { x = 592, y = 8,   w = 416, h = 254 },
    site    = { x = 592, y = 270, w = 416, h = 268 },
}

local function toast(text, level)
    local ok, app = pcall(require, "app")
    if ok and app and app.toast then app.toast(text, level) end
end

-- 单项体检等级
local function level_of(h, def)
    if (def.dhi and h.value > def.dhi) or (def.dlo and h.value < def.dlo) then return "danger" end
    if h.value > def.hi or h.value < def.lo then return "warn" end
    return "ok"
end

local function uptime_text(minutes)
    if minutes < 60 then return string.format("%d 分钟", minutes) end
    return string.format("%d 小时 %d 分", math.floor(minutes / 60), minutes % 60)
end

local function mem_text()
    if not rtos or not rtos.meminfo then return "--" end
    local ok, total, used = pcall(rtos.meminfo, "sys")
    if ok and total and used and total > 0 then
        return string.format("%.0f / %.0f KB", (total - used) / 1024, total / 1024)
    end
    return "--"
end

local function fw_text()
    if rtos and rtos.version then
        local ok, v = pcall(rtos.version)
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    return "LuatOS"
end

function M.create(root)
    local page = { root = root, alive = true, bright = conf.backlight.default }

    -- ==================== 显示与背光 ====================
    local lc = theme.card(root, L.light.x, L.light.y, L.light.w, L.light.h, { radius = 14 })
    theme.label(lc, 16, 8, 220, 20, "显示与背光", SZ.m, C.ink)
    theme.chip(lc, 432, 10, 112, 20, "PWM3 · 1 kHz", C.ink2, C.panel2, SZ.xs)

    local bright_val = theme.label(lc, 16, 32, 120, 44, "80", SZ.xl, C.ice)
    theme.label(lc, 92, 52, 24, 16, "%", SZ.s, C.ink3)
    local bright_hint = theme.label(lc, 140, 44, 404, 16, "", SZ.xs, C.ink3, A_RIGHT)
    local bright_sub = theme.label(lc, 140, 62, 404, 16, "", SZ.xs, C.ink3, A_RIGHT)

    local function apply_bright(v)
        v = math.max(conf.backlight.min, math.min(100, math.floor(v + 0.5)))
        page.bright = v
        if pwm and pwm.setup and pwm.start then
            pcall(function()
                pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, v)
                pwm.start(conf.backlight.pwm_ch)
            end)
        end
        return v
    end

    local slider = theme.slider({
        parent = lc, x = 16, y = 84, w = 528, h = 26,
        min = conf.backlight.min, max = 100, value = conf.backlight.default,
        on_change = function(self)
            local v = conf.backlight.default
            pcall(function() v = self:get_value() end)
            apply_bright(v)
            page.refresh()
        end,
        style = {
            bg_color = C.panel3, bg_opa = 255,
            border_color = C.line, border_width = 0, radius = 8, pad = 3,
            indicator_color = C.ice, knob_color = C.snow, knob_border_color = C.ice,
            knob_border_width = 2,
        },
    })
    page.slider = slider

    theme.label(lc, 16, 114, 60, 14, "10", SZ.xs, C.ink3)
    theme.label(lc, 250, 114, 60, 14, "55", SZ.xs, C.ink3, A_CENTER)
    theme.label(lc, 484, 114, 60, 14, "100", SZ.xs, C.ink3, A_RIGHT)

    local preset_def = {
        { text = "夜间 30", v = 30 },
        { text = "标准 60", v = 60 },
        { text = "明亮 90", v = 90 },
    }
    for i, p in ipairs(preset_def) do
        theme.ghost(lc, 16 + (i - 1) * 179, 134, 170, 30, p.text, {
            size = SZ.xs,
            on_click = function()
                apply_bright(p.v)
                if page.slider then pcall(function() page.slider:set_value(p.v) end) end
                page.refresh()
            end,
        })
    end
    page.bright_val = bright_val
    page.bright_hint = bright_hint
    page.bright_sub = bright_sub

    -- ==================== 演示模型 ====================
    local dc = theme.card(root, L.demo.x, L.demo.y, L.demo.w, L.demo.h, { radius = 14 })
    theme.label(dc, 16, 8, 220, 20, "演示模型", SZ.m, C.ink)
    local d_chip = theme.chip(dc, 432, 10, 112, 20, "运行中", C.bg0, C.green, SZ.xs)
    theme.label(dc, 16, 32, 528, 16, "本地演化运营模型 · 每秒采样一次，采样点保留 48 个", SZ.xs, C.ink3)

    local cells = {}
    local CAP = { "仿真时长", "采样次数", "累计事件" }
    for i, cap in ipairs(CAP) do
        local x = 16 + (i - 1) * 179
        theme.label(dc, x, 54, 160, 14, cap, SZ.xs, C.ink3)
        cells[i] = theme.label(dc, x, 70, 160, 26, "--", SZ.l, C.ink)
    end
    page.cells = cells

    local btn_pause = theme.ghost(dc, 16, 104, 170, 32, "暂停演示", {
        size = SZ.s,
        on_click = function()
            local paused = sim.toggle_pause()
            toast(paused and "演示模型已暂停" or "演示模型已恢复", "ok")
            page.refresh()
        end,
    })
    local btn_reset = theme.ghost(dc, 195, 104, 170, 32, "重置数据", {
        size = SZ.s,
        on_click = function()
            sim.reset()
            toast("演示数据已重置", "ok")
            page.refresh()
        end,
    })
    local btn_groom = theme.ghost(dc, 374, 104, 170, 32, "一键压雪", {
        size = SZ.s,
        on_click = function()
            sim.groom()
            toast("压雪作业完成，雪面已平整", "ok")
            page.refresh()
        end,
    })
    theme.label(dc, 16, 146, 528, 14, "以上操作仅作用于仿真数据，不下发到真实设备", SZ.xs, C.ink3)
    page.d_chip = d_chip
    page.btn_pause = btn_pause
    page.btn_reset = btn_reset
    page.btn_groom = btn_groom

    -- ==================== 机械体检 ====================
    local hc = theme.card(root, L.health.x, L.health.y, L.health.w, L.health.h, { radius = 14 })
    theme.label(hc, 16, 8, 220, 20, "机械体检", SZ.m, C.ink)
    local h_chip = theme.chip(hc, 432, 10, 112, 20, "全站正常", C.bg0, C.green, SZ.xs)
    theme.hline(hc, 16, 30, 528, C.line)

    local hcells = {}
    for i, def in ipairs(conf.health) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local x = 16 + col * 176
        local y = 40 + row * 58
        theme.box(hc, x, y, 168, 50, C.panel2, 8)
        theme.label(hc, x + 10, y + 6, 100, 14, def.name, SZ.xs, C.ink3)
        local dot = theme.box(hc, x + 148, y + 9, 6, 6, C.green, 3)
        local val = theme.label(hc, x + 10, y + 22, 96, 22, "--", SZ.l, C.ink)
        local unit = theme.label(hc, x + 110, y + 27, 28, 14, def.unit, SZ.xs, C.ink3)
        hcells[i] = { def = def, val = val, unit = unit, dot = dot }
    end
    page.hcells = hcells
    page.h_chip = h_chip

    -- ==================== 系统信息 ====================
    local sic = theme.card(root, L.sysinfo.x, L.sysinfo.y, L.sysinfo.w, L.sysinfo.h, { radius = 14 })
    theme.label(sic, 16, 8, 220, 20, "系统信息", SZ.m, C.ink)
    theme.chip(sic, 296, 10, 104, 20, "在线", C.bg0, C.green, SZ.xs)
    theme.hline(sic, 16, 32, 384, C.line)

    local SYS_ROWS = {
        { "产品名称", conf.name },
        { "软件版本", conf.version },
        { "屏幕分辨率", string.format("%d × %d", conf.W, conf.H) },
        { "显示驱动", "RGB · EXD" },
        { "触摸", "GT911 · I2C1" },
        { "中文字库", "hzfont × 6 档" },
        { "固件版本", fw_text() },
        { "运行时长", "--" },
        { "系统内存", "--" },
    }
    local sys_vals = {}
    for i, r in ipairs(SYS_ROWS) do
        local y = 40 + (i - 1) * 23
        theme.label(sic, 16, y, 140, 16, r[1], SZ.xs, C.ink3)
        sys_vals[i] = theme.label(sic, 158, y, 242, 16, r[2], SZ.xs, C.ink, A_RIGHT)
    end
    page.sys_vals = sys_vals

    -- ==================== 站点档案 ====================
    local ec = theme.card(root, L.site.x, L.site.y, L.site.w, L.site.h, { radius = 14 })
    theme.label(ec, 16, 8, 220, 20, "站点档案", SZ.m, C.ink)
    local yrs = tonumber(string.match(conf.resort.opened or "", "^(%d+)")) or 2019
    local s_chip = theme.chip(ec, 296, 10, 104, 20, string.format("运营 %d 年", 2026 - yrs), C.ink2, C.panel2, SZ.xs)
    theme.hline(ec, 16, 32, 384, C.line)

    local hero = theme.box(ec, 16, 40, 384, 66, C.panel2, 10)
    art.icon(ec, "peak", 28, 54, 34, C.ice)
    theme.label(ec, 72, 48, 200, 22, conf.resort.name, SZ.l, C.ink)
    theme.label(ec, 72, 72, 210, 16, conf.resort.site, SZ.xs, C.ink3)
    theme.label(ec, 244, 50, 144, 40, string.format("%d m", conf.resort.top), SZ.l, C.snow, A_RIGHT)
    theme.label(ec, 244, 74, 144, 14, "上站海拔", SZ.xs, C.ink3, A_RIGHT)

    local SITE_ROWS = {
        { "基准海拔", string.format("%d m", conf.resort.altitude) },
        { "垂直落差", string.format("%d m", conf.resort.drop) },
        { "索道线路", string.format("%d 条 · %d 座支架", #conf.lifts, conf.lifts[1].towers) },
        { "雪道", string.format("%d 条 · 总长 %d m", conf.resort.slopes,
            (function()
                local sum = 0
                for _, s in ipairs(conf.slopes) do sum = sum + s.len end
                return sum
            end)()) },
        { "造雪机", string.format("%d 台 · 额定 %.0f cm/h", #conf.guns,
            (function()
                local sum = 0
                for _, g in ipairs(conf.guns) do sum = sum + g.rate end
                return sum * 0.1
            end)()) },
        { "开业时间", conf.resort.opened },
    }
    local site_vals = {}
    for i, r in ipairs(SITE_ROWS) do
        local y = 118 + (i - 1) * 24
        theme.label(ec, 16, y, 140, 16, r[1], SZ.xs, C.ink3)
        site_vals[i] = theme.label(ec, 158, y, 242, 16, r[2], SZ.xs, C.ink, A_RIGHT)
    end
    page.site_vals = site_vals
    page.s_chip = s_chip
    page.hero = hero

    -- ==================== 刷新 ====================
    local function refresh()
        if not page.alive then return end
        local s = sim.summary()

        -- 背光
        page.bright_val:set_text(string.format("%d", page.bright))
        page.bright_hint:set_text(string.format("当前 %d%% · 下限 %d%%", page.bright, conf.backlight.min))
        page.bright_sub:set_text(page.bright >= 85 and "长时间高亮会加速背光老化"
            or (page.bright <= 30 and "夜间值守模式，站台巡视建议提高亮度" or "亮度适中，适合全天候值守"))

        -- 演示模型
        local paused = s.paused
        page.d_chip.set(paused and "已暂停" or "运行中", C.bg0)
        page.d_chip.box:set_color(paused and C.gold or C.green)
        page.btn_pause:set_text(paused and "恢复演示" or "暂停演示")
        page.cells[1]:set_text(uptime_text(sim.uptime()))
        page.cells[1]:set_color(C.ink)
        page.cells[2]:set_text(string.format("%d 次", sim.data.ticks))
        page.cells[2]:set_color(C.ink)
        page.cells[3]:set_text(string.format("%d 条", #sim.data.events))
        page.cells[3]:set_color(#sim.data.events > 0 and C.ink or C.ink3)

        -- 机械体检
        local worst = sim.health_worst()
        page.h_chip.set(theme.state_text(worst), C.bg0)
        page.h_chip.box:set_color(theme.state_color(worst))
        for i, cell in ipairs(page.hcells) do
            local h = sim.health(cell.def.key)
            local lv = level_of(h, cell.def)
            cell.val:set_text(string.format("%." .. cell.def.dec .. "f", h.value))
            cell.val:set_color(lv == "ok" and C.ink or theme.state_color(lv))
            cell.unit:set_color(lv == "ok" and C.ink3 or theme.state_color(lv))
            cell.dot:set_color(theme.state_color(lv))
        end

        -- 系统信息
        page.sys_vals[8]:set_text(uptime_text(sim.uptime()))
        page.sys_vals[9]:set_text(mem_text())

        -- 站点档案
        page.site_vals[5]:set_text(string.format("%d 台 · 运行 %d 台", #conf.guns,
            (function()
                local n = 0
                for _, g in ipairs(sim.guns()) do
                    if g.on and not g.fault then n = n + 1 end
                end
                return n
            end)()))
    end
    page.refresh = refresh

    function page.destroy()
        page.alive = false
    end

    refresh()
    return page
end

return M
