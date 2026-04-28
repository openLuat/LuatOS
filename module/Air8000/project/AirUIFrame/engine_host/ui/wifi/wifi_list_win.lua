--[[
@module  wifi_list_win
@summary WiFi列表窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
]]

require "wifi_app"
require "wifi_connect_win"
require "wifi_detail_win"
require "wifi_saved_list_win"

local SCREEN_W, SCREEN_H = 480, 800
local MARGIN = 15
local TITLE_H = 60
local CARD_H = 60

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        SCREEN_W, SCREEN_H = phys_w, phys_h
    else
        SCREEN_W, SCREEN_H = phys_h, phys_w
    end
    MARGIN = math.floor(SCREEN_W * 0.03)
    TITLE_H = 60
    CARD_H = math.floor(SCREEN_H * 0.09)
end

local list_win_id = nil
local list_main_container = nil
local list_current_connect_item = nil
local list_wifi_list_content = nil
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
local scan_indicator_image = nil
local scan_refresh_container = nil
local scan_rotation_running = false

local function scan_indicator_show()
    if scan_refresh_container then scan_refresh_container:hide() end
    if scan_indicator_container then scan_indicator_container:open() end
    scan_rotation_running = true
    sys.taskInit(function()
        local rotation = 0
        while scan_rotation_running and scan_indicator_image do
            rotation = (rotation + 300) % 3600
            scan_indicator_image:set_rotation(rotation)
            sys.wait(50)
        end
    end)
end

local function scan_indicator_hide()
    scan_rotation_running = false
    if scan_indicator_image then scan_indicator_image:set_rotation(0) end
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

local function list_clear_current_connect_item()
    if list_current_connect_item then
        list_current_connect_item:destroy()
        list_current_connect_item = nil
    end
end

local function list_create_wifi_item(wifi, index)
    local signal = math.min(100, math.max(0, (wifi.rssi or -100) + 100))
    local item_w = SCREEN_W - 2 * MARGIN - 20
    local wifi_item = airui.container({
        parent = list_wifi_list_content,
        x = 10, y = 10 + (index - 1) * 75,
        w = item_w, h = 65,
        color = 0xFAFAFA, radius = 4,
    })
    airui.label({
        parent = wifi_item,
        text = wifi.ssid or "未知",
        x = 10, y = 8,
        w = item_w - 80, h = 20,
        font_size = 20,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = wifi_item,
        text = string.format("%d%%", signal),
        x = 10, y = 36,
        w = item_w - 80, h = 15,
        font_size = 16,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.button({
        parent = wifi_item,
        x = item_w - 70, y = 17,
        w = 60, h = 30,
        text = "连接",
        on_click = function()
            sys.publish("OPEN_WIFI_CONNECT_WIN", wifi.ssid)
        end
    })
    table.insert(list_wifi_items, wifi_item)
end

local function list_create_saved_network_item(saved_wifi, index, status_text)
    local item_w = SCREEN_W - 2 * MARGIN - 20
    local wifi_item = airui.container({
        parent = list_saved_networks_content,
        x = 10, y = 10 + (index - 1) * 60,
        w = item_w, h = 50,
        color = 0xFAFAFA, radius = 4,
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
        x = 10, y = 8,
        w = item_w - 140, h = 22,
        font_size = 22,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local status_color = status_text == "已连接" and 0x4CAF50 or (status_text == "已配置" and 0xFF9800 or 0x2196F3)
    airui.label({
        parent = wifi_item,
        text = status_text,
        x = item_w - 130, y = 10,
        w = 120, h = 24,
        font_size = 20,
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
        list_clear_current_connect_item()
        list_update_wifi_list({})
    end
end

local list_saved_networks_content = nil

local function list_create_ui()
    update_screen_size()
    list_main_container = airui.container({
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H,
        color = 0xF0F0F0,
    })

    local title_bar = airui.container({
        parent = list_main_container,
        x = 0, y = 0,
        w = SCREEN_W, h = TITLE_H,
        color = 0x3F51B5,
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = 50, h = 40,
        color = 0x3F51B5,
        on_click = function() exwin.close(list_win_id) end
    })
    airui.label({
        parent = btn_back,
        x = 0, y = 5,
        w = 50, h = 30,
        text = "<",
        font_size = 28,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        text = "WiFi 网络配置",
        x = 60, y = 14,
        w = SCREEN_W -60, h = 40,
        font_size = 32,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local list_scroll_container = airui.container({
        parent = list_main_container,
        x = 0, y = TITLE_H,
        w = SCREEN_W, h = SCREEN_H - TITLE_H,
        color = 0xF0F0F0,
    })

    -- WiFi开关卡片
    local wifi_enable_card = airui.container({
        parent = list_scroll_container,
        x = MARGIN, y = 10,
        w = SCREEN_W - 2 * MARGIN, h = 60 + CARD_H,
        color = 0xFFFFFF, radius = 8,
    })
    airui.label({
        parent = wifi_enable_card,
        text = "WiFi",
        x = 10, y = 15,
        w = 80, h = 30,
        font_size = 24,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    wifi_enable_switch_container = airui.container({
        parent = wifi_enable_card,
        x = SCREEN_W - 2 * MARGIN - 80, y = 15,
        w = 70, h = 29,
    })
    wifi_enable_switch_container:hide()
    wifi_enable_switch = airui.switch({
        parent = wifi_enable_switch_container,
        x = 0, y = 0,
        w = 70, h = 29,
        checked = false,
        on_change = function(self)
            sys.taskInit(function() list_on_wifi_enable_change(self:get_state()) end)
        end
    })

    local saved_network_item = airui.container({
        parent = wifi_enable_card,
        x = 0, y = 60,
        w = SCREEN_W - 2 * MARGIN, h = CARD_H,
        color = 0xFFFFFF, radius = 0,
        on_click = function()
            sys.publish("OPEN_WIFI_SAVED_LIST_WIN")
        end
    })
    airui.label({
        parent = saved_network_item,
        text = "已保存的网络",
        x = 10, y = 15,
        w = 200, h = 40,
        font_size = 20,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = saved_network_item,
        text = ">",
        x = SCREEN_W - 2 * MARGIN - 40, y = 15,
        w = 30, h = 30,
        font_size = 24,
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 已保存网络列表标题
    airui.label({
        parent = list_scroll_container,
        text = "已保存网络",
        x = MARGIN + 5, y = 145,
        w = 200, h = 25,
        font_size = 18,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT,
    })

    local saved_networks_card = airui.container({
        parent = list_scroll_container,
        x = MARGIN, y = 175,
        w = SCREEN_W - 2 * MARGIN, h = 190,
        color = 0xFFFFFF, radius = 8,
    })
    list_saved_networks_content = airui.container({
        parent = saved_networks_card,
        x = 0, y = 0,
        w = SCREEN_W - 2 * MARGIN, h = 190,
        color = 0xFFFFFF,
    })

    -- WiFi列表标题
    airui.label({
        parent = list_scroll_container,
        text = "WiFi 列表",
        x = MARGIN + 5, y = 385,
        w = 200, h = 25,
        font_size = 18,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 刷新按钮区域
    scan_refresh_container = airui.container({
        parent = list_scroll_container,
        x = SCREEN_W - 2 * MARGIN - 60, y = 380,
        w = 60, h = 30,
    })
    airui.button({
        parent = scan_refresh_container,
        x = 0, y = 0,
        w = 60, h = 30,
        text = "刷新",
        style = {
            bg_color = 0xF0F0F0, border_color = 0xF0F0F0,
            text_color = 0x2196F3,
            pressed_bg_color = 0xEEEEEE, pressed_text_color = 0x2196F3,
        },
        on_click = function()
            if current_config and current_config.wifi_enabled then
                sys.publish("WIFI_SCAN_REQ")
            else
                local msg = airui.msgbox({
                    text = "请先开启WiFi",
                    buttons = { "确定" },
                    on_action = function(self) self:hide() end
                })
                msg:show()
            end
        end
    })

    scan_indicator_container = airui.container({
        parent = list_scroll_container,
        x = SCREEN_W - 2 * MARGIN - 120, y = 380,
        w = 200, h = 30,
        color = 0xF0F0F0,
    })
    scan_indicator_image = airui.image({
        parent = scan_indicator_container,
        x = 5, y = 0,
        w = 30, h = 30,
        src = airui.SYMBOL_REFRESH,
    })
    airui.label({
        parent = scan_indicator_container,
        text = "正在扫描...",
        x = 40, y = 5,
        w = 150, h = 20,
        font_size = 16,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT,
    })
    scan_indicator_container:hide()

    local wifi_list_card = airui.container({
        parent = list_scroll_container,
        x = MARGIN, y = 415,
        w = SCREEN_W - 2 * MARGIN, h = 320,
        color = 0xFFFFFF, radius = 8,
    })
    list_wifi_list_content = airui.container({
        parent = wifi_list_card,
        x = 0, y = 0,
        w = SCREEN_W - 2 * MARGIN, h = 320,
        color = 0xFFFFFF,
    })

    -- 加载提示
    list_loading_container = airui.container({
        parent = list_main_container,
        x = (SCREEN_W - 300) / 2, y = 130,
        w = 300, h = 130,
        color = 0x000000,
    })
    airui.label({
        parent = list_loading_container,
        text = "正在扫描 WiFi 热点",
        x = 0, y = 55,
        w = 300, h = 60,
        font_size = 20,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })
    list_loading_container:hide()

    list_connecting_container = airui.container({
        parent = list_main_container,
        x = (SCREEN_W - 300) / 2, y = 130,
        w = 300, h = 130,
        color = 0x000000,
    })
    airui.label({
        parent = list_connecting_container,
        text = "正在连接 WiFi",
        x = 0, y = 55,
        w = 300, h = 60,
        font_size = 20,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })
    list_connecting_container:hide()
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
    local msg = airui.msgbox({
        text = "扫描超时，未找到WiFi热点",
        buttons = { "确定" },
        on_action = function(self) self:hide() end
    })
    msg:show()
end

local function list_on_connecting(ssid)
    log.info("wifi_list_win", "正在连接:", ssid)
    if list_connecting_container then list_connecting_container:open() end
end

local function list_on_connected(ssid)
    log.info("wifi_list_win", "连接成功:", ssid)
    if list_connecting_container then list_connecting_container:hide() end
    list_update_saved_networks_list()
    airui.msgbox({
        text = "WiFi 连接成功",
        buttons = { "确定" },
        timeout = 3000,
        on_action = function(self) self:destroy() end
    })
end

local function list_on_disconnected(reason, code)
    log.error("wifi_list_win", "连接失败:", reason, code)
    if list_connecting_container then list_connecting_container:hide() end
    airui.msgbox({
        text = "WiFi 连接失败: " .. reason,
        buttons = { "确定" },
        timeout = 3000,
        on_action = function(self) self:destroy() end
    })
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
    if list_main_container then
        list_main_container:destroy()
        list_main_container = nil
    end
    list_current_connect_item = nil
    list_wifi_list_content = nil
    list_loading_container = nil
    list_connecting_container = nil
    list_wifi_items = {}
    wifi_enable_switch = nil
    wifi_enable_switch_container = nil
    current_config = nil
    current_status = nil
    list_win_id = nil
    list_saved_networks_content = nil
    saved_network_list = {}
    saved_network_items = {}
    current_scan_results = {}
    scan_indicator_container = nil
    scan_indicator_image = nil
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