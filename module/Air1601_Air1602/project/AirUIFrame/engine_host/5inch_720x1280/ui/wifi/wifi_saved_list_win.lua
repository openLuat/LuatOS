--[[
@module  wifi_saved_list_win
@summary 已保存网络列表窗口（UI层，事件驱动）- 自适应分辨率
@version 1.1
@date    2026.04.16
]]

require "wifi_app"
require "wifi_connect_win"

local SCREEN_W, SCREEN_H = 480, 800
local MARGIN = 15
local TITLE_H = math.floor(60 * _G.density_scale)

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

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
end
local saved_list_win_id = nil
local saved_list_main_container = nil
local saved_list_scroll_container = nil
local saved_list_content = nil
local saved_list_items = {}
local saved_list_data = {}
local current_config = nil

local function saved_list_on_status_updated(status)
    log.info("wifi_saved_list_win", "WiFi状态更新:", json.encode(status))
end

local function saved_list_on_config_rsp(data)
    current_config = data.config
    log.info("wifi_saved_list_win", "配置加载完成, wifi_enabled:", current_config and current_config.wifi_enabled)
end

local function saved_list_clear_items()
    for _, item in ipairs(saved_list_items) do item:destroy() end
    saved_list_items = {}
end

local function saved_list_create_ui()
    update_screen_size()
    saved_list_main_container = airui.container({
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H,
        color = COLOR_BG,
    })

    local title_bar = airui.container({
        parent = saved_list_main_container,
        x = 0, y = 0,
        w = SCREEN_W, h = TITLE_H,
        color = COLOR_PRIMARY,
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function()
            sys.publish("CLOSE_WIFI_SAVED_LIST_WIN")
        end
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
        text = "已保存的网络",
        x = math.floor(60 * _G.density_scale), y = math.floor(14 * _G.density_scale),
        w = SCREEN_W - math.floor(60 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT,
    })

    saved_list_scroll_container = airui.container({
        parent = saved_list_main_container,
        x = 0, y = TITLE_H,
        w = SCREEN_W, h = SCREEN_H - TITLE_H,
        color = COLOR_BG,
        scrollable = true,
    })
    saved_list_content = airui.container({
        parent = saved_list_scroll_container,
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H - TITLE_H,
        color = COLOR_BG,
    })
end

local function saved_list_update()
    log.info("wifi_saved_list_win", "更新已保存网络列表，数量:", #saved_list_data)
    saved_list_clear_items()
    local y = 0
    for _, wifi_data in ipairs(saved_list_data) do
        local item = airui.container({
            parent = saved_list_content,
            x = MARGIN, y = y,
            w = SCREEN_W - 2 * MARGIN, h = math.floor(65 * _G.density_scale),
            color = COLOR_WHITE, radius = 8,
            on_click = function()
                log.info("wifi_saved_list_win", "点击已保存网络:", wifi_data.ssid)
                if not current_config or not current_config.wifi_enabled then
                    airui.msgbox({
                        text = "请先开启WiFi",
                        buttons = { "确定" },
                        on_action = function(self) self:destroy() end
                    })
                    return
                end
                sys.publish("OPEN_WIFI_CONNECT_WIN", wifi_data, true)
            end
        })
        airui.label({
            parent = item,
            text = wifi_data.ssid,
            x = math.floor(10 * _G.density_scale), y = math.floor(17 * _G.density_scale),
            w = SCREEN_W - 2 * MARGIN - math.floor(20 * _G.density_scale), h = math.floor(30 * _G.density_scale),
            font_size = math.floor(20 * _G.density_scale),
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT,
        })
        table.insert(saved_list_items, item)
        y = y + math.floor(75 * _G.density_scale)
    end
end

local function saved_list_on_saved_list_rsp(data)
    log.info("wifi_saved_list_win", "收到已保存网络列表，数量:", #data.list)
    saved_list_data = data.list
    saved_list_update()
end

local function saved_list_on_create()
    log.info("wifi_saved_list_win", "已保存网络窗口创建")
    sys.publish("WIFI_GET_SAVED_LIST_REQ")
    sys.publish("WIFI_GET_CONFIG_REQ")
    sys.publish("WIFI_GET_STATUS_REQ")
    saved_list_create_ui()
    sys.subscribe("WIFI_SAVED_LIST_RSP", saved_list_on_saved_list_rsp)
    sys.subscribe("WIFI_STATUS_UPDATED", saved_list_on_status_updated)
    sys.subscribe("WIFI_CONFIG_RSP", saved_list_on_config_rsp)
end

local function saved_list_on_destroy()
    log.info("wifi_saved_list_win", "已保存网络窗口销毁")
    sys.unsubscribe("WIFI_SAVED_LIST_RSP", saved_list_on_saved_list_rsp)
    sys.unsubscribe("WIFI_STATUS_UPDATED", saved_list_on_status_updated)
    sys.unsubscribe("WIFI_CONFIG_RSP", saved_list_on_config_rsp)
    saved_list_clear_items()
    if saved_list_main_container then
        saved_list_main_container:destroy()
        saved_list_main_container = nil
    end
    saved_list_scroll_container = nil
    saved_list_content = nil
    saved_list_win_id = nil
    current_config = nil
end

local function saved_list_on_get_focus() end
local function saved_list_on_lose_focus() end

local function open()
    if not exwin.is_active(saved_list_win_id) then
        saved_list_win_id = exwin.open({
            on_create = saved_list_on_create,
            on_destroy = saved_list_on_destroy,
            on_get_focus = saved_list_on_get_focus,
            on_lose_focus = saved_list_on_lose_focus,
        })
        log.info("wifi_saved_list_win", "已保存网络窗口打开，ID:", saved_list_win_id)
    end
end

sys.subscribe("OPEN_WIFI_SAVED_LIST_WIN", open)
sys.subscribe("CLOSE_WIFI_SAVED_LIST_WIN", function()
    if saved_list_win_id then exwin.close(saved_list_win_id) end
end)
log.info("wifi_saved_list_win", "订阅 OPEN_WIFI_SAVED_LIST_WIN 消息")