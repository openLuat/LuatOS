-- Naming convention: local fns ≤5 chars, local vars ≤4 chars
--[[
@module  wifi_detail_win
@summary WiFi详情窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
@author  江访
]]

local SW, SH = 480, 800
local MG = 15
local TH = math.floor(60 * _G.density_scale)
local BH = 50

local CPR = 0x007AFF
local CPD = 0x0056B3
local CBG = 0xF5F5F5
local CCD = 0xFFFFFF
local CTX = 0x333333
local CTS = 0x757575
local CDV = 0xE0E0E0
local CWH = 0xFFFFFF
local CDG = 0xE63946

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
    BH = math.floor(SH * 0.0625)
end

local wid = nil
local mc = nil
local lbs = {}
local pv = false

local cs = {
    connected = false, ready = false, current_ssid = "",
    rssi = "--", ip = "--", netmask = "--", gateway = "--", bssid = "--",
    scan_results = {}
}
local cc = {
    wifi_enabled = false, ssid = "", password = "",
    need_ping = true, local_network_mode = false,
    ping_ip = "", ping_time = "10000", auto_socket_switch = true
}

local function updi()
    if not cs then return end
    if lbs.ssid then
        lbs.ssid:set_text(cs.current_ssid ~= "" and cs.current_ssid or "--")
    end
    if lbs.rssi then
        lbs.rssi:set_text(cs.rssi ~= "--" and (cs.rssi .. " dBm") or "--")
    end
    if lbs.ip then lbs.ip:set_text(cs.ip) end
    if lbs.netmask then lbs.netmask:set_text(cs.netmask) end
    if lbs.gateway then lbs.gateway:set_text(cs.gateway) end
    if lbs.bssid then lbs.bssid:set_text(cs.bssid) end
    if lbs.password and cc then
        local pw = cc.password or ""
        if pv then
            lbs.password:set_text(pw)
        else
            lbs.password:set_text(string.rep("*", #pw))
        end
    end
end

local function dcui()
    upss()
    mc = airui.container({
        x = 0, y = 0,
        w = SW, h = SH,
        color = CBG,
    })

    local tb = airui.container({
        parent = mc,
        x = 0, y = 0,
        w = SW, h = TH,
        color = CPR,
    })
    local bb = airui.container({
        parent = tb,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = TH - math.floor(20 * _G.density_scale),
        color = CPR,
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
        text = "WiFi 详情",
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = SW - math.floor(60 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        font_size = math.floor(32 * _G.density_scale),
        color = CWH,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local sc = airui.container({
        parent = mc,
        x = 0, y = TH,
        w = SW, h = SH - TH,
        color = CBG,
        scrollable = true,
    })

    local dc = airui.container({
        parent = sc,
        x = MG, y = math.floor(10 * _G.density_scale),
        w = SW - 2 * MG, h = math.floor(440 * _G.density_scale),
        color = CCD, radius = 8,
    })

    airui.label({
        parent = dc,
        text = "网络详情",
        x = math.floor(10 * _G.density_scale), y = math.floor(15 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(20 * _G.density_scale),
        font_size = math.floor(22 * _G.density_scale),
        color = CTX,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.button({
        parent = dc,
        x = SW - 2 * MG - math.floor(20 * _G.density_scale) - math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(60 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "刷新",
        style = {
            bg_color = CPR, bg_opa = 255,
            text_color = CWH,
            pressed_bg_color = CPD,
            pressed_text_color = CWH,
        },
        on_click = function()
            sys.publish("WIFI_GET_STATUS_REQ")
            local ms = airui.msgbox({
                text = "刷新成功",
                buttons = { "确定" },
                on_action = function(sl) sl:hide() end
            })
            ms:show()
        end
    })

    local function crdr(pr, y, lt, vk)
        local rw = airui.container({
            parent = pr,
            x = math.floor(10 * _G.density_scale), y = y,
            w = SW - 2 * MG - math.floor(20 * _G.density_scale),
            h = math.floor(50 * _G.density_scale),
            color = CCD, radius = 4,
        })
        airui.label({
            parent = rw,
            text = lt,
            x = 0, y = math.floor(15 * _G.density_scale),
            w = math.floor(120 * _G.density_scale), h = math.floor(25 * _G.density_scale),
            font_size = math.floor(20 * _G.density_scale),
            color = CTX,
            align = airui.TEXT_ALIGN_LEFT,
        })
        local vl = airui.label({
            parent = rw,
            text = "--",
            x = math.floor(130 * _G.density_scale), y = math.floor(15 * _G.density_scale),
            w = (SW - 2 * MG - math.floor(20 * _G.density_scale)) - math.floor(130 * _G.density_scale) - math.floor(5 * _G.density_scale),
            h = math.floor(25 * _G.density_scale),
            font_size = math.floor(20 * _G.density_scale),
            color = CTX,
            align = airui.TEXT_ALIGN_RIGHT,
        })
        lbs[vk] = vl
    end

    local yo = math.floor(50 * _G.density_scale)
    crdr(dc, yo, "SSID", "ssid")
    yo = yo + math.floor(55 * _G.density_scale)
    crdr(dc, yo, "信号强度", "rssi")
    yo = yo + math.floor(55 * _G.density_scale)
    crdr(dc, yo, "IP地址", "ip")
    yo = yo + math.floor(55 * _G.density_scale)
    crdr(dc, yo, "子网掩码", "netmask")
    yo = yo + math.floor(55 * _G.density_scale)
    crdr(dc, yo, "网关", "gateway")
    yo = yo + math.floor(55 * _G.density_scale)
    crdr(dc, yo, "MAC地址", "bssid")
    yo = yo + math.floor(55 * _G.density_scale)

    local pwr = airui.container({
        parent = dc,
        x = math.floor(10 * _G.density_scale), y = yo,
        w = SW - 2 * MG - math.floor(20 * _G.density_scale),
        h = math.floor(50 * _G.density_scale),
        color = CCD, radius = 4,
    })
    airui.label({
        parent = pwr,
        text = "密码",
        x = 0, y = math.floor(15 * _G.density_scale),
        w = math.floor(120 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = CTX,
        align = airui.TEXT_ALIGN_LEFT,
    })
    lbs.password = airui.label({
        parent = pwr,
        text = "",
        x = math.floor(130 * _G.density_scale), y = math.floor(15 * _G.density_scale),
        w = (SW - 2 * MG - math.floor(20 * _G.density_scale)) - math.floor(130 * _G.density_scale) - math.floor(5 * _G.density_scale),
        h = math.floor(25 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = CTX,
        align = airui.TEXT_ALIGN_RIGHT,
        on_click = function()
            pv = not pv
            if cc then
                local pw = cc.password or ""
                if pv then
                    lbs.password:set_text(pw)
                else
                    lbs.password:set_text(string.rep("*", #pw))
                end
            end
        end
    })

    airui.button({
        parent = sc,
        x = MG, y = math.floor(470 * _G.density_scale),
        w = SW - 2 * MG, h = BH,
        text = "断开连接",
        style = {
            bg_color = CDG, bg_opa = 255,
            text_color = CWH,
            pressed_bg_color = CDG,
            pressed_text_color = CWH,
        },
        on_click = function()
            local ms = airui.msgbox({
                text = "确定要断开WiFi连接吗？",
                buttons = { "取消", "确定" },
                on_action = function(sl, lb)
                    if lb == "确定" then
                        sys.publish("WIFI_DISCONNECT_REQ")
                        sl:hide()
                        exwin.close(wid)
                    else
                        sl:hide()
                    end
                end
            })
            ms:show()
        end
    })
end

local function onst(st)
    log.info("wfdw", "WiFi状态更新:", json.encode(st))
    cs = st
    updi()
end

local function oncf(dt)
    cc = dt.config
    log.info("wfdw", "配置加载完成:", json.encode(cc))
    updi()
end

local function onc()
    dcui()
    sys.publish("WIFI_GET_STATUS_REQ")
    sys.publish("WIFI_GET_CONFIG_REQ")
    sys.subscribe("WIFI_STATUS_UPDATED", onst)
    sys.subscribe("WIFI_CONFIG_RSP", oncf)
end

local function ond()
    sys.unsubscribe("WIFI_STATUS_UPDATED", onst)
    sys.unsubscribe("WIFI_CONFIG_RSP", oncf)
    if mc then
        mc:destroy()
        mc = nil
    end
    lbs = {}
    wid = nil
    pv = false
end

local function onf() end
local function onlf() end

local function opn()
    if not exwin.is_active(wid) then
        wid = exwin.open({
            on_create = onc,
            on_destroy = ond,
            on_get_focus = onf,
            on_lose_focus = onlf,
        })
    end
end

sys.subscribe("OPEN_WIFI_DETAIL_WIN", opn)
