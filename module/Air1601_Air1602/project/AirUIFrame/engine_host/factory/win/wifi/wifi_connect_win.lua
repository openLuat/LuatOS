--[[
@module  wifi_connect_win
@summary WiFi连接窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
]]

require "wifi_app"

local SCREEN_W, SCREEN_H = 480, 800
local MARGIN = 15
local TITLE_H = 50
local BUTTON_H = 50
local SPACING = 10

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        SCREEN_W, SCREEN_H = phys_w, phys_h
    else
        SCREEN_W, SCREEN_H = phys_h, phys_w
    end
    MARGIN = math.floor(SCREEN_W * 0.03)
    TITLE_H = math.floor(SCREEN_H * 0.0625)   -- 50/800
    BUTTON_H = math.floor(SCREEN_H * 0.0625)
    SPACING = math.floor(SCREEN_W * 0.02)
end

local connect_win_id = nil
local connect_main_container = nil
local connect_current_wifi = nil
local connect_wifi_keyboard = nil
local connect_password_textarea = nil
local connect_ping_time_input = nil
local connect_ping_ip_input = nil
local connect_advanced_config = nil
local connect_from_saved = false

local current_config = {
    wifi_enabled = false,
    ssid = "",
    password = "",
    need_ping = true,
    local_network_mode = false,
    ping_ip = "",
    ping_time = "10000",
    auto_socket_switch = true
}

local function connect_on_config_rsp(data)
    current_config = data.config
    log.info("wifi_connect_win", "配置加载完成:", json.encode(current_config))
    
    if connect_from_saved and connect_password_textarea and connect_current_wifi then
        if current_config.ssid == connect_current_wifi.ssid then
            connect_password_textarea:set_text(current_config.password or "")
            connect_advanced_config.need_ping = current_config.need_ping ~= nil and current_config.need_ping or true
            connect_advanced_config.local_network_mode = current_config.local_network_mode ~= nil and current_config.local_network_mode or false
            connect_advanced_config.ping_ip = current_config.ping_ip or ""
            connect_advanced_config.ping_time = current_config.ping_time or "10000"
            connect_advanced_config.auto_socket_switch = current_config.auto_socket_switch ~= nil and current_config.auto_socket_switch or true
        end
    end
end

local function connect_create_ui()
    update_screen_size()

    local config
    if connect_from_saved and connect_current_wifi then
        config = {
            need_ping = connect_current_wifi.need_ping ~= nil and connect_current_wifi.need_ping or true,
            local_network_mode = connect_current_wifi.local_network_mode ~= nil and connect_current_wifi.local_network_mode or false,
            ping_ip = connect_current_wifi.ping_ip or "",
            ping_time = connect_current_wifi.ping_time or "10000",
            auto_socket_switch = connect_current_wifi.auto_socket_switch ~= nil and connect_current_wifi.auto_socket_switch or true
        }
    elseif connect_from_saved and current_config then
        config = current_config
    else
        config = {
            need_ping = true,
            local_network_mode = false,
            ping_ip = "",
            ping_time = "10000",
            auto_socket_switch = true
        }
    end
    
    connect_advanced_config = {
        need_ping = config.need_ping,
        local_network_mode = config.local_network_mode,
        ping_ip = config.ping_ip,
        ping_time = config.ping_time,
        auto_socket_switch = config.auto_socket_switch
    }

    connect_main_container = airui.container({
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H,
        color = 0xF0F0F0,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = connect_main_container,
        x = 0, y = 0,
        w = SCREEN_W, h = TITLE_H,
        color = 0x1E88E5,
    })
    airui.button({
        parent = title_bar,
        x = 0, y = 10,
        w = 100, h = TITLE_H - 10,
        text = "< 返回",
        style = {
            bg_opa = 0, pressed_bg_opa = 0,
            text_color = 0xFFFFFF, pressed_text_color = 0xFFFFFF,
            border_color = 0x1E88E5,
        },
        on_click = function()
            exwin.close(connect_win_id)
        end
    })
    airui.label({
        parent = title_bar,
        text = connect_current_wifi and connect_current_wifi.ssid or "未知",
        x = 0, y = 15,
        w = SCREEN_W, h = 30,
        font_size = 24,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 键盘
    connect_wifi_keyboard = airui.keyboard({
        parent = connect_main_container,
        x = 0, y = 0,
        w = SCREEN_W, h = 200,
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    -- 可滚动内容容器
    local content_container = airui.container({
        parent = connect_main_container,
        x = 0, y = TITLE_H,
        w = SCREEN_W, h = SCREEN_H - TITLE_H - 80,
        color = 0xF0F0F0,
        scroll = true
    })

    -- 密码区域
    airui.label({
        parent = content_container,
        text = "WiFi 密码",
        x = MARGIN + 5, y = 10,
        w = 200, h = 25,
        font_size = 18,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local password_card = airui.container({
        parent = content_container,
        x = MARGIN, y = 40,
        w = SCREEN_W - 2 * MARGIN, h = 80,
        color = 0xFFFFFF, radius = 8,
    })
    connect_password_textarea = airui.textarea({
        parent = password_card,
        x = 10, y = 15,
        w = SCREEN_W - 2 * MARGIN - 20, h = 50,
        text = connect_current_wifi and connect_current_wifi.password or "",
        placeholder = "请输入WiFi密码",
        max_len = 64,
        font_size = 22,
        color = 0x000000,
        keyboard = connect_wifi_keyboard,
    })

    -- 高级配置
    airui.label({
        parent = content_container,
        text = "高级配置",
        x = MARGIN + 5, y = 130,
        w = 200, h = 25,
        font_size = 18,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local advanced_card = airui.container({
        parent = content_container,
        x = MARGIN, y = 160,
        w = SCREEN_W - 2 * MARGIN, h = 330,
        color = 0xFFFFFF, radius = 8,
    })

    local y_offset = 15
    local row_w = SCREEN_W - 2 * MARGIN - 20

    -- need_ping 开关行
    local need_ping_row = airui.container({
        parent = advanced_card,
        x = 10, y = y_offset,
        w = row_w, h = 45,
        color = 0xFAFAFA, radius = 4,
    })
    airui.label({
        parent = need_ping_row,
        text = "网络连通检测",
        x = 10, y = 10,
        w = 200, h = 25,
        font_size = 20,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.switch({
        parent = need_ping_row,
        x = row_w - 80, y = 8,
        w = 70, h = 29,
        checked = connect_advanced_config.need_ping,
        on_change = function(self)
            connect_advanced_config.need_ping = self:get_state()
        end
    })
    y_offset = y_offset + 55

    -- 局域网模式开关
    local local_network_mode_row = airui.container({
        parent = advanced_card,
        x = 10, y = y_offset,
        w = row_w, h = 45,
        color = 0xFAFAFA, radius = 4,
    })
    airui.label({
        parent = local_network_mode_row,
        text = "局域网模式",
        x = 10, y = 10,
        w = 200, h = 25,
        font_size = 20,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.switch({
        parent = local_network_mode_row,
        x = row_w - 80, y = 8,
        w = 70, h = 29,
        checked = connect_advanced_config.local_network_mode,
        on_change = function(self)
            connect_advanced_config.local_network_mode = self:get_state()
        end
    })
    y_offset = y_offset + 55

    -- 检测间隔输入
    local ping_time_row = airui.container({
        parent = advanced_card,
        x = 10, y = y_offset,
        w = row_w, h = 45,
        color = 0xFAFAFA, radius = 4,
    })
    airui.label({
        parent = ping_time_row,
        text = "检测间隔 (ms)",
        x = 10, y = 10,
        w = 150, h = 25,
        font_size = 20,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    connect_ping_time_input = airui.textarea({
        parent = ping_time_row,
        x = row_w - 120, y = 8,
        w = 110, h = 29,
        text = connect_advanced_config.ping_time,
        placeholder = "10000",
        max_len = 10,
        font_size = 18,
        color = 0x000000,
        keyboard = connect_wifi_keyboard,
    })
    y_offset = y_offset + 55

    -- 检测IP输入
    local ping_ip_row = airui.container({
        parent = advanced_card,
        x = 10, y = y_offset,
        w = row_w, h = 45,
        color = 0xFAFAFA, radius = 4,
    })
    airui.label({
        parent = ping_ip_row,
        text = "检测IP",
        x = 10, y = 10,
        w = 100, h = 25,
        font_size = 20,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    connect_ping_ip_input = airui.textarea({
        parent = ping_ip_row,
        x = row_w - 170, y = 8,
        w = 160, h = 29,
        text = connect_advanced_config.ping_ip,
        placeholder = "可选",
        max_len = 32,
        font_size = 18,
        color = 0x000000,
        keyboard = connect_wifi_keyboard,
    })
    y_offset = y_offset + 55

    -- 自动切换连接开关
    local auto_socket_switch_row = airui.container({
        parent = advanced_card,
        x = 10, y = y_offset,
        w = row_w, h = 45,
        color = 0xFAFAFA, radius = 4,
    })
    airui.label({
        parent = auto_socket_switch_row,
        text = "自动切换连接",
        x = 10, y = 10,
        w = 200, h = 25,
        font_size = 20,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.switch({
        parent = auto_socket_switch_row,
        x = row_w - 80, y = 8,
        w = 70, h = 29,
        checked = connect_advanced_config.auto_socket_switch,
        on_change = function(self)
            connect_advanced_config.auto_socket_switch = self:get_state()
        end
    })

    -- 底部按钮
    local bottom_container = airui.container({
        parent = connect_main_container,
        x = 0, y = SCREEN_H - 80,
        w = SCREEN_W, h = 80,
        color = 0xF0F0F0,
    })
    local btn_w = math.floor((SCREEN_W - 2 * MARGIN - SPACING) / 2)
    airui.button({
        parent = bottom_container,
        x = MARGIN, y = 15,
        w = btn_w, h = BUTTON_H,
        text = "取消",
        on_click = function()
            exwin.close(connect_win_id)
        end
    })
    airui.button({
        parent = bottom_container,
        x = MARGIN + btn_w + SPACING, y = 15,
        w = btn_w, h = BUTTON_H,
        text = "连接",
        style = {
            bg_color = 0x2196F3, bg_opa = 255,
            text_color = 0xFFFFFF,
            pressed_bg_color = 0x1976D2,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = function()
            local password = connect_password_textarea:get_text()
            if not password or password == "" then
                airui.msgbox({
                    text = "请输入WiFi密码",
                    buttons = { "确定" },
                    on_action = function(self) self:destroy() end
                })
                return
            end
            if #password < 8 then
                airui.msgbox({
                    text = "WiFi密码长度至少需要8位",
                    buttons = { "确定" },
                    on_action = function(self) self:destroy() end
                })
                return
            end

            connect_advanced_config.ping_time = connect_ping_time_input:get_text()
            connect_advanced_config.ping_ip = connect_ping_ip_input:get_text()

            local ping_time_num = tonumber(connect_advanced_config.ping_time)
            if not ping_time_num or ping_time_num <= 0 then
                airui.msgbox({
                    text = "检测间隔必须是正整数，请重新输入",
                    buttons = { "确定" },
                    on_action = function(self) self:destroy() end
                })
                return
            end

            sys.publish("WIFI_CONNECT_REQ", {
                ssid = connect_current_wifi and connect_current_wifi.ssid,
                password = password,
                advanced_config = connect_advanced_config
            })
            
            if connect_from_saved then
                sys.publish("CLOSE_WIFI_SAVED_LIST_WIN")
            end
            
            if connect_win_id then
                exwin.close(connect_win_id)
            end
        end
    })
end

local function connect_on_connected(ssid)
    log.info("wifi_connect_win", "WiFi连接成功:", ssid)
end

local function connect_on_disconnected(reason, code)
    log.info("wifi_connect_win", "WiFi连接失败:", reason, code)
end

local function connect_on_create()
    log.info("wifi_connect_win", "WiFi连接窗口创建")
    sys.publish("WIFI_GET_CONFIG_REQ")
    connect_create_ui()
    sys.subscribe("WIFI_CONNECTED", connect_on_connected)
    sys.subscribe("WIFI_DISCONNECTED", connect_on_disconnected)
    sys.subscribe("WIFI_CONFIG_RSP", connect_on_config_rsp)
end

local function connect_on_destroy()
    log.info("wifi_connect_win", "WiFi连接窗口销毁")
    sys.unsubscribe("WIFI_CONNECTED", connect_on_connected)
    sys.unsubscribe("WIFI_DISCONNECTED", connect_on_disconnected)
    sys.unsubscribe("WIFI_CONFIG_RSP", connect_on_config_rsp)
    if connect_main_container then
        connect_main_container:destroy()
        connect_main_container = nil
    end
    connect_win_id = nil
    connect_current_wifi = nil
    connect_wifi_keyboard = nil
    connect_password_textarea = nil
    connect_ping_time_input = nil
    connect_ping_ip_input = nil
    connect_advanced_config = nil
    connect_from_saved = false
end

local function connect_on_get_focus() end
local function connect_on_lose_focus() end

local function open(wifi_data, from_saved)
    if type(wifi_data) == "table" then
        connect_current_wifi = wifi_data
    else
        connect_current_wifi = {ssid = wifi_data}
    end
    connect_from_saved = from_saved or false
    if not exwin.is_active(connect_win_id) then
        connect_win_id = exwin.open({
            on_create = connect_on_create,
            on_destroy = connect_on_destroy,
            on_get_focus = connect_on_get_focus,
            on_lose_focus = connect_on_lose_focus,
        })
        log.info("wifi_connect_win", "WiFi连接窗口打开，ID:", connect_win_id)
    end
end

sys.subscribe("OPEN_WIFI_CONNECT_WIN", open)
log.info("wifi_connect_win", "订阅 OPEN_WIFI_CONNECT_WIN 消息")