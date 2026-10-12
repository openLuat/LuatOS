--[[
@module  wifi_win
@summary WiFi页面，显示当前连接状态 + 扫描结果
@version 2.0.0
@date    2026.08.14
@author  江访
@usage
本页面提供WiFi信息展示功能：
1、当前是否连接WiFi及连接状态（SSID + 信号强度）
2、刷新按钮触发扫描（通过 WIFI_SCAN_REQ/WIFI_SCAN_RESULT 与 wifi_app 交互）
3、扫描结果列表展示（重新布局）

不提供WiFi开关功能。
]]

local win_id = nil
local main_container, content
local wifi_status_label = nil
local scan_list_label = nil
local scan_count_label = nil

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

--[[
更新WiFi连接状态显示

@local
@function on_status_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi名称
@param level number 信号等级(0~4)
@param rssi number 信号强度dBm
]]
local function on_status_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    if not wifi_status_label then return end
    local text = ""
    local color = T.COLOR_TEXT
    if connected then
        text = "已连接：" .. tostring(ssid or "")
        if rssi and rssi ~= 0 then
            text = text .. "  " .. tostring(rssi) .. "dBm"
        end
        color = T.COLOR_GREEN
    else
        text = "未连接"
        color = T.COLOR_DANGER
    end
    wifi_status_label:set_text(text)
    wifi_status_label:set_color(color)
end

--[[
WIFI_SCAN_RESULT 消息回调：接收扫描结果并显示

@local
@function on_scan_result
@param results table 扫描结果列表
]]
local function on_scan_result(results)
    if not exwin.is_active(win_id) then return end
    if not scan_list_label then return end
    if results and type(results) == "table" and #results > 0 then
        local lines = {}
        local count = #results
        if count > 8 then count = 8 end
        for i = 1, count do
            local entry = results[i]
            if type(entry) == "table" then
                local ssid = entry.ssid or "未知"
                local rssi = entry.rssi or 0
                table.insert(lines, ssid .. "  " .. tostring(rssi) .. "dBm")
            end
        end
        if #lines > 0 then
            scan_list_label:set_text(table.concat(lines, "\n"))
            if scan_count_label then
                scan_count_label:set_text("发现 " .. tostring(#results) .. " 个WiFi")
            end
        else
            scan_list_label:set_text("未发现WiFi")
            if scan_count_label then
                scan_count_label:set_text("未发现WiFi")
            end
        end
    else
        scan_list_label:set_text("未发现WiFi")
        if scan_count_label then
            scan_count_label:set_text("未发现WiFi")
        end
    end
end

--[[
刷新按钮点击：请求扫描
]]
local function on_refresh_click()
    if not exwin.is_active(win_id) then return end
    if scan_list_label then
        scan_list_label:set_text("扫描中...")
    end
    if scan_count_label then
        scan_count_label:set_text("")
    end
    sys.publish("WIFI_SCAN_REQ")
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    -- 顶部标题栏
    T.titlebar(main_container, "WiFi", on_back_click)

    -- 内容区域
    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- WiFi连接状态卡片
    local _, _, status_content = T.info_card(content, 6, 44, "连接状态", "未连接")
    wifi_status_label = status_content

    -- 扫描区域标题 + 刷新按钮
    airui.label({ parent = content, x = T.MARGIN, y = 58, w = 100, h = 20, text = "可用WiFi", font_size = T.FONT_CARD_TITLE, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    scan_count_label = airui.label({ parent = content, x = 110, y = 58, w = 180, h = 20, text = "", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })

    T.btn_primary(content, 380, 52, 90, 30, "刷新扫描", on_refresh_click)

    -- 扫描结果区域
    local list_card = airui.container({ parent = content, x = T.MARGIN, y = 86, w = T.CARD_W, h = 136, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    scan_list_label = airui.label({ parent = list_card, x = 10, y = 6, w = T.CARD_W - 20, h = 124, text = "点击\"刷新扫描\"开始", font_size = T.FONT_SMALL, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
end

local function on_create()
    create_ui()
    sys.subscribe("WIFI_SCAN_RESULT", on_scan_result)
    sys.subscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    -- 主动查询一次当前WiFi状态
    sys.publish("NETWORK_STATUS_QUERY")
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    scan_list_label = nil
    wifi_status_label = nil
    scan_count_label = nil
    sys.unsubscribe("WIFI_SCAN_RESULT", on_scan_result)
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    win_id = nil
end

local function on_get_focus()
    -- 重新获得焦点时刷新连接状态
    sys.publish("NETWORK_STATUS_QUERY")
end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_WIFI_WIN", open_handler)
