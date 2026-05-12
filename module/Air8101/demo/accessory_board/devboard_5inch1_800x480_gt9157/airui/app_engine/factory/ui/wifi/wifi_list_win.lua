--[[ naming: lv=2-4 chars, lf=2-5 chars ]]
--[[
@module  wifi_list_win
@summary WiFi列表窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
@author  江访
]]

require "wifi_connect_win"
require "wifi_detail_win"

local SW, SH = 480, 800
local MG = 15
local TH = math.floor(60 * _G.density_scale)
local CH = 60

local CP  = 0x007AFF
local CPD = 0x0056B3
local CBG = 0xF5F5F5
local CCD = 0xFFFFFF
local CTX = 0x333333
local CT2 = 0x757575
local CDV = 0xE0E0E0
local CWH = 0xFFFFFF
local CAC = 0xFF9800

local function upss()
    local rt = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rt == 0 or rt == 180 then
        SW, SH = pw, ph
    else
        SW, SH = ph, pw
    end
    MG = math.floor(SW * 0.03)
    TH = math.floor(60 * _G.density_scale)
    CH = math.floor(SH * 0.09)
end

local wid = nil
local lmc = nil
local lcci = nil
local lwc = nil
local lsc = nil
local lwi = {}
local llc = nil
local lcc = nil
local wes = nil
local wsc = nil
local ipss = false

local snl = {}
local sni = {}
local csr = {}

local sic = nil
local srf = nil

local function sish()
    if srf then srf:hide() end
    if sic then sic:open() end
end

local function sihd()
    if sic then sic:hide() end
    if srf then srf:open() end
end

local cfg = {
    wifi_enabled = false, ssid = "", password = "",
    need_ping = true, local_network_mode = false,
    ping_ip = "", ping_time = "10000", auto_socket_switch = true
}
local sts = {
    connected = false, ready = false, current_ssid = "",
    rssi = "--", ip = "--", netmask = "--", gateway = "--", bssid = "--",
    scan_results = {}
}

local function cwfi(wf, idx)
    local sig = math.min(100, math.max(0, (wf.rssi or -100) + 100))
    local iw = SW - 2 * MG - math.floor(20 * _G.density_scale)
    local ic = sts and sts.current_ssid == wf.ssid
    local it = airui.container({
        parent = lwc,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale) + (idx - 1) * math.floor(75 * _G.density_scale),
        w = iw, h = math.floor(65 * _G.density_scale),
        color = CCD, radius = 4,
        on_click = function()
            if ic then
                sys.publish("OPEN_WIFI_DETAIL_WIN")
            else
                sys.publish("OPEN_WIFI_CONNECT_WIN", wf.ssid)
            end
        end
    })
    airui.label({
        parent = it,
        text = wf.ssid or "未知",
        x = math.floor(10 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = iw - math.floor(80 * _G.density_scale), h = math.floor(20 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = CTX,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = it,
        text = string.format("%d%%", sig),
        x = math.floor(10 * _G.density_scale), y = math.floor(36 * _G.density_scale),
        w = iw - math.floor(80 * _G.density_scale), h = math.floor(15 * _G.density_scale),
        font_size = math.floor(16 * _G.density_scale),
        color = CT2,
        align = airui.TEXT_ALIGN_LEFT,
    })
    if ic then
        airui.label({
            parent = it,
            x = iw - math.floor(80 * _G.density_scale), y = math.floor(17 * _G.density_scale),
            w = math.floor(70 * _G.density_scale), h = math.floor(30 * _G.density_scale),
            text = "已连接",
            font_size = math.floor(16 * _G.density_scale),
            color = 0x4CAF50,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
    table.insert(lwi, it)
end

local function csni(sw, idx, stx)
    local iw = SW - 2 * MG - math.floor(20 * _G.density_scale)
    local it = airui.container({
        parent = lsc,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale) + (idx - 1) * math.floor(60 * _G.density_scale),
        w = iw, h = math.floor(50 * _G.density_scale),
        color = CCD, radius = 4,
        on_click = function()
            if stx == "已连接" then
                sys.publish("OPEN_WIFI_DETAIL_WIN")
            else
                sys.publish("OPEN_WIFI_CONNECT_WIN", sw, false)
            end
        end
    })
    airui.label({
        parent = it,
        text = sw.ssid or "未知",
        x = math.floor(10 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = iw - math.floor(140 * _G.density_scale), h = math.floor(22 * _G.density_scale),
        font_size = math.floor(22 * _G.density_scale),
        color = CTX,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local sc = stx == "已连接" and 0x4CAF50 or (stx == "已配置" and CAC or CP)
    airui.label({
        parent = it,
        text = stx,
        x = iw - math.floor(130 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(120 * _G.density_scale), h = math.floor(24 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = sc,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    table.insert(sni, it)
end

local function usnl()
    for _, it in ipairs(sni) do it:destroy() end
    sni = {}
    if not lsc then return end
    if not cfg or not cfg.wifi_enabled then return end

    local ms = {}
    local csid = sts and sts.current_ssid or ""
    for _, sw in ipairs(snl) do
        local sc = false
        local ic = (sw.ssid == csid)
        for _, scw in ipairs(csr) do
            if scw.ssid == sw.ssid then sc = true; break end
        end
        if sc or ic then
            table.insert(ms, {
                wifi = sw,
                status = ic and "已连接" or "可连接",
                is_connected = ic
            })
        end
    end
    table.sort(ms, function(a,b)
        if a.is_connected and not b.is_connected then return true end
        if not a.is_connected and b.is_connected then return false end
        return a.wifi.ssid < b.wifi.ssid
    end)
    for i, it in ipairs(ms) do
        csni(it.wifi, i, it.status)
    end
end

local function uwfl(rs)
    for _, it in ipairs(lwi) do it:destroy() end
    lwi = {}
    if rs and #rs > 0 then
        for i, wf in ipairs(rs) do
            cwfi(wf, i)
        end
    end
end

local function wech(ck)
    if ipss then return end
    sys.publish("WIFI_ENABLE_REQ", {enabled = ck})
    if ck then
        sys.publish("WIFI_SCAN_REQ")
    else
        uwfl({})
    end
end

local function lcui()
    upss()
    lmc = airui.container({
        x = 0, y = 0,
        w = SW, h = SH,
        color = CBG,
    })

    local tb = airui.container({
        parent = lmc,
        x = 0, y = 0,
        w = SW, h = TH,
        color = CP,
    })
    local bb = airui.container({
        parent = tb,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = CP,
        on_click = function() exwin.close(wid) end
    })
    airui.label({
        parent = bb,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = CWH,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = tb,
        text = "WiFi 网络配置",
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = SW - math.floor(60 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        font_size = math.floor(32 * _G.density_scale),
        color = CWH,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local scr = airui.container({
        parent = lmc,
        x = 0, y = TH,
        w = SW, h = SH - TH,
        color = CBG,
        scrollable = true,
    })

    -- WiFi开关卡片（紧凑布局）
    local wec = airui.container({
        parent = scr,
        x = MG, y = math.floor(10 * _G.density_scale),
        w = SW - 2 * MG, h = math.floor(50 * _G.density_scale),
        color = CWH, radius = 8,
    })
    local ch = math.floor(50 * _G.density_scale)
    airui.label({
        parent = wec,
        text = "WiFi",
        x = math.floor(10 * _G.density_scale), y = math.floor((ch - 30 * _G.density_scale) / 2),
        w = math.floor(80 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        font_size = math.floor(24 * _G.density_scale),
        color = CTX,
        align = airui.TEXT_ALIGN_LEFT,
    })
    wsc = airui.container({
        parent = wec,
        x = SW - 2 * MG - math.floor(80 * _G.density_scale), y = math.floor((ch - 29 * _G.density_scale) / 2),
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
    })
    wsc:hide()
    wes = airui.switch({
        parent = wsc,
        x = 0, y = 0,
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
        checked = false,
        on_change = function(self)
            sys.taskInit(function() wech(self:get_state()) end)
        end
    })

    -- 已保存wifi
    local sty = math.floor(10 * _G.density_scale) + ch + math.floor(15 * _G.density_scale)
    airui.label({
        parent = scr,
        text = "已保存wifi",
        x = MG + math.floor(5 * _G.density_scale), y = sty,
        w = math.floor(150 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(18 * _G.density_scale),
        color = CT2,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 已保存wifi 容器
    local sy = sty + math.floor(28 * _G.density_scale)
    local sc = airui.container({
        parent = scr,
        x = MG, y = sy,
        w = SW - 2 * MG, h = math.floor(190 * _G.density_scale),
        color = CWH, radius = 8,
    })
    lsc = airui.container({
        parent = sc,
        x = 0, y = 0,
        w = SW - 2 * MG, h = math.floor(190 * _G.density_scale),
        color = CWH,
    })

    -- 附近的wifi
    local scy = sy + math.floor(190 * _G.density_scale) + math.floor(20 * _G.density_scale)
    airui.label({
        parent = scr,
        text = "附近的wifi",
        x = MG + math.floor(5 * _G.density_scale), y = scy,
        w = math.floor(150 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(18 * _G.density_scale),
        color = CT2,
        align = airui.TEXT_ALIGN_LEFT,
    })

    srf = airui.container({
        parent = scr,
        x = SW - 2 * MG - math.floor(60 * _G.density_scale), y = scy,
        w = math.floor(60 * _G.density_scale), h = math.floor(25 * _G.density_scale),
    })
    airui.button({
        parent = srf,
        x = 0, y = 0,
        w = math.floor(60 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        text = "刷新",
        font_size = math.floor(16 * _G.density_scale),
        style = { bg_color = CP, pressed_bg_color = CPD, text_color = CWH },
        on_click = function()
            if cfg and cfg.wifi_enabled then
                sys.publish("WIFI_SCAN_REQ")
            else
                airui.msgbox({ text = "请先开启WiFi", buttons = { "确定" }, on_action = function(s) s:hide() end }):show()
            end
        end
    })

    sic = airui.container({
        parent = scr,
        x = SW - 2 * MG - math.floor(130 * _G.density_scale), y = scy,
        w = math.floor(130 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        color = CBG,
    })
    sic:hide()

    local lcy = scy + math.floor(35 * _G.density_scale)
    local wlc = airui.container({
        parent = scr,
        x = MG, y = lcy,
        w = SW - 2 * MG, h = math.floor(320 * _G.density_scale),
        color = CWH, radius = 8,
    })
    lwc = airui.container({
        parent = wlc,
        x = 0, y = 0,
        w = SW - 2 * MG, h = math.floor(320 * _G.density_scale),
        color = CWH,
    })
end

local function scst()
    log.info("wlw", "扫描开始")
    sish()
end

local function scdn(rs)
    log.info("wlw", "扫描完成，找到", #rs, "个热点")
    sihd()
    csr = rs or {}
    uwfl(rs)
    usnl()
end

local function scto()
    log.warn("wlw", "扫描超时")
    sihd()
    airui.msgbox({ text = "扫描超时，未找到WiFi热点", buttons = { "确定" }, on_action = function(s) s:hide() end }):show()
end

local function cng(sid)
    log.info("wlw", "正在连接:", sid)
    if lcc then lcc:open() end
end

local function cnd(sid)
    log.info("wlw", "连接成功:", sid)
    if lcc then lcc:hide() end
    usnl()
    uwfl(csr)
    airui.msgbox({ text = "WiFi 连接成功", buttons = { "确定" }, timeout = 3000, on_action = function(s) s:destroy() end })
end

local function dsc(rs, cd)
    log.error("wlw", "连接失败:", rs, cd)
    if lcc then lcc:hide() end
    airui.msgbox({ text = "WiFi 连接失败: " .. rs, buttons = { "确定" }, timeout = 3000, on_action = function(s) s:destroy() end })
    usnl()
    uwfl({})
end

local function stup(st)
    log.info("wlw", "WiFi状态更新:", json.encode(st))
    sts = st
    if cfg then
        if not cfg.wifi_enabled and not st.connected then
            uwfl({})
        end
        usnl()
    end
end

local function slrs(dt)
    log.info("wlw", "收到已保存网络列表:", #dt.list)
    snl = dt.list or {}
    usnl()
end

local function cfrs(dt)
    local oe = cfg and cfg.wifi_enabled
    cfg = dt.config
    log.info("wlw", "配置加载完成, enabled:", cfg.wifi_enabled)
    if wes and (oe == nil or oe ~= cfg.wifi_enabled) then
        ipss = true
        wes:set_state(cfg.wifi_enabled)
        ipss = false
    end
    if wsc then wsc:open() end
    if sts then stup(sts) end
    usnl()
    if cfg and cfg.wifi_enabled then
        sys.publish("WIFI_SCAN_REQ")
    end
end

local function lcrt()
    lcui()
    sys.publish("WIFI_GET_STATUS_REQ")
    sys.publish("WIFI_GET_CONFIG_REQ")
    sys.publish("WIFI_GET_SAVED_LIST_REQ")
    sys.subscribe("WIFI_SCAN_STARTED", scst)
    sys.subscribe("WIFI_SCAN_DONE", scdn)
    sys.subscribe("WIFI_SCAN_TIMEOUT", scto)
    sys.subscribe("WIFI_CONNECTING", cng)
    sys.subscribe("WIFI_CONNECTED", cnd)
    sys.subscribe("WIFI_DISCONNECTED", dsc)
    sys.subscribe("WIFI_STATUS_UPDATED", stup)
    sys.subscribe("WIFI_CONFIG_RSP", cfrs)
    sys.subscribe("WIFI_SAVED_LIST_RSP", slrs)
end

local function ldst()
    sys.unsubscribe("WIFI_SCAN_STARTED", scst)
    sys.unsubscribe("WIFI_SCAN_DONE", scdn)
    sys.unsubscribe("WIFI_SCAN_TIMEOUT", scto)
    sys.unsubscribe("WIFI_CONNECTING", cng)
    sys.unsubscribe("WIFI_CONNECTED", cnd)
    sys.unsubscribe("WIFI_DISCONNECTED", dsc)
    sys.unsubscribe("WIFI_STATUS_UPDATED", stup)
    sys.unsubscribe("WIFI_CONFIG_RSP", cfrs)
    sys.unsubscribe("WIFI_SAVED_LIST_RSP", slrs)
    sihd()
    if lmc then lmc:destroy(); lmc = nil end
    lcci = nil
    lwc = nil
    lsc = nil
    lwi = {}
    llc = nil
    lcc = nil
    wes = nil
    wsc = nil
    cfg = nil
    sts = nil
    wid = nil
    snl = {}
    sni = {}
    csr = {}
    sic = nil
    srf = nil
end

local function lgfc()
    sys.publish("WIFI_GET_STATUS_REQ")
    if cfg and cfg.wifi_enabled then
        sys.publish("WIFI_SCAN_REQ")
    end
end

local function llfc() end

local function open()
    if not exwin.is_active(wid) then
        wid = exwin.open({
            on_create = lcrt,
            on_destroy = ldst,
            on_get_focus = lgfc,
            on_lose_focus = llfc,
        })
        log.info("wlw", "WiFi列表窗口打开，ID:", wid)
    end
end

sys.subscribe("OPEN_WIFI_WIN", open)
log.info("wlw", "订阅 OPEN_WIFI_WIN 消息")
