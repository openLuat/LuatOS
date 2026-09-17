--[[
@module  wifi_detail_win
@summary WiFi详情窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
@author  江访

消息协议（订阅/发布）:
订阅: OPEN_WIFI_DETAIL_WIN           → 创建详情窗口
订阅: WIFI_STATUS_UPDATED(status)    → 实时状态更新
订阅: WIFI_CONFIG_RSP({config})      → 配置返回
发布: WIFI_GET_STATUS_REQ            → 获取当前状态
发布: WIFI_GET_CONFIG_REQ            → 获取配置
发布: WIFI_DISCONNECT_REQ            → 断开连接
]]

local SCREEN_W, SCREEN_H = 480, 800
local MARGIN = 15
local TITLE_H = math.floor(60 * (_G.density_scale or 1.0))
local BUTTON_H = 50

-- TabOS 深色玻璃态调色板（原浅色常量 → 主题令牌）
local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

-- 主题令牌动态代理：换主题后自动取到新色值
-- （写成 local X = theme.C.y 会在 require 时固化，换肤不生效）
local CLR = theme.live()

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
    BUTTON_H = math.floor(SCREEN_H * 0.0625)
end

local detail_win_id = nil
local detail_main_container = nil
local detail_labels = {}
local password_visible = false

local current_status = {
    connected = false, ready = false, current_ssid = "",
    rssi = "--", ip = "--", netmask = "--", gateway = "--", bssid = "--",
    scan_results = {}
}
local current_config = {
    wifi_enabled = false, ssid = "", password = "",
    need_ping = true, local_network_mode = false,
    ping_ip = "", ping_time = "10000", auto_socket_switch = true
}

local function detail_update_detail_info()
    if not current_status then return end
    if detail_labels.ssid then
        detail_labels.ssid:set_text(current_status.current_ssid ~= "" and current_status.current_ssid or "--")
    end
    if detail_labels.rssi then
        detail_labels.rssi:set_text(current_status.rssi ~= "--" and (current_status.rssi .. " dBm") or "--")
    end
    if detail_labels.ip then detail_labels.ip:set_text(current_status.ip) end
    if detail_labels.netmask then detail_labels.netmask:set_text(current_status.netmask) end
    if detail_labels.gateway then detail_labels.gateway:set_text(current_status.gateway) end
    if detail_labels.bssid then detail_labels.bssid:set_text(current_status.bssid) end
    if detail_labels.password and current_config then
        local password = current_config.password or ""
        if password_visible then
            detail_labels.password:set_text(password)
        else
            detail_labels.password:set_text(string.rep("*", #password))
        end
    end
    if detail_labels.connectivity then
        if current_status.connectivity_verified then
            detail_labels.connectivity:set_text("已确认 (NTP同步成功)")
            detail_labels.connectivity:set_color(theme.SEM.success)
        elseif current_status.ready then
            detail_labels.connectivity:set_text("待确认 (NTP同步中...)")
            detail_labels.connectivity:set_color(CLR.primary)
        elseif current_status.connected then
            detail_labels.connectivity:set_text("正在获取IP")
            detail_labels.connectivity:set_color(CLR.primary)
        else
            detail_labels.connectivity:set_text("未就绪")
            detail_labels.connectivity:set_color(CLR.t2)
        end
    end
end

local function detail_create_ui()
    update_screen_size()
detail_main_container = theme.page_bg(airui.screen, SCREEN_W, SCREEN_H)

    --[[标题栏改走统一组件（= theme.header），与 wifi_list / 文件管理 / 设置各页一致：
    返回键由 theme.iconbtn 绘制，图标缺失时退化出的 "<" 文字按「盒高 = 字号 + 3」算，
    不再溢出父容器；标题/副标题的盒高也由 header 内部算好。]]
    local _, th = titlebar.create(detail_main_container, "WiFi 详情", SCREEN_W,
        function() exwin.close(detail_win_id) end, "实时状态 | IP 配置 | 连接信息")
    TITLE_H = th

    local detail_scroll_container = airui.container({
        parent = detail_main_container,
        x = 0, y = TITLE_H,
        w = SCREEN_W, h = SCREEN_H - TITLE_H,
        color = CLR.surface, color_opacity = 0,
        scrollable = true,
    })

    local detail_card = airui.container({
        parent = detail_scroll_container,
        x = MARGIN, y = math.floor(10 * _G.density_scale),
        w = SCREEN_W - 2 * MARGIN, h = math.floor(440 * _G.density_scale),
        color = theme.C.surface, color_opacity = theme.OPA.glass,
        border_color = theme.C.stroke, border_width = 1, radius = theme.r("md"),
    })

    airui.label({
        parent = detail_card,
        text = "网络详情",
        x = math.floor(10 * _G.density_scale), y = math.floor(15 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = theme.fs("h2") + 3,
        font_size = theme.fs("h2"),
        color = CLR.t1,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.button({
        parent = detail_card,
        x = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale) - math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(60 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "刷新",
        style = {
            bg_color = CLR.primary, bg_opa = 255,
            text_color = CLR.white,
            pressed_bg_color = CLR.primary_deep,
            pressed_text_color = CLR.white,
        },
        on_click = function()
            sys.publish("WIFI_GET_STATUS_REQ")
            local msg = airui.msgbox({
                text = "刷新成功",
                buttons = { "确定" },
                on_action = function(self) self:hide() end
            })
            msg:show()
        end
    })

    local function create_detail_row(parent, y, label_text, value_key)
        local row = airui.container({
            parent = parent,
            x = math.floor(10 * _G.density_scale), y = y,
            w = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale),
            h = math.floor(50 * _G.density_scale),
            color = theme.C.surface, color_opacity = theme.OPA.glass,
            border_color = theme.C.stroke, border_width = 1, radius = theme.r("sm"),
        })
        airui.label({
            parent = row,
            text = label_text,
            x = 0, y = math.floor(15 * _G.density_scale),
            w = math.floor(120 * _G.density_scale), h = math.floor(25 * _G.density_scale),
            font_size = theme.fs("h3"),
            color = CLR.t1,
            align = airui.TEXT_ALIGN_LEFT,
        })
        local value_label = airui.label({
            parent = row,
            text = "--",
            x = math.floor(130 * _G.density_scale), y = math.floor(15 * _G.density_scale),
            w = (SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale)) - math.floor(130 * _G.density_scale) - math.floor(5 * _G.density_scale),
            h = math.floor(25 * _G.density_scale),
            font_size = theme.fs("h3"),
            color = CLR.t1,
            align = airui.TEXT_ALIGN_RIGHT,
        })
        detail_labels[value_key] = value_label
    end

    local y_offset = math.floor(50 * _G.density_scale)
    create_detail_row(detail_card, y_offset, "SSID", "ssid")
    y_offset = y_offset + math.floor(55 * _G.density_scale)
    create_detail_row(detail_card, y_offset, "信号强度", "rssi")
    y_offset = y_offset + math.floor(55 * _G.density_scale)
    create_detail_row(detail_card, y_offset, "IP地址", "ip")
    y_offset = y_offset + math.floor(55 * _G.density_scale)
    create_detail_row(detail_card, y_offset, "子网掩码", "netmask")
    y_offset = y_offset + math.floor(55 * _G.density_scale)
    create_detail_row(detail_card, y_offset, "网关", "gateway")
    y_offset = y_offset + math.floor(55 * _G.density_scale)
    create_detail_row(detail_card, y_offset, "MAC地址", "bssid")
    y_offset = y_offset + math.floor(55 * _G.density_scale)
    create_detail_row(detail_card, y_offset, "网络连通", "connectivity")
    y_offset = y_offset + math.floor(55 * _G.density_scale)

    local password_row = airui.container({
        parent = detail_card,
        x = math.floor(10 * _G.density_scale), y = y_offset,
        w = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale),
        h = math.floor(50 * _G.density_scale),
        color = theme.C.surface, color_opacity = theme.OPA.glass,
        border_color = theme.C.stroke, border_width = 1, radius = theme.r("sm"),
    })
    airui.label({
        parent = password_row,
        text = "密码",
        x = 0, y = math.floor(15 * _G.density_scale),
        w = math.floor(120 * _G.density_scale), h = math.floor(25 * _G.density_scale),
        font_size = theme.fs("h3"),
        color = CLR.t1,
        align = airui.TEXT_ALIGN_LEFT,
    })
    detail_labels.password = airui.label({
        parent = password_row,
        text = "",
        x = math.floor(130 * _G.density_scale), y = math.floor(15 * _G.density_scale),
        w = (SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale)) - math.floor(130 * _G.density_scale) - math.floor(5 * _G.density_scale),
        h = math.floor(25 * _G.density_scale),
        font_size = theme.fs("h3"),
        color = CLR.t1,
        align = airui.TEXT_ALIGN_RIGHT,
        on_click = function()
            password_visible = not password_visible
            if current_config then
                local password = current_config.password or ""
                if password_visible then
                    detail_labels.password:set_text(password)
                else
                    detail_labels.password:set_text(string.rep("*", #password))
                end
            end
        end
    })

    airui.button({
        parent = detail_scroll_container,
        x = MARGIN, y = math.floor(470 * _G.density_scale),
        w = SCREEN_W - 2 * MARGIN, h = BUTTON_H,
        text = "断开连接",
        style = {
            bg_color = CLR.rose, bg_opa = 255,
            text_color = CLR.white,
            pressed_bg_color = CLR.rose,
            pressed_text_color = CLR.white,
        },
        on_click = function()
            local msg = airui.msgbox({
                text = "确定要断开WiFi连接吗？",
                buttons = { "取消", "确定" },
                on_action = function(self, label)
                    if label == "确定" then
                        sys.publish("WIFI_DISCONNECT_REQ")
                        self:hide()
                        exwin.close(detail_win_id)
                    else
                        self:hide()
                    end
                end
            })
            msg:show()
        end
    })
end

local function detail_on_status_updated(status)
    log.info("wifi_detail_win", "WiFi状态更新:", json.encode(status))
    current_status = status
    detail_update_detail_info()
end

local function detail_on_config_rsp(data)
    current_config = data.config
    log.info("wifi_detail_win", "配置加载完成:", json.encode(current_config))
    detail_update_detail_info()
end

local function detail_on_create()
    detail_create_ui()
    sys.publish("WIFI_GET_STATUS_REQ")
    sys.publish("WIFI_GET_CONFIG_REQ")
    sys.subscribe("WIFI_STATUS_UPDATED", detail_on_status_updated)
    sys.subscribe("WIFI_CONFIG_RSP", detail_on_config_rsp)
end

local function detail_on_destroy()
    sys.unsubscribe("WIFI_STATUS_UPDATED", detail_on_status_updated)
    sys.unsubscribe("WIFI_CONFIG_RSP", detail_on_config_rsp)
    if detail_main_container then
        detail_main_container:destroy()
        detail_main_container = nil
    end
    detail_labels = {}
    detail_win_id = nil
    password_visible = false
end

local function detail_on_get_focus() end
local function detail_on_lose_focus() end

local function open()
    if not exwin.is_active(detail_win_id) then
        detail_win_id = exwin.open({
            on_create = detail_on_create,
            on_destroy = detail_on_destroy,
            on_get_focus = detail_on_get_focus,
            on_lose_focus = detail_on_lose_focus,
        })
    end
end

sys.subscribe("OPEN_WIFI_DETAIL_WIN", open)