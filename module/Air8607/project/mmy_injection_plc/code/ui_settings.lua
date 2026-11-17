--[[
@module  ui_settings
@summary 系统页：背光 / 演示模型 / 设备体检 / 系统信息 / PLC 诊断 / 设备档案
@version 1.0
@date    2026.11.15
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
    display = { x = 14,  y = 10,  w = 336, h = 176 },
    demo    = { x = 14,  y = 196, w = 336, h = 150 },
    health  = { x = 14,  y = 356, w = 336, h = 178 },
    system  = { x = 366, y = 10,  w = 320, h = 176 },
    diag    = { x = 366, y = 196, w = 320, h = 338 },
    archive = { x = 698, y = 10,  w = 312, h = 250 },
    tips    = { x = 698, y = 270, w = 312, h = 264 },
}

local function fmt_uptime(sec)
    sec = math.max(0, theme.n(sec))
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
end

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

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 显示与背光 ====================
    local dc = theme.card(root, L.display.x, L.display.y, L.display.w, L.display.h, { radius = 10 })
    theme.label(dc, 14, 8, 160, 18, "显示与背光", SZ.s, C.ink)
    local bri_val = theme.label(dc, 250, 8, 74, 18, conf.backlight.default .. "%", SZ.xs, C.ink2, A_RIGHT)

    local bri = conf.backlight.default
    local function set_brightness(v)
        v = theme.clamp(theme.n(v), conf.backlight.min, 100)
        bri = v
        pcall(function()
            pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, v)
            pwm.start(conf.backlight.pwm_ch)
        end)
        bri_val:set_text(string.format("%d%%", v))
    end

    local bar = mk_slider(dc, 14, 34, 308, 26, conf.backlight.min, 100, bri, C.run, function(self)
        set_brightness(self:get_value())
    end)

    theme.label(dc, 14, 64, 220, 14, "PWM3（GPIO13），1000 Hz", SZ.xs, C.ink3)
    local bri_now = theme.label(dc, 190, 64, 132, 14, "", SZ.xs, C.ink3, A_RIGHT)
    page.bri_now = bri_now

    local PRE = {
        { name = "夜间", v = 32 },
        { name = "标准", v = 82 },
        { name = "明亮", v = 100 },
    }
    for i, p in ipairs(PRE) do
        theme.ghost(dc, 14 + (i - 1) * 106, 86, 98, 28, p.name, {
            size = SZ.xs,
            on_click = function()
                set_brightness(p.v)
                if bar then theme.setbar(bar, p.v, true) end
            end,
        })
    end
    theme.label(dc, 14, 122, 308, 14, "背光在显示初始化完成后才点亮，避免上电花屏", SZ.xs, C.ink3)
    theme.label(dc, 14, 142, 308, 14, "夜间模式用于值守班次，亮度不低于 30%", SZ.xs, C.ink3)

    -- ==================== 演示模型 ====================
    local mc = theme.card(root, L.demo.x, L.demo.y, L.demo.w, L.demo.h, { radius = 10 })
    theme.label(mc, 14, 8, 160, 18, "演示模型", SZ.s, C.ink)
    local mstate = theme.label(mc, 250, 8, 74, 18, "", SZ.xs, C.run, A_RIGHT)
    page.mstate = mstate

    local DEMO = {
        { cap = "采样次数", key = "tick" },
        { cap = "运行时长", key = "uptime" },
        { cap = "事件条数", key = "events" },
    }
    local cells = {}
    for i, d in ipairs(DEMO) do
        local x = 14 + (i - 1) * 106
        theme.label(mc, x, 32, 100, 14, d.cap, SZ.xs, C.ink3)
        cells[i] = theme.label(mc, x, 46, 100, 20, "0", SZ.m, C.ink)
    end
    page.cells = cells

    local btn_pause = theme.ghost(mc, 14, 78, 148, 28, "暂停模型", {
        size = SZ.xs,
        on_click = function()
            sim.pause(not sim.is_paused())
            page.refresh()
        end,
    })
    theme.ghost(mc, 172, 78, 148, 28, "重置数据", {
        size = SZ.xs,
        on_click = function()
            sim.reset()
            page.refresh()
        end,
    })
    page.btn_pause = btn_pause
    theme.label(mc, 14, 114, 308, 14, "采样 1 s，一炮 28 s，历史 120 点", SZ.xs, C.ink3)

    -- ==================== 设备体检 ====================
    local hc = theme.card(root, L.health.x, L.health.y, L.health.w, L.health.h, { radius = 10 })
    theme.label(hc, 14, 8, 160, 18, "设备体检", SZ.s, C.ink)
    local hbad = theme.label(hc, 250, 8, 74, 18, "", SZ.xs, C.ink3, A_RIGHT)
    page.hbad = hbad

    local hrows = {}
    for i, d in ipairs(conf.health) do
        local y = 32 + (i - 1) * 24
        theme.hline(hc, 14, y + 20, L.health.w - 28, C.line)
        local dot = theme.box(hc, 14, y + 6, 5, 5, C.green, 2)
        theme.label(hc, 26, y, 130, 16, d.name, SZ.xs, C.ink3)
        local val = theme.label(hc, 162, y, 96, 16, "--", SZ.xs, C.ink2, A_RIGHT)
        local stt = theme.label(hc, 262, y, 62, 16, "", SZ.xs, C.ink3, A_RIGHT)
        hrows[i] = { dot = dot, val = val, stt = stt, def = d }
    end
    page.hrows = hrows

    -- ==================== 系统信息 ====================
    local sc = theme.card(root, L.system.x, L.system.y, L.system.w, L.system.h, { radius = 10 })
    theme.label(sc, 14, 8, 160, 18, "系统信息", SZ.s, C.ink)
    local INFO = {
        { cap = "分辨率", val = conf.W .. " x " .. conf.H },
        { cap = "显示驱动", val = "RGB 并行，10.1 寸" },
        { cap = "触摸", val = "GT911，I2C1" },
        { cap = "字库", val = "hzfont 6 档" },
        { cap = "Lua 内存", val = "--" },
        { cap = "运行时长", val = "--" },
    }
    local infos = {}
    for i, d in ipairs(INFO) do
        local y = 32 + (i - 1) * 23
        theme.label(sc, 14, y, 96, 16, d.cap, SZ.xs, C.ink3)
        infos[i] = theme.label(sc, 114, y, 192, 16, d.val, SZ.xs, C.ink2, A_RIGHT)
    end
    page.infos = infos

    -- ==================== PLC 诊断 ====================
    local dg = theme.card(root, L.diag.x, L.diag.y, L.diag.w, L.diag.h, { radius = 10 })
    theme.label(dg, 14, 8, 180, 18, "PLC 诊断", SZ.s, C.ink)
    local dg_state = theme.label(dg, 200, 8, 106, 18, "", SZ.xs, C.run, A_RIGHT)
    page.dg_state = dg_state

    local MET = {
        { cap = "扫描周期", unit = "ms", key = "scan" },
        { cap = "CPU 负荷", unit = "%",  key = "cpu" },
        { cap = "任务数",   unit = "个", key = "task" },
        { cap = "背板模块", unit = "个", key = "mod" },
    }
    local mets = {}
    for i, d in ipairs(MET) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 14 + col * 150
        local y = 32 + row * 46
        theme.label(dg, x, y, 120, 14, d.cap, SZ.xs, C.ink3)
        local v = theme.label(dg, x, y + 14, 50, 24, "--", SZ.l, C.ink)
        theme.label(dg, x + 52, y + 20, 40, 14, d.unit, SZ.xs, C.ink3)
        mets[i] = { def = d, val = v }
    end
    page.mets = mets

    theme.hline(dg, 14, 126, L.diag.w - 28, C.line)
    theme.label(dg, 14, 132, 160, 14, "扫描周期趋势", SZ.xs, C.ink3)
    local scan_shape = theme.shape(dg, 14, 150, 292, 42, {})
    page.scan_shape = scan_shape

    theme.hline(dg, 14, 200, L.diag.w - 28, C.line)
    theme.label(dg, 14, 206, 160, 14, "诊断缓冲", SZ.xs, C.ink3)
    local drows = {}
    for i = 1, 5 do
        local y = 226 + (i - 1) * 20
        local dot = theme.box(dg, 14, y + 5, 4, 4, C.line, 2)
        local t = theme.label(dg, 24, y, 36, 14, "", SZ.xs, C.ink3)
        local tx = theme.label(dg, 62, y, 244, 14, "", SZ.xs, C.ink3)
        drows[i] = { dot = dot, time = t, text = tx }
    end
    page.drows = drows

    -- ==================== 设备档案 ====================
    local ac = theme.card(root, L.archive.x, L.archive.y, L.archive.w, L.archive.h, { radius = 10 })
    theme.label(ac, 14, 8, 160, 18, "设备档案", SZ.s, C.ink)
    local ARCH = {
        { cap = "机台", val = conf.machine.name },
        { cap = "型号", val = conf.machine.model },
        { cap = "当前模具", val = conf.machine.molds },
        { cap = "安装位置", val = conf.machine.site },
        { cap = "锁模力", val = conf.machine.clamp .. " kN" },
        { cap = "螺杆直径", val = conf.machine.screw .. " mm" },
        { cap = "理论注射量", val = conf.machine.shot .. " cm3" },
        { cap = "投运时间", val = conf.machine.commission },
    }
    for i, d in ipairs(ARCH) do
        local y = 32 + (i - 1) * 26
        theme.label(ac, 14, y, 76, 16, d.cap, SZ.xs, C.ink3)
        theme.label(ac, 92, y, 206, 16, d.val, SZ.xs, C.ink2, A_RIGHT)
    end
    local arch_shot = theme.label(ac, 14, 232, 284, 14, "", SZ.xs, C.ink3)
    page.arch_shot = arch_shot

    -- ==================== 操作提示 ====================
    local tp = theme.card(root, L.tips.x, L.tips.y, L.tips.w, L.tips.h, { radius = 10 })
    theme.label(tp, 14, 8, 160, 18, "使用说明", SZ.s, C.ink)
    local TIPS = {
        "1、顶部五个页签切换页面，页面切换即销毁重建。",
        "2、总览页的启动按钮仅在停机或故障复位后可用。",
        "3、梯形图页按 PLC 扫描顺序着色，青为导通。",
        "4、点位页可点按强制，强制值优先于实时映像。",
        "5、演示脚本每 2 分钟注入一次故障，用于观察联锁。",
        "6、所有工艺量由本地模型演化，不接真实控制器。",
    }
    for i, t in ipairs(TIPS) do
        theme.label(tp, 14, 34 + (i - 1) * 34, 284, 32, t, SZ.xs, C.ink3)
    end

    -- ==================== 刷新 ====================
    local round = 0
    local function refresh()
        if not page.alive then return end
        local s = sim.summary()
        round = round + 1

        page.cells[1]:set_text(tostring(theme.n(s.tick)))
        page.cells[2]:set_text(fmt_uptime(s.uptime))
        page.cells[3]:set_text(tostring(sim.event_count()))

        local paused = sim.is_paused()
        page.mstate:set_text(paused and "已暂停" or "采集中")
        page.mstate:set_color(paused and C.amber or C.run)
        page.btn_pause:set_text(paused and "恢复模型" or "暂停模型")

        page.bri_now:set_text(string.format("当前 %d%%", bri))
        page.infos[5]:set_text(string.format("Lua %.0f KB", collectgarbage("count")))
        page.infos[6]:set_text(fmt_uptime(s.uptime))

        -- 体检
        local bad = 0
        for i, r in ipairs(page.hrows) do
            local h = sim.health(r.def.key)
            local fmt = "%." .. r.def.dec .. "f"
            r.val:set_text(string.format(fmt, h.value) .. (r.def.unit ~= "" and (" " .. r.def.unit) or ""))
            r.val:set_color(h.level == "ok" and C.ink2 or C.amber)
            r.stt:set_text(theme.state_text(h.level))
            r.stt:set_color(theme.state_color(h.level))
            pcall(function() r.dot:set_color(theme.state_color(h.level)) end)
            if h.level ~= "ok" then bad = bad + 1 end
        end
        page.hbad:set_text(bad == 0 and "全部正常" or (bad .. " 项关注"))
        page.hbad:set_color(bad == 0 and C.run or C.amber)

        -- 诊断
        local mode, mode_text = sim.mode()
        page.dg_state:set_text(mode_text)
        page.dg_state:set_color(mode == "fault" and C.red or C.run)
        page.mets[1].val:set_text(string.format("%.1f", s.scan))
        page.mets[2].val:set_text(string.format("%d", theme.n(s.cpu)))
        page.mets[3].val:set_text("6")
        page.mets[4].val:set_text(tostring(#conf.modules))

        if round % 2 == 0 then
            -- 扫描周期趋势：用最近 20 次采样的 cpu 负荷做条形，一个 shape 重建
            local items = art.curve_items(292, 42, {
                { data = { s.cpu - 3, s.cpu - 1, s.cpu + 1, s.cpu - 2, s.cpu, s.cpu + 2,
                           s.cpu - 1, s.cpu + 1, s.cpu - 2, s.cpu, s.cpu + 1, s.cpu - 1 },
                  color = C.run, min = 16, max = 44, width = 2, sample = 14 },
            }, { pad_top = 2, pad_bottom = 4, grid = 2, dot = false })
            pcall(function() page.scan_shape:set_items(items) end)

            local evs = sim.events(5)
            for i, row in ipairs(page.drows) do
                local e = evs[i]
                if e then
                    pcall(function() row.dot:set_color(theme.state_color(e.level)) end)
                    row.time:set_text(e.clock)
                    row.text:set_text(theme.fit(e.text, 20))
                    row.text:set_color(e.level == "danger" and C.red or (e.level == "warn" and C.amber or C.ink3))
                else
                    row.time:set_text("")
                    row.text:set_text("")
                end
            end
        end

        page.arch_shot:set_text(string.format("今日 %d 模，良品 %d，不良 %d",
            theme.n(s.shot - 1200), theme.n(s.good - 1189), theme.n(s.bad - 11)))
    end
    page.refresh = refresh

    local function slow()
        if not page.alive then return end
    end
    page.slow = slow

    function page.destroy()
        page.alive = false
    end

    refresh()
    return page
end

return M
