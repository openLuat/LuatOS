--[[
@module  ui_settings
@summary 设置页：传输方式、RS485 串口参数、TCP/轮询参数、屏幕亮度、模拟开关
@version 1.0.0
@date    2026.10.25
]]
local conf = require "conf"
local theme = require "theme"
local mbdev = require "mbdev"
local mbmaster = require "mbmaster"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H
local NAV_Y = 548

local IS_PC = (rtos and rtos.bsp and rtos.bsp() == "PC")

local root = nil
local app_ref = nil

local transBtns = {}
local baudBtns, parityBtns, stopBtns, pinBtns = {}, {}, {}, {}
local pollBtns, toBtns, retryBtns = {}, {}, {}
local brightLabel, brightSlider, pauseBtn
local cur_bright = conf.backlight.default
local headerRight, infoLabel

-- ==================== 背光 ====================
local function apply_bright(v)
    v = math.floor(v + 0.5)
    if v < conf.backlight.min then v = conf.backlight.min end
    if v > 100 then v = 100 end
    cur_bright = v
    if (not IS_PC) and pwm and pwm.setup then
        pcall(function()
            pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, v)
            pwm.start(conf.backlight.pwm_ch)
        end)
    end
    if brightLabel then brightLabel:set_text(v .. "%") end
    return v
end

-- ==================== 通用：一组互斥按钮 ====================
-- 注意：airui 控件是 userdata，不能往上面挂自定义字段，所以额外用一张表保存
-- {items, btns, is_sel, color}
local function group(parent, x, y, w, h, gap, items, is_sel, on_pick, refresh_fn, color)
    local g = { items = items, btns = {}, is_sel = is_sel, color = color or C.cyan }
    for i, it in ipairs(items) do
        local bx = x + (i - 1) * (w + gap)
        g.btns[i] = theme.button(parent, bx, y, w, h, it.text, it.size or 13, C.panel2, C.ink2,
            function()
                theme.defer(function()
                    on_pick(it.value)
                    if refresh_fn then refresh_fn() end
                end)
            end, 7)
    end
    return g
end

local function refresh_group(g)
    if not g or not g.btns then return end
    for i, b in ipairs(g.btns) do
        local on = g.is_sel(g.items[i].value)
        b:set_style({
            bg_color = on and g.color or C.panel2,
            text_color = on and 0x05141C or C.ink2,
            border_color = on and g.color or C.line2,
            radius = 7,
        })
    end
end

local function refresh_all()
    if transBtns and transBtns.btns then
        for i, b in ipairs(transBtns.btns) do
            local on = (transBtns.items[i].value == mbmaster.transport())
            b:set_style({
                bg_color = on and C.cyan or C.panel2,
                text_color = on and 0x05141C or C.ink2,
                border_color = on and C.cyan or C.line2,
                radius = 9,
            })
        end
    end
    refresh_group(baudBtns)
    refresh_group(parityBtns)
    refresh_group(stopBtns)
    refresh_group(pinBtns)
    refresh_group(pollBtns)
    refresh_group(toBtns)
    refresh_group(retryBtns)
    if pauseBtn then
        pauseBtn:set_text(mbmaster.paused() and "恢复轮询" or "暂停轮询")
        pauseBtn:set_style({
            bg_color = mbmaster.paused() and C.green or C.amber,
            text_color = 0x05141C,
            border_color = mbmaster.paused() and C.green or C.amber,
            radius = 9,
        })
    end
end

-- ==================== 卡片 ====================
local function build_trans_card()
    local c = theme.card(root, 24, 66, 976, 92)
    theme.accent_bar(c, 16, 0, 50, C.cyan)
    theme.label(c, 16, 10, 300, 22, "通讯方式", 16, C.ink)
    infoLabel = theme.label(c, 330, 13, 630, 20, "", 12, C.ink3, airui.TEXT_ALIGN_RIGHT)

    local items = {
        { text = "内置虚拟从站", value = "sim" },
        { text = "RS485 RTU", value = "rtu" },
        { text = "Modbus TCP", value = "tcp" },
    }
    transBtns = group(c, 16, 44, 300, 38, 12, items,
        function(v) return v == mbmaster.transport() end,
        function(v)
            local ok, err = mbmaster.set_transport(v)
            if app_ref then
                app_ref.toast(ok and ("已切换到 " .. v) or ("切换失败：" .. tostring(err)))
            end
        end,
        refresh_all, C.cyan)
end

local function build_serial_card()
    local c = theme.card(root, 24, 168, 480, 210)
    theme.accent_bar(c, 16, 0, 50, C.amber)
    theme.label(c, 16, 10, 300, 22, "RS485 串口参数", 16, C.ink)

    theme.label(c, 16, 46, 60, 20, "波特率", 12, C.ink3)
    baudBtns = group(c, 80, 44, 92, 26, 6, {
        { text = "9600", value = 9600 }, { text = "19200", value = 19200 },
        { text = "38400", value = 38400 }, { text = "115200", value = 115200 },
    }, function(v) return conf.comm.rtu.baud == v end,
       function(v) conf.comm.rtu.baud = v end, refresh_all, C.amber)

    theme.label(c, 16, 86, 60, 20, "校验位", 12, C.ink3)
    parityBtns = group(c, 80, 84, 60, 26, 6, {
        { text = "无", value = "none" }, { text = "奇", value = "odd" }, { text = "偶", value = "even" },
    }, function(v) return conf.comm.rtu.parity == v end,
       function(v) conf.comm.rtu.parity = v end, refresh_all, C.amber)

    theme.label(c, 256, 86, 60, 20, "停止位", 12, C.ink3)
    stopBtns = group(c, 320, 84, 48, 26, 6, {
        { text = "1", value = 1 }, { text = "2", value = 2 },
    }, function(v) return conf.comm.rtu.stopbits == v end,
       function(v) conf.comm.rtu.stopbits = v end, refresh_all, C.amber)

    theme.label(c, 16, 126, 60, 20, "换向脚", 12, C.ink3)
    pinBtns = group(c, 80, 124, 60, 26, 6, {
        { text = "禁用", value = 0 }, { text = "GPIO10", value = 10 },
        { text = "GPIO24", value = 24 }, { text = "GPIO33", value = 33 },
    }, function(v) return conf.comm.rtu.rs485_de_pin == v end,
       function(v) conf.comm.rtu.rs485_de_pin = v end, refresh_all, C.amber)
    theme.label(c, 16, 160, 448, 18, "换向脚 = 禁用：由收发器自行换向", 11, C.ink3)
    theme.label(c, 16, 180, 448, 18, "指定 GPIO：交给 uart 硬件 485 自动切换（接收电平取反）", 11, C.ink3)
end

local function build_net_card()
    local c = theme.card(root, 516, 168, 484, 210)
    theme.accent_bar(c, 16, 0, 50, C.green)
    theme.label(c, 16, 10, 300, 22, "Modbus TCP / 轮询参数", 16, C.ink)

    theme.label(c, 16, 44, 452, 20, string.format("服务器  %s : %d  （在 conf.lua 修改）",
        conf.comm.tcp.ip, conf.comm.tcp.port), 12, C.ink3)

    theme.label(c, 16, 74, 70, 20, "轮询周期", 12, C.ink3)
    pollBtns = group(c, 92, 72, 78, 26, 6, {
        { text = "500ms", value = 500 }, { text = "1s", value = 1000 }, { text = "2s", value = 2000 },
    }, function(v) return conf.comm.poll_interval_ms == v end,
       function(v) conf.comm.poll_interval_ms = v end, refresh_all, C.green)

    theme.label(c, 16, 112, 70, 20, "响应超时", 12, C.ink3)
    toBtns = group(c, 92, 110, 78, 26, 6, {
        { text = "300ms", value = 300 }, { text = "800ms", value = 800 }, { text = "1500ms", value = 1500 },
    }, function(v) return conf.comm.timeout_ms == v end,
       function(v) conf.comm.timeout_ms = v end, refresh_all, C.green)

    theme.label(c, 16, 150, 70, 20, "失败重试", 12, C.ink3)
    retryBtns = group(c, 92, 148, 56, 26, 6, {
        { text = "0", value = 0 }, { text = "1", value = 1 },
        { text = "2", value = 2 }, { text = "3", value = 3 },
    }, function(v) return conf.comm.retry == v end,
       function(v) conf.comm.retry = v end, refresh_all, C.green)

    theme.button(c, 340, 148, 128, 30, "重置统计", 13, C.panel2, C.ink2, function()
        theme.defer(function()
            mbmaster.reset_stats()
            if app_ref then app_ref.toast("通讯统计已重置") end
        end)
    end, 8)
end

local function build_ui_card()
    local c = theme.card(root, 24, 388, 976, 110)
    theme.accent_bar(c, 16, 0, 50, C.violet)
    theme.label(c, 16, 10, 300, 22, "显示与运行", 16, C.ink)

    theme.label(c, 16, 48, 70, 22, "背光", 13, C.ink3)
    local function bdelta(d)
        apply_bright(cur_bright + d)
        if brightSlider then brightSlider:set_value(cur_bright, false) end
    end
    theme.button(c, 90, 44, 60, 34, "-10", 13, C.panel2, C.ink2,
        function() theme.defer(function() bdelta(-10) end) end, 8)
    theme.button(c, 156, 44, 48, 34, "-1", 15, C.panel2, C.ink2,
        function() theme.defer(function() bdelta(-1) end) end, 8)
    brightLabel = theme.label(c, 210, 44, 76, 34, "", 18, C.ink, airui.TEXT_ALIGN_CENTER)
    theme.button(c, 292, 44, 48, 34, "+1", 15, C.panel2, C.ink2,
        function() theme.defer(function() bdelta(1) end) end, 8)
    theme.button(c, 346, 44, 60, 34, "+10", 13, C.panel2, C.ink2,
        function() theme.defer(function() bdelta(10) end) end, 8)

    local ok, sl = pcall(function()
        return airui.slider({
            parent = c, x = 420, y = 50, w = 260, h = 24,
            min = conf.backlight.min, max = 100, value = cur_bright,
            style = {
                bg_color = C.line, bg_opa = 255,
                indicator_color = C.violet, indicator_opa = 255,
                knob_color = 0xFFFFFF, knob_opa = 255,
                knob_border_color = C.violet, knob_border_width = 2,
                radius = 12,
            },
            on_change = function()
                if brightSlider then apply_bright(brightSlider:get_value()) end
            end,
        })
    end)
    brightSlider = ok and sl or nil
    brightLabel:set_text(cur_bright .. "%")

    pauseBtn = theme.button(c, 700, 40, 140, 44, "暂停轮询", 15, C.amber, 0x05141C, function()
        theme.defer(function()
            mbmaster.set_paused(not mbmaster.paused())
            if app_ref then app_ref.toast(mbmaster.paused() and "轮询已暂停" or "轮询已恢复") end
            refresh_all()
        end)
    end, 9)

    theme.button(c, 850, 40, 110, 44, "清空报警", 14, C.panel2, C.red, function()
        theme.defer(function()
            mbdev.clear_alarms()
            if app_ref then app_ref.toast("报警记录已清空") end
        end)
    end, 9)
end

-- ==================== 构建 / 刷新 ====================
function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 12)

    headerRight = theme.page_header(root, "系统设置 · Settings", "", C.ink3)

    build_trans_card()
    build_serial_card()
    build_net_card()
    build_ui_card()

    theme.label(root, 24, 508, 700, 20, string.format(
        "%s v%s · Air8607 + AirLCD_1090 1024×600 · %s",
        conf.name, conf.version, IS_PC and "PC 模拟器" or "实机运行"), 12, C.ink3)

    theme.navbar(root, "settings", NAV_Y, function(id)
        if app_ref then app_ref.show(id) end
    end)

    refresh_all()
    M.refresh()
end

function M.refresh()
    if not root then return end
    if infoLabel then
        infoLabel:set_text(string.format("当前：%s · %s", mbmaster.transport_name(), mbmaster.transport_desc()))
    end
    if headerRight then
        headerRight:set_text(string.format("在线 %d/%d · 报警 %d",
            mbdev.online_count(), #mbdev.devices(), #mbdev.alarms()))
    end
end

function M.destroy()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    transBtns, baudBtns, parityBtns, stopBtns, pinBtns = {}, {}, {}, {}, {}
    pollBtns, toBtns, retryBtns = {}, {}, {}
    brightLabel, brightSlider, pauseBtn = nil, nil, nil
    headerRight, infoLabel = nil, nil
end

return M
