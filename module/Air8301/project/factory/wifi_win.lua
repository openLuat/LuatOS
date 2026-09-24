--[[
@module  wifi_win
@summary WiFi 状态与扫描页面（8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
@usage
显示当前 WiFi 连接状态（SSID / 信号强度 / IP），支持扫描周边 WiFi。
- 订阅 STATUS_WIFI_UPDATED 实时更新
- 打开页面时发布 NETWORK_STATUS_QUERY 主动查询一次
]]

local win_id = nil
local main_container, content
local ssid_label, rssi_label, ip_label, scan_label

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
WiFi 状态更新回调

@local
@function on_status_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi名称
@param level number 信号等级
@param rssi number 信号强度dBm
]]
local function on_status_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    if ssid_label then
        if connected then
            ssid_label:set_text(tostring(ssid or "--"))
            ssid_label:set_color(T.COLOR_GREEN)
        else
            ssid_label:set_text("未连接")
            ssid_label:set_color(T.COLOR_DANGER)
        end
    end
    if rssi_label then
        rssi_label:set_text(connected and (tostring(rssi or 0) .. " dBm") or "--")
    end
    if ip_label then
        local ip = connected and socket.localIP(socket.LWIP_STA) or "--"
        ip_label:set_text(tostring(ip or "--"))
    end
end

--[[
WiFi 扫描按钮点击：触发扫描并在 3 秒后读取结果

@local
@function on_scan_click
]]
local function on_scan_click()
    if not exwin.is_active(win_id) then return end
    if scan_label then
        scan_label:set_text("扫描中...")
    end
    wlan.scan()
end

--[[
WiFi 扫描完成回调：显示前若干条结果

@local
@function on_scan_done
]]
local function on_scan_done()
    if not exwin.is_active(win_id) then return end
    local list = wlan.scanResult() or {}
    local lines = {}
    for i, ap in ipairs(list) do
        if i > 8 then break end
        lines[#lines + 1] = tostring(ap.ssid or "--") .. "  " .. tostring(ap.rssi or 0) .. "dBm"
    end
    if #lines == 0 then
        lines[1] = "未扫描到 WiFi"
    end
    if scan_label then
        scan_label:set_text(table.concat(lines, "\n"))
    end
end

--[[
创建 WiFi 页面 UI

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "WiFi", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    local _, _, ssid_content = T.info_card(content, 6, 46, "当前 SSID", "--")
    ssid_label = ssid_content

    local _, _, rssi_content = T.info_card(content, 58, 46, "信号强度", "--")
    rssi_label = rssi_content

    local _, _, ip_content = T.info_card(content, 6, 46, "IP 地址", "--")
    ip_content:set_pos(240, 6)
    ip_label = ip_content

    -- 扫描按钮（右侧）
    T.btn_primary(content, 240, 58, 230, 46, "扫描周边 WiFi", on_scan_click)

    local _, _, scan_content = T.info_card(content, 110, 104, "扫描结果", "点击上方按钮开始扫描")
    scan_label = scan_content

    -- 主动查询一次网络状态
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    sys.subscribe("WLAN_SCAN_DONE", on_scan_done)
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    ssid_label = nil
    rssi_label = nil
    ip_label = nil
    scan_label = nil
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    sys.unsubscribe("WLAN_SCAN_DONE", on_scan_done)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_WIFI_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_WIFI_WIN", open_handler)
