--[[
@module  wifi_list_win
@summary WiFi列表窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
@author  江访
]]

require "wifi_connect_win"
require "wifi_detail_win"

local SCREEN_W, SCREEN_H = 480, 800
local MARGIN = 15
local TITLE_H = math.floor(60 * (_G.density_scale or 1.0))
local CARD_H = 60

local COLOR_PRIMARY  = 0x007AFF
local COLOR_PRIMARY_DARK = 0x0056B3
local COLOR_BG = 0xF5F5F5
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x333333
local COLOR_SECONDARY = 0x757575
local COLOR_DIVIDER = 0xE0E0E0
local COLOR_WHITE = 0xFFFFFF
local COLOR_ACCENT = 0xFF9800

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        SCREEN_W, SCREEN_H = phys_w, phys_h
    else
        SCREEN_W, SCREEN_H = phys_h, phys_w
    end
    MARGIN = math.floor(SCREEN_W * 0.03)
    TITLE_H = math.floor(60 * _G.density_scale)
    CARD_H = math.floor(SCREEN_H * 0.09)
end

local window_id = nil
local main_container = nil
local lcci = nil
local wifi_list_container = nil
local saved_list_container = nil
local wifi_items = {}
local llc = nil
local connecting_container = nil
local wifi_switch = nil
local switch_container = nil
local programmatic_switch = false

local saved_network_list = {}
local saved_network_items = {}
local current_scan_results = {}

local scanning_indicator = nil
local scan_refresh_btn = nil

local function show_scanning()
    if scan_refresh_btn then scan_refresh_btn:hide() end
    if scanning_indicator then scanning_indicator:open() end
end

local function hide_scanning()
    if scanning_indicator then scanning_indicator:hide() end
    if scan_refresh_btn then scan_refresh_btn:open() end
end

local wifi_config = {
    wifi_enabled = false, ssid = "", password = "",
    need_ping = true, local_network_mode = false,
    ping_ip = "", ping_time = "10000", auto_socket_switch = true
}
local wifi_status = {
    connected = false, ready = false, current_ssid = "",
    rssi = "--", ip = "--", netmask = "--", gateway = "--", bssid = "--",
    scan_results = {}
}

local function create_wifi_item(wifi_entry, index)
    local signal_pct = math.min(100, math.max(0, (wifi_entry.rssi or -100) + 100))
    local item_w = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale)
    local is_connected = wifi_status and wifi_status.current_ssid == wifi_entry.ssid
    local item = airui.container({
        parent = wifi_list_container,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale) + (index - 1) * math.floor(75 * _G.density_scale),
        w = item_w, h = math.floor(65 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
        on_click = function()
            if is_connected then
                sys.publish("OPEN_WIFI_DETAIL_WIN")
            else
                sys.publish("OPEN_WIFI_CONNECT_WIN", wifi_entry.ssid)
            end
        end
    })
    airui.label({
        parent = item,
        text = wifi_entry.ssid or "未知",
        x = math.floor(10 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = item_w - math.floor(80 * _G.density_scale), h = math.floor(20 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = item,
        text = string.format("%d%%", signal_pct),
        x = math.floor(10 * _G.density_scale), y = math.floor(36 * _G.density_scale),
        w = item_w - math.floor(80 * _G.density_scale), h = math.floor(15 * _G.density_scale),
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })
    if is_connected then
        airui.label({
            parent = item,
            x = item_w - math.floor(80 * _G.density_scale), y = math.floor(17 * _G.density_scale),
            w = math.floor(70 * _G.density_scale), h = math.floor(30 * _G.density_scale),
            text = "已连接",
            font_size = math.floor(16 * _G.density_scale),
            color = 0x4CAF50,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
    table.insert(wifi_items, item)
end

local function create_saved_item(saved_wifi, index, stx)
    local item_w = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale)
    local item = airui.container({
        parent = saved_list_container,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale) + (index - 1) * math.floor(60 * _G.density_scale),
        w = item_w, h = math.floor(50 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
        on_click = function()
            if stx == "已连接" then
                sys.publish("OPEN_WIFI_DETAIL_WIN")
            else
                sys.publish("OPEN_WIFI_CONNECT_WIN", saved_wifi, false)
            end
        end
    })
    airui.label({
        parent = item,
        text = saved_wifi.ssid or "未知",
        x = math.floor(10 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = item_w - math.floor(140 * _G.density_scale), h = math.floor(22 * _G.density_scale),
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local status_color = stx == "已连接" and 0x4CAF50 or (stx == "已配置" and COLOR_ACCENT or COLOR_PRIMARY)
    airui.label({
        parent = item,
        text = stx,
        x = item_w - math.floor(130 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(120 * _G.density_scale), h = math.floor(24 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = status_color,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    table.insert(saved_network_items, item)
end

local function update_saved_list()
    for _, item in ipairs(saved_network_items) do item:destroy() end
    saved_network_items = {}
    if not saved_list_container then return end
    if not wifi_config or not wifi_config.wifi_enabled then return end

    local matched_list = {}
    local connected_ssid = wifi_status and wifi_status.current_ssid or ""
    for _, saved_wifi in ipairs(saved_network_list) do
        local status_color = false
        local is_connected = (saved_wifi.ssid == connected_ssid)
        for _, saved_config_wifi in ipairs(current_scan_results) do
            if saved_config_wifi.ssid == saved_wifi.ssid then status_color = true; break end
        end
        if status_color or is_connected then
            table.insert(matched_list, {
                wifi = saved_wifi,
                status = is_connected and "已连接" or "可连接",
                is_connected = is_connected
            })
        end
    end
    table.sort(matched_list, function(a,b)
        if a.is_connected and not b.is_connected then return true end
        if not a.is_connected and b.is_connected then return false end
        return a.wifi.ssid < b.wifi.ssid
    end)
    for i, item in ipairs(matched_list) do
        create_saved_item(item.wifi, i, item.status)
    end
end

local function update_wifi_list(scan_results)
    for _, item in ipairs(wifi_items) do item:destroy() end
    wifi_items = {}
    if scan_results and #scan_results > 0 then
        for i, wifi_entry in ipairs(scan_results) do
            create_wifi_item(wifi_entry, i)
        end
    end
end

local function on_wifi_toggle(checked)
    if programmatic_switch then return end
    sys.publish("WIFI_ENABLE_REQ", {enabled = checked})
    if checked then
        sys.publish("WIFI_SCAN_REQ")
    else
        update_wifi_list({})
    end
end

local function build_ui()
    update_screen_size()
    main_container = airui.container({
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H,
        color = COLOR_BG,
    })

    local tb = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = SCREEN_W, h = TITLE_H,
        color = COLOR_PRIMARY,
    })
    local bb = airui.container({
        parent = tb,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(window_id) end
    })
    airui.label({
        parent = bb,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = tb,
        text = "WiFi 网络配置",
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = SCREEN_W - math.floor(60 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local scr = airui.container({
        parent = main_container,
        x = 0, y = TITLE_H,
        w = SCREEN_W, h = SCREEN_H - TITLE_H,
        color = COLOR_BG,
        scrollable = true,
    })

    -- WiFi开关卡片（紧凑布局）
    local wec = airui.container({
        parent = scr,
        x = MARGIN, y = math.floor(10 * _G.density_scale),
        w = SCREEN_W - 2 * MARGIN, h = math.floor(50 * _G.density_scale),
        color = COLOR_WHITE, radius = 8,
    })
    local ch = math.floor(50 * _G.density_scale)
    airui.label({
        parent = wec,
        text = "WiFi",
        x = math.floor(10 * _G.density_scale), y = math.floor((ch - 30 * _G.density_scale) / 2),
        w = math.floor(80 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    switch_container = airui.container({
        parent = wec,
        x = SCREEN_W - 2 * MARGIN - math.floor(80 * _G.density_scale), y = math.floor((ch - 29 * _G.density_scale) / 2),
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
    })
    switch_container:hide()
    wifi_switch = airui.switch({
        parent = switch_container,
        x = 0, y = 0,
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
        checked = false,
        on_change = function(self)
            sys.taskInit(function() on_wifi_toggle(self:get_state()) end)
        end
    })

    -- 已保存wifi
    local sty = math.floor(10 * _G.density_scale) + ch + math.floor(15 * _G.density_scale)
    airui.label({
        parent = scr,
        text = "已保存wifi",
        x = MARGIN + math.floor(5 * _G.density_scale), y = sty,
        w = math.floor(150 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 已保存wifi 容器
    local sy = sty + math.floor(28 * _G.density_scale)
    local status_color = airui.container({
        parent = scr,
        x = MARGIN, y = sy,
        w = SCREEN_W - 2 * MARGIN, h = math.floor(190 * _G.density_scale),
        color = COLOR_WHITE, radius = 8,
    })
    saved_list_container = airui.container({
        parent = status_color,
        x = 0, y = 0,
        w = SCREEN_W - 2 * MARGIN, h = math.floor(190 * _G.density_scale),
        color = COLOR_WHITE,
    })

    -- 附近的wifi
    local scy = sy + math.floor(190 * _G.density_scale) + math.floor(20 * _G.density_scale)
    airui.label({
        parent = scr,
        text = "附近的wifi",
        x = MARGIN + math.floor(5 * _G.density_scale), y = scy,
        w = math.floor(150 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })

    scan_refresh_btn = airui.container({
        parent = scr,
        x = SCREEN_W - 2 * MARGIN - math.floor(60 * _G.density_scale), y = scy,
        w = math.floor(60 * _G.density_scale), h = math.floor(25 * _G.density_scale),
    })
    airui.button({
        parent = scan_refresh_btn,
        x = 0, y = 0,
        w = math.floor(60 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        text = "刷新",
        font_size = math.floor(16 * _G.density_scale),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE },
        on_click = function()
            if wifi_config and wifi_config.wifi_enabled then
                sys.publish("WIFI_SCAN_REQ")
            else
                airui.msgbox({ text = "请先开启WiFi", buttons = { "确定" }, on_action = function(s) s:hide() end }):show()
            end
        end
    })

    scanning_indicator = airui.container({
        parent = scr,
        x = SCREEN_W - 2 * MARGIN - math.floor(130 * _G.density_scale), y = scy,
        w = math.floor(130 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        color = COLOR_BG,
    })
    scanning_indicator:hide()

    local lcy = scy + math.floor(35 * _G.density_scale)
    local wlc = airui.container({
        parent = scr,
        x = MARGIN, y = lcy,
        w = SCREEN_W - 2 * MARGIN, h = math.floor(320 * _G.density_scale),
        color = COLOR_WHITE, radius = 8,
    })
    wifi_list_container = airui.container({
        parent = wlc,
        x = 0, y = 0,
        w = SCREEN_W - 2 * MARGIN, h = math.floor(320 * _G.density_scale),
        color = COLOR_WHITE,
    })
end

local function on_scan_start()
    log.info("wifi_list", "扫描开始")
    show_scanning()
end

local function on_scan_done(scan_results)
    log.info("wifi_list", "扫描完成，找到", #scan_results, "个热点")
    hide_scanning()
    current_scan_results = scan_results or {}
    update_wifi_list(scan_results)
    update_saved_list()
end

local function on_scan_timeout()
    log.warn("wifi_list", "扫描超时")
    hide_scanning()
    airui.msgbox({ text = "扫描超时，未找到WiFi热点", buttons = { "确定" }, on_action = function(s) s:hide() end }):show()
end

local function on_connecting(sid)
    log.info("wifi_list", "正在连接:", sid)
    if connecting_container then connecting_container:open() end
end

local function on_connected(sid)
    log.info("wifi_list", "连接成功:", sid)
    if connecting_container then connecting_container:hide() end
    update_saved_list()
    update_wifi_list(current_scan_results)
    airui.msgbox({ text = "WiFi 连接成功", buttons = { "确定" }, timeout = 3000, on_action = function(s) s:destroy() end })
end

local function on_disconnected(scan_results, code)
    log.error("wifi_list", "连接失败:", scan_results, code)
    if connecting_container then connecting_container:hide() end
    airui.msgbox({ text = "WiFi 连接失败: " .. scan_results, buttons = { "确定" }, timeout = 3000, on_action = function(s) s:destroy() end })
    update_saved_list()
    update_wifi_list({})
end

local function on_status_update(status)
    log.info("wifi_list", "WiFi状态更新:", json.encode(status))
    wifi_status = status
    if wifi_config then
        if not wifi_config.wifi_enabled and not status.connected then
            update_wifi_list({})
        end
        update_saved_list()
    end
end

local function on_saved_list_rsp(data)
    log.info("wifi_list", "收到已保存网络列表:", #data.list)
    saved_network_list = data.list or {}
    update_saved_list()
end

local function on_config_rsp(data)
    local old_enabled = wifi_config and wifi_config.wifi_enabled
    wifi_config = data.config
    log.info("wifi_list", "配置加载完成, enabled:", wifi_config.wifi_enabled)
    if wifi_switch and (old_enabled == nil or old_enabled ~= wifi_config.wifi_enabled) then
        programmatic_switch = true
        wifi_switch:set_state(wifi_config.wifi_enabled)
        programmatic_switch = false
    end
    if switch_container then switch_container:open() end
    if wifi_status then on_status_update(wifi_status) end
    update_saved_list()
    if wifi_config and wifi_config.wifi_enabled then
        sys.publish("WIFI_SCAN_REQ")
    end
end

local function on_create()
    build_ui()
    sys.publish("WIFI_GET_STATUS_REQ")
    sys.publish("WIFI_GET_CONFIG_REQ")
    sys.publish("WIFI_GET_SAVED_LIST_REQ")
    sys.subscribe("WIFI_SCAN_STARTED", on_scan_start)
    sys.subscribe("WIFI_SCAN_DONE", on_scan_done)
    sys.subscribe("WIFI_SCAN_TIMEOUT", on_scan_timeout)
    sys.subscribe("WIFI_CONNECTING", on_connecting)
    sys.subscribe("WIFI_CONNECTED", on_connected)
    sys.subscribe("WIFI_DISCONNECTED", on_disconnected)
    sys.subscribe("WIFI_STATUS_UPDATED", on_status_update)
    sys.subscribe("WIFI_CONFIG_RSP", on_config_rsp)
    sys.subscribe("WIFI_SAVED_LIST_RSP", on_saved_list_rsp)
end

local function on_destroy()
    sys.unsubscribe("WIFI_SCAN_STARTED", on_scan_start)
    sys.unsubscribe("WIFI_SCAN_DONE", on_scan_done)
    sys.unsubscribe("WIFI_SCAN_TIMEOUT", on_scan_timeout)
    sys.unsubscribe("WIFI_CONNECTING", on_connecting)
    sys.unsubscribe("WIFI_CONNECTED", on_connected)
    sys.unsubscribe("WIFI_DISCONNECTED", on_disconnected)
    sys.unsubscribe("WIFI_STATUS_UPDATED", on_status_update)
    sys.unsubscribe("WIFI_CONFIG_RSP", on_config_rsp)
    sys.unsubscribe("WIFI_SAVED_LIST_RSP", on_saved_list_rsp)
    hide_scanning()
    if main_container then main_container:destroy(); main_container = nil end
    lcci = nil
    wifi_list_container = nil
    saved_list_container = nil
    wifi_items = {}
    llc = nil
    connecting_container = nil
    wifi_switch = nil
    switch_container = nil
    wifi_config = nil
    wifi_status = nil
    window_id = nil
    saved_network_list = {}
    saved_network_items = {}
    current_scan_results = {}
    scanning_indicator = nil
    scan_refresh_btn = nil
end

local function on_get_focus()
    sys.publish("WIFI_GET_STATUS_REQ")
    if wifi_config and wifi_config.wifi_enabled then
        sys.publish("WIFI_SCAN_REQ")
    end
end

local function on_lose_focus() end

local function open()
    if not exwin.is_active(window_id) then
        window_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("wifi_list", "WiFi列表窗口打开，ID:", window_id)
    end
end

sys.subscribe("OPEN_WIFI_WIN", open)
log.info("wifi_list", "订阅 OPEN_WIFI_WIN 消息")
