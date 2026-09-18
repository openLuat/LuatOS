--[[
@module  mqtt_win
@summary MQTT云平台状态与配置页面
@version 1.0
@date    2026.09.04
@author  江访
@usage
显示MQTT连接状态、broker地址、设备ID、上传间隔等信息。
]]

local win_id = nil
local main_container, content
local status_label, broker_label, client_label, interval_label

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "MQTT云平台", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 连接状态卡片
    local c1 = airui.container({ parent = content, x = T.MARGIN, y = 10, w = T.CARD_W, h = 50, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c1, x = 15, y = 6, w = 100, h = 20, text = "连接状态", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    status_label = airui.label({ parent = c1, x = 15, y = 26, w = 200, h = 20, text = "未连接", font_size = T.FONT_BODY, color = T.COLOR_DANGER, align = airui.TEXT_ALIGN_LEFT })

    -- Broker 信息卡片
    local c2 = airui.container({ parent = content, x = T.MARGIN, y = 68, w = T.CARD_W, h = 50, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c2, x = 15, y = 6, w = 100, h = 20, text = "Broker", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    broker_label = airui.label({ parent = c2, x = 15, y = 26, w = 400, h = 20, text = "未配置", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 设备ID卡片
    local c3 = airui.container({ parent = content, x = T.MARGIN, y = 126, w = T.CARD_W, h = 50, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c3, x = 15, y = 6, w = 100, h = 20, text = "设备ID", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    client_label = airui.label({ parent = c3, x = 15, y = 26, w = 400, h = 20, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 上传间隔卡片
    local c4 = airui.container({ parent = content, x = T.MARGIN, y = 184, w = T.CARD_W, h = 50, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c4, x = 15, y = 6, w = 100, h = 20, text = "上传间隔", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    interval_label = airui.label({ parent = c4, x = 15, y = 26, w = 200, h = 20, text = "60秒", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
end

local function on_create()
    create_ui()
    -- 查询 MQTT 状态
    sys.publish("mqtt_cmd_get_status")
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    status_label = nil; broker_label = nil; client_label = nil; interval_label = nil; win_id = nil
end

local function on_get_focus()
    sys.publish("mqtt_cmd_get_status")
end
local function on_lose_focus() end

-- 订阅 MQTT 状态更新
sys.subscribe("mqtt_status_rsp", function(data)
    if not status_label then return end
    if data.connected then
        status_label:set_text("已连接")
        status_label:set_color(T.COLOR_GREEN)
    else
        status_label:set_text("未连接")
        status_label:set_color(T.COLOR_DANGER)
    end
    if data.broker then
        local broker_str = data.broker .. ":" .. (data.port or "")
        broker_label:set_text(broker_str)
    end
    if data.client_id then
        client_label:set_text(data.client_id)
    end
end)

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_MQTT_WIN", open_handler)
