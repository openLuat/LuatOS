--[[
@module  wifi_list_win
@summary WiFi列表窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
]]

require "wifi_app"
require "wifi_connect_win"
require "wifi_detail_win"

local SCREEN_W, SCREEN_H = 480, 800
local MARGIN = 15
local TITLE_H = math.floor(60 * _G.density_scale)
local CARD_H = 60

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_ACCENT         = 0xFF9800

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

local list_win_id = nil
local list_main_container = nil
local list_current_connect_item = nil
local list_wifi_list_content = nil
local list_saved_networks_content = nil
local list_wifi_items = {}
local list_loading_container = nil
local list_connecting_container = nil
local wifi_enable_switch = nil
local wifi_enable_switch_container = nil
local is_programmatically_setting_switch = false

local saved_network_list = {}
local saved_network_items = {}
local current_scan_results = {}

local scan_indicator_container = nil
local scan_refresh_container = nil

local function scan_indicator_show()
    if scan_refresh_container then scan_refresh_container:hide() end
    if scan_indicator_container then scan_indicator_container:open() end
end

local function scan_indicator_hide()
    if scan_indicator_container then scan_indicator_container:hide() end
    if scan_refresh_container then scan_refresh_container:open() end
end

local current_config = {
    wifi_enabled = false, ssid = "", password = "",
    need_ping = true, local_network_mode = false,
    ping_ip = "", ping_time = "10000", auto_socket_switch = true
}
local current_status = {
    connected = false, ready = false, current_ssid = "",
    rssi = "--", ip = "--", netmask = "--", gateway = "--", bssid = "--",
    scan_results = {}
}

local function list_create_wifi_item(wifi, index)
    local signal = math.min(100, math.max(0, (wifi.rssi or -100) + 100))
    local item_w = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale)
    local is_connected = current_status and current_status.current_ssid == wifi.ssid
    local wifi_item = airui.container({
        parent = list_wifi_list_content,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale) + (index - 1) * math.floor(75 * _G.density_scale),
        w = item_w, h = math.floor(65 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
        on_click = function()
            if is_connected then
                sys.publish("OPEN_WIFI_DETAIL_WIN")
            else
                sys.publish("OPEN_WIFI_CONNECT_WIN", wifi.ssid)
            end
        end
    })
    airui.label({
        parent = wifi_item,
        text = wifi.ssid or "未知",
        x = math.floor(10 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = item_w - math.floor(80 * _G.density_scale), h = math.floor(20 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = wifi_item,
        text = string.format("%d%%", signal),
        x = math.floor(10 * _G.density_scale), y = math.floor(36 * _G.density_scale),
        w = item_w - math.floor(80 * _G.density_scale), h = math.floor(15 * _G.density_scale),
        font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })
    if is_connected then
        airui.label({
            parent = wifi_item,
            x = item_w - math.floor(80 * _G.density_scale), y = math.floor(17 * _G.density_scale),
            w = math.floor(70 * _G.density_scale), h = math.floor(30 * _G.density_scale),
            text = "已连接",
            font_size = math.floor(16 * _G.density_scale),
            color = 0x4CAF50,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
    table.insert(list_wifi_items, wifi_item)
end

local function list_create_saved_network_item(saved_wifi, index, status_text)
    local item_w = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale)
    local wifi_item = airui.container({
        parent = list_saved_networks_content,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale) + (index - 1) * math.floor(60 * _G.density_scale),
        w = item_w, h = math.floor(50 * _G.density_scale),
        color = COLOR_CARD, radius = 4,
        on_click = function()
            if status_text == "已连接" then
                sys.publish("OPEN_WIFI_DETAIL_WIN")
            else
                sys.publish("OPEN_WIFI_CONNECT_WIN", saved_wifi, false)
            end
        end
    })
    airui.label({
        parent = wifi_item,
        text = saved_wifi.ssid or "未知",
        x = math.floor(10 * _G.density_scale), y = math.floor(8 * _G.density_scale),
        w = item_w - math.floor(140 * _G.density_scale), h = math.floor(22 * _G.density_scale),
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local status_color = status_text == "已连接" and 0x4CAF50 or (status_text == "已配置" and COLOR_ACCENT or COLOR_PRIMARY)
    airui.label({
        parent = wifi_item,
        text = status_text,
        x = item_w - math.floor(130 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(120 * _G.density_scale), h = math.floor(24 * _G.density_scale),
        font_size = math.floor(20 * _G.density_scale),
        color = status_color,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    table.insert(saved_network_items, wifi_item)
end

local function list_update_saved_networks_list()
    for _, item in ipairs(saved_network_items) do item:destroy() end
    saved_network_items = {}
    if not list_saved_networks_content then return end
    if not current_config or not current_config.wifi_enabled then return end

    local matched_saved_networks = {}
    local connected_ssid = current_status and current_status.current_ssid or ""
    for _, saved_wifi in ipairs(saved_network_list) do
        local is_scanned = false
        local is_connected = (saved_wifi.ssid == connected_ssid)
        for _, scan_wifi in ipairs(current_scan_results) do
            if scan_wifi.ssid == saved_wifi.ssid then is_scanned = true; break end
        end
        if is_scanned or is_connected then
            table.insert(matched_saved_networks, {
                wifi = saved_wifi,
                status = is_connected and "已连接" or "可连接",
                is_connected = is_connected
            })
        end
    end
    table.sort(matched_saved_networks, function(a,b)
        if a.is_connected and not b.is_connected then return true end
        if not a.is_connected and b.is_connected then return false end
        return a.wifi.ssid < b.wifi.ssid
    end)
    for i, item in ipairs(matched_saved_networks) do
        list_create_saved_network_item(item.wifi, i, item.status)
    end
end

local function list_update_wifi_list(results)
    for _, item in ipairs(list_wifi_items) do item:destroy() end
    list_wifi_items = {}
    if results and #results > 0 then
        for i, wifi in ipairs(results) do
            list_create_wifi_item(wifi, i)
        end
    end
end

local function list_on_wifi_enable_change(checked)
    if is_programmatically_setting_switch then return end
    sys.publish("WIFI_ENABLE_REQ", {enabled = checked})
    if checked then
        sys.publish("WIFI_SCAN_REQ")
    else
        list_update_wifi_list({})
    end
end

local function list_create_ui()
    update_screen_size()
    list_main_container = airui.container({
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H,
        color = COLOR_BG,
    })

    local title_bar = airui.container({
        parent = list_main_container,
        x = 0, y = 0,
        w = SCREEN_W, h = TITLE_H,
        color = COLOR_PRIMARY,
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(list_win_id) end
    })
    airui.label({
        parent = btn_back,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        text = "WiFi 网络配置",
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = SCREEN_W - math.floor(60 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local list_scroll_container = airui.container({
        parent = list_main_container,
        x = 0, y = TITLE_H,
        w = SCREEN_W, h = SCREEN_H - TITLE_H,
        color = COLOR_BG,
        scrollable = true,
    })

    -- WiFi开关卡片（紧凑布局）
    local wifi_enable_card = airui.container({
        parent = list_scroll_container,
        x = MARGIN, y = math.floor(10 * _G.density_scale),
        w = SCREEN_W - 2 * MARGIN, h = math.floor(50 * _G.density_scale),
        color = COLOR_WHITE, radius = 8,
    })
    local card_h = math.floor(50 * _G.density_scale)
    airui.label({
        parent = wifi_enable_card,
        text = "WiFi",
        x = math.floor(10 * _G.density_scale), y = math.floor((card_h - 30 * _G.density_scale) / 2),
        w = math.floor(80 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    wifi_enable_switch_container = airui.container({
        parent = wifi_enable_card,
        x = SCREEN_W - 2 * MARGIN - math.floor(80 * _G.density_scale), y = math.floor((card_h - 29 * _G.density_scale) / 2),
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
    })
    wifi_enable_switch_container:hide()
    wifi_enable_switch = airui.switch({
        parent = wifi_enable_switch_container,
        x = 0, y = 0,
        w = math.floor(70 * _G.density_scale), h = math.floor(29 * _G.density_scale),
        checked = false,
        on_change = function(self)
            sys.taskInit(function() list_on_wifi_enable_change(self:get_state()) end)
        end
    })

    -- 已保存wifi
    local saved_title_y = math.floor(10 * _G.density_scale) + card_h + math.floor(15 * _G.density_scale)
    airui.label({
        parent = list_scroll_container,
        text = "已保存wifi",
        x = MARGIN + math.floor(5 * _G.density_scale), y = saved_title_y,
        w = math.floor(150 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 已保存wifi 容器
    local saved_y = saved_title_y + math.floor(28 * _G.density_scale)
    local saved_card = airui.container({
        parent = list_scroll_container,
        x = MARGIN, y = saved_y,
        w = SCREEN_W - 2 * MARGIN, h = math.floor(190 * _G.density_scale),
        color = COLOR_WHITE, radius = 8,
    })
    list_saved_networks_content = airui.container({
        parent = saved_card,
        x = 0, y = 0,
        w = SCREEN_W - 2 * MARGIN, h = math.floor(190 * _G.density_scale),
        color = COLOR_WHITE,
    })

    -- 附近的wifi
    local scan_y = saved_y + math.floor(190 * _G.density_scale) + math.floor(20 * _G.density_scale)
    airui.label({
        parent = list_scroll_container,
        text = "附近的wifi",
        x = MARGIN + math.floor(5 * _G.density_scale), y = scan_y,
        w = math.floor(150 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })

    scan_refresh_container = airui.container({
        parent = list_scroll_container,
        x = SCREEN_W - 2 * MARGIN - math.floor(60 * _G.density_scale), y = scan_y,
        w = math.floor(60 * _G.density_scale), h = math.floor(25 * _G.density_scale),
    })
    airui.button({
        parent = scan_refresh_container,
        x = 0, y = 0,
        w = math.floor(60 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        text = "刷新",
        font_size = math.floor(16 * _G.density_scale),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE },
        on_click = function()
            if current_config and current_config.wifi_enabled then
                sys.publish("WIFI_SCAN_REQ")
            else
                airui.msgbox({ text = "请先开启WiFi", buttons = { "确定" }, on_action = function(s) s:hide() end }):show()
            end
        end
    })

    scan_indicator_container = airui.container({
        parent = list_scroll_container,
        x = SCREEN_W - 2 * MARGIN - math.floor(130 * _G.density_scale), y = scan_y,
        w = math.floor(130 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        color = COLOR_BG,
    })
    scan_indicator_container:hide()

    local list_card_y = scan_y + math.floor(35 * _G.density_scale)
    local wifi_list_card = airui.container({
        parent = list_scroll_container,
        x = MARGIN, y = list_card_y,
        w = SCREEN_W - 2 * MARGIN, h = math.floor(320 * _G.density_scale),
        color = COLOR_WHITE, radius = 8,
    })
    list_wifi_list_content = airui.container({
        parent = wifi_list_card,
        x = 0, y = 0,
        w = SCREEN_W - 2 * MARGIN, h = math.floor(320 * _G.density_scale),
        color = COLOR_WHITE,
    })
end

local function list_on_scan_started()
    log.info("wifi_list_win", "扫描开始")
    scan_indicator_show()
end

local function list_on_scan_done(results)
    log.info("wifi_list_win", "扫描完成，找到", #results, "个热点")
    scan_indicator_hide()
    current_scan_results = results or {}
    list_update_wifi_list(results)
    list_update_saved_networks_list()
end

local function list_on_scan_timeout()
    log.warn("wifi_list_win", "扫描超时")
    scan_indicator_hide()
    airui.msgbox({ text = "扫描超时，未找到WiFi热点", buttons = { "确定" }, on_action = function(s) s:hide() end }):show()
end

local function list_on_connecting(ssid)
    log.info("wifi_list_win", "正在连接:", ssid)
    if list_connecting_container then list_connecting_container:open() end
end

local function list_on_connected(ssid)
    log.info("wifi_list_win", "连接成功:", ssid)
    if list_connecting_container then list_connecting_container:hide() end
    list_update_saved_networks_list()
    list_update_wifi_list(current_scan_results)
    airui.msgbox({ text = "WiFi 连接成功", buttons = { "确定" }, timeout = 3000, on_action = function(s) s:destroy() end })
end

local function list_on_disconnected(reason, code)
    log.error("wifi_list_win", "连接失败:", reason, code)
    if list_connecting_container then list_connecting_container:hide() end
    airui.msgbox({ text = "WiFi 连接失败: " .. reason, buttons = { "确定" }, timeout = 3000, on_action = function(s) s:destroy() end })
    list_update_saved_networks_list()
    list_update_wifi_list({})
end

local function list_on_status_updated(status)
    log.info("wifi_list_win", "WiFi状态更新:", json.encode(status))
    current_status = status
    if current_config then
        if not current_config.wifi_enabled and not status.connected then
            list_update_wifi_list({})
        end
        list_update_saved_networks_list()
    end
end

local function list_on_saved_list_rsp(data)
    log.info("wifi_list_win", "收到已保存网络列表:", #data.list)
    saved_network_list = data.list or {}
    list_update_saved_networks_list()
end

local function list_on_config_rsp(data)
    local old_enabled = current_config and current_config.wifi_enabled
    current_config = data.config
    log.info("wifi_list_win", "配置加载完成, enabled:", current_config.wifi_enabled)
    if wifi_enable_switch and (old_enabled == nil or old_enabled ~= current_config.wifi_enabled) then
        is_programmatically_setting_switch = true
        wifi_enable_switch:set_state(current_config.wifi_enabled)
        is_programmatically_setting_switch = false
    end
    if wifi_enable_switch_container then wifi_enable_switch_container:open() end
    if current_status then list_on_status_updated(current_status) end
    list_update_saved_networks_list()
    if current_config and current_config.wifi_enabled then
        sys.publish("WIFI_SCAN_REQ")
    end
end

local function list_on_create()
    log.info("wifi_list_win", "WiFi列表窗口创建")
    list_create_ui()
    sys.publish("WIFI_GET_STATUS_REQ")
    sys.publish("WIFI_GET_CONFIG_REQ")
    sys.publish("WIFI_GET_SAVED_LIST_REQ")
    sys.subscribe("WIFI_SCAN_STARTED", list_on_scan_started)
    sys.subscribe("WIFI_SCAN_DONE", list_on_scan_done)
    sys.subscribe("WIFI_SCAN_TIMEOUT", list_on_scan_timeout)
    sys.subscribe("WIFI_CONNECTING", list_on_connecting)
    sys.subscribe("WIFI_CONNECTED", list_on_connected)
    sys.subscribe("WIFI_DISCONNECTED", list_on_disconnected)
    sys.subscribe("WIFI_STATUS_UPDATED", list_on_status_updated)
    sys.subscribe("WIFI_CONFIG_RSP", list_on_config_rsp)
    sys.subscribe("WIFI_SAVED_LIST_RSP", list_on_saved_list_rsp)
end

local function list_on_destroy()
    log.info("wifi_list_win", "WiFi列表窗口销毁")
    sys.unsubscribe("WIFI_SCAN_STARTED", list_on_scan_started)
    sys.unsubscribe("WIFI_SCAN_DONE", list_on_scan_done)
    sys.unsubscribe("WIFI_SCAN_TIMEOUT", list_on_scan_timeout)
    sys.unsubscribe("WIFI_CONNECTING", list_on_connecting)
    sys.unsubscribe("WIFI_CONNECTED", list_on_connected)
    sys.unsubscribe("WIFI_DISCONNECTED", list_on_disconnected)
    sys.unsubscribe("WIFI_STATUS_UPDATED", list_on_status_updated)
    sys.unsubscribe("WIFI_CONFIG_RSP", list_on_config_rsp)
    sys.unsubscribe("WIFI_SAVED_LIST_RSP", list_on_saved_list_rsp)
    scan_indicator_hide()
    if list_main_container then list_main_container:destroy(); list_main_container = nil end
    list_current_connect_item = nil
    list_wifi_list_content = nil
    list_saved_networks_content = nil
    list_wifi_items = {}
    list_loading_container = nil
    list_connecting_container = nil
    wifi_enable_switch = nil
    wifi_enable_switch_container = nil
    current_config = nil
    current_status = nil
    list_win_id = nil
    saved_network_list = {}
    saved_network_items = {}
    current_scan_results = {}
    scan_indicator_container = nil
    scan_refresh_container = nil
end

local function list_on_get_focus()
    log.info("wifi_list_win", "WiFi列表窗口获得焦点")
    sys.publish("WIFI_GET_STATUS_REQ")
    if current_config and current_config.wifi_enabled then
        sys.publish("WIFI_SCAN_REQ")
    end
end

local function list_on_lose_focus() end

local function open()
    if not exwin.is_active(list_win_id) then
        list_win_id = exwin.open({
            on_create = list_on_create,
            on_destroy = list_on_destroy,
            on_get_focus = list_on_get_focus,
            on_lose_focus = list_on_lose_focus,
        })
        log.info("wifi_list_win", "WiFi列表窗口打开，ID:", list_win_id)
    end
end

sys.subscribe("OPEN_WIFI_WIN", open)
log.info("wifi_list_win", "订阅 OPEN_WIFI_WIN 消息")
