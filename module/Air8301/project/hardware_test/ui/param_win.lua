--[[
@module  param_win
@summary 参数设置页面，显示和编辑设备配置
@version 1.0
@date    2026.09.04
@author  江访
@usage
可查看/编辑的配置项：
1、MQTT：broker地址、端口、CID
2、网络：WiFi SSID、网络优先级
3、串口：RS485/RS232 波特率
4、系统：NTP服务器、对时间隔

修改后通过 CONFIG_UPDATE_TRIGGER 保存，各模块热重载。
]]

local param_app = require "param_app"

local win_id = nil
local main_container, content

-- 当前配置副本（页面内编辑，确认后统一保存）
local edit_config = {}

-- UI 标签引用
local mqtt_broker_label, mqtt_port_label, mqtt_cid_label
local wifi_ssid_label, priority_label
local rs485_1_baud_label, rs485_2_baud_label
local ntp_server_label, ntp_interval_label

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

-- ==================== 配置读取/保存 ====================

local function load_edit_config()
    local cfg = param_app.get_config()
    -- 深拷贝到 edit_config（避免直接修改原配置）
    edit_config = json.decode(json.encode(cfg or {}))
end

local function save_and_close()
    -- 通过 CONFIG_UPDATE_TRIGGER 合并保存
    for k, v in pairs(edit_config) do
        sys.publish("CONFIG_UPDATE_TRIGGER", k, v)
    end
    log.info("param_win", "config saved")
    exwin.close(win_id)
end

-- ==================== UI 刷新 ====================

local function refresh_labels()
    if not exwin.is_active(win_id) then return end

    local mqtt = edit_config.mqtt or {}
    local net = edit_config.network or {}
    local uart = edit_config.uart or {}
    local sys_cfg = edit_config.system or {}

    if mqtt_broker_label then mqtt_broker_label:set_text(mqtt.broker or "--") end
    if mqtt_port_label then mqtt_port_label:set_text(tostring(mqtt.port or "--")) end
    if mqtt_cid_label then mqtt_cid_label:set_text(mqtt.cid or "--") end

    local wifi = net.wifi or {}
    if wifi_ssid_label then wifi_ssid_label:set_text(wifi.ssid or "未配置") end

    local prio = net.priority or {}
    if priority_label then
        local order = prio.order or {"eth1", "eth2", "wifi", "4g"}
        priority_label:set_text(table.concat(order, " > "))
    end

    local rs485_1 = uart.rs485_1 or {}
    local rs485_2 = uart.rs485_2 or {}
    if rs485_1_baud_label then rs485_1_baud_label:set_text(tostring(rs485_1.baud_rate or 115200)) end
    if rs485_2_baud_label then rs485_2_baud_label:set_text(tostring(rs485_2.baud_rate or 115200)) end

    if ntp_server_label then ntp_server_label:set_text(sys_cfg.ntp_server or "ntp.aliyun.com") end
    if ntp_interval_label then ntp_interval_label:set_text(tostring(sys_cfg.ntp_interval_h or 6) .. "小时") end
end

-- ==================== 创建 UI ====================

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })
    T.titlebar(main_container, "参数设置", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    local y = 8

    -- MQTT 卡片
    local c1 = airui.container({ parent = content, x = T.MARGIN, y = y, w = T.CARD_W, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c1, x = 10, y = 4, w = 100, h = 18, text = "MQTT", font_size = T.FONT_CARD_TITLE, color = T.COLOR_PRIMARY, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c1, x = 10, y = 24, w = 60, h = 18, text = "服务器", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    mqtt_broker_label = airui.label({ parent = c1, x = 80, y = 24, w = 200, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c1, x = 290, y = 24, w = 40, h = 18, text = "端口", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    mqtt_port_label = airui.label({ parent = c1, x = 330, y = 24, w = 60, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c1, x = 10, y = 46, w = 60, h = 18, text = "CID", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    mqtt_cid_label = airui.label({ parent = c1, x = 80, y = 46, w = 200, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    y = y + 78

    -- 网络卡片
    local c2 = airui.container({ parent = content, x = T.MARGIN, y = y, w = T.CARD_W, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c2, x = 10, y = 4, w = 100, h = 18, text = "网络", font_size = T.FONT_CARD_TITLE, color = T.COLOR_PRIMARY, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c2, x = 10, y = 24, w = 60, h = 18, text = "WiFi", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    wifi_ssid_label = airui.label({ parent = c2, x = 80, y = 24, w = 200, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c2, x = 10, y = 46, w = 60, h = 18, text = "优先级", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    priority_label = airui.label({ parent = c2, x = 80, y = 46, w = 300, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    y = y + 78

    -- 串口卡片
    local c3 = airui.container({ parent = content, x = T.MARGIN, y = y, w = T.CARD_W, h = 58, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c3, x = 10, y = 4, w = 100, h = 18, text = "串口", font_size = T.FONT_CARD_TITLE, color = T.COLOR_PRIMARY, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c3, x = 10, y = 26, w = 70, h = 18, text = "RS485-1", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    rs485_1_baud_label = airui.label({ parent = c3, x = 80, y = 26, w = 100, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c3, x = 200, y = 26, w = 70, h = 18, text = "RS485-2", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    rs485_2_baud_label = airui.label({ parent = c3, x = 270, y = 26, w = 100, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    y = y + 66

    -- 系统卡片
    local c4 = airui.container({ parent = content, x = T.MARGIN, y = y, w = T.CARD_W, h = 58, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c4, x = 10, y = 4, w = 100, h = 18, text = "系统", font_size = T.FONT_CARD_TITLE, color = T.COLOR_PRIMARY, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c4, x = 10, y = 26, w = 60, h = 18, text = "NTP", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    ntp_server_label = airui.label({ parent = c4, x = 80, y = 26, w = 180, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c4, x = 270, y = 26, w = 60, h = 18, text = "间隔", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    ntp_interval_label = airui.label({ parent = c4, x = 330, y = 26, w = 80, h = 18, text = "--", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    y = y + 66

    -- 底部提示
    airui.label({ parent = content, x = T.MARGIN, y = y + 4, w = T.CARD_W, h = 18, text = "配置修改后自动保存，各模块热重载", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER })
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    load_edit_config()
    create_ui()
    refresh_labels()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    content = nil
    mqtt_broker_label = nil; mqtt_port_label = nil; mqtt_cid_label = nil
    wifi_ssid_label = nil; priority_label = nil
    rs485_1_baud_label = nil; rs485_2_baud_label = nil
    ntp_server_label = nil; ntp_interval_label = nil
    edit_config = {}
    win_id = nil
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

sys.subscribe("OPEN_PARAM_WIN", open_handler)
