--[[
@module  network_win
@summary 网络状态页面，显示4G信号强度、WiFi状态和以太网1/2状态
@version 1.1.0
@date    2026.07.31
@author  合宙 Air8301
@usage
本页面只读展示三种网络状态：
1、4G信号强度（等级1~5或"无服务"）
2、WiFi连接状态（已连接显示SSID+信号强度，未连接显示未连接）
3、以太网1/2连接状态（分开两行显示IP）

WiFi 状态获取：
- 订阅 STATUS_WIFI_UPDATED(connected, ssid, level, rssi) 实时更新
- 打开页面时发布 NETWORK_STATUS_QUERY 主动查询一次，避免"WiFi已连接但页面显示未连接"
]]

local win_id = nil
local main_container, content
local signal_label, wifi_label, eth1_label, eth2_label

-- 颜色常量
local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF
local COLOR_GREEN = 0x4CAF50
local COLOR_RED = 0xF44336
local COLOR_ORANGE = 0xFF9800

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
更新4G信号等级显示

@local
@function on_status_signal_updated
@param level number 信号等级(0~5)
]]
local function on_status_signal_updated(level)
    if not exwin.is_active(win_id) then return end
    if not signal_label then return end
    local text = ""
    local color = COLOR_TEXT
    if level == nil or level == 0 then
        text = "无服务"
        color = COLOR_RED
    elseif level == 1 then
        text = "信号：1级（微弱）"
        color = COLOR_RED
    elseif level == 2 then
        text = "信号：2级（较差）"
        color = COLOR_ORANGE
    elseif level == 3 then
        text = "信号：3级（一般）"
        color = COLOR_ORANGE
    elseif level == 4 then
        text = "信号：4级（良好）"
        color = COLOR_GREEN
    elseif level == 5 then
        text = "信号：5级（极强）"
        color = COLOR_GREEN
    end
    signal_label:set_text(text)
    signal_label:set_color(color)
end

--[[
更新WiFi状态显示

@local
@function on_status_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi名称
@param level number 信号等级(0~4)
@param rssi number 信号强度dBm
]]
local function on_status_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    if not wifi_label then return end
    local text = ""
    local color = COLOR_TEXT
    if connected then
        text = "已连接  " .. tostring(ssid or "")
        if rssi and rssi ~= 0 then
            text = text .. "  " .. tostring(rssi) .. "dBm"
        end
        color = COLOR_GREEN
    else
        text = "未连接"
        color = COLOR_RED
    end
    wifi_label:set_text(text)
    wifi_label:set_color(color)
end

--[[
更新以太网1状态显示

@local
@function on_eth1_status
]]
local function update_eth1(eth1_state, eth1_ip)
    if not eth1_label then return end
    if eth1_state and eth1_state > 0 then
        eth1_label:set_text("已连接  " .. (eth1_ip or ""))
        eth1_label:set_color(COLOR_GREEN)
    else
        eth1_label:set_text("未连接")
        eth1_label:set_color(COLOR_RED)
    end
end

--[[
更新以太网2状态显示

@local
@function on_eth2_status
]]
local function update_eth2(eth2_state, eth2_ip)
    if not eth2_label then return end
    if eth2_state and eth2_state > 0 then
        eth2_label:set_text("已连接  " .. (eth2_ip or ""))
        eth2_label:set_color(COLOR_GREEN)
    else
        eth2_label:set_text("未连接")
        eth2_label:set_color(COLOR_RED)
    end
end

--[[
更新以太网状态显示（ETH1/ETH2分开两行）

@local
@function on_status_eth_updated
@param eth1_state boolean ETH1连接状态
@param eth1_ip string ETH1的IP地址
@param eth2_state boolean ETH2连接状态
@param eth2_ip string ETH2的IP地址
]]
local function on_status_eth_updated(eth1_state, eth1_ip, eth2_state, eth2_ip)
    if not exwin.is_active(win_id) then return end
    update_eth1(eth1_state, eth1_ip)
    update_eth2(eth2_state, eth2_ip)
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 272, color = COLOR_BG, parent = airui.screen })

    -- 顶部导航栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 44, color = COLOR_PRIMARY })

    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 0,
        y = 0,
        w = 60,
        h = 44,
        on_click = on_back_click
    })
    airui.label({
        parent = back_btn,
        x = 5,
        y = 10,
        w = 50,
        h = 24,
        text = "< 返回",
        font_size = 16,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题
    airui.label({
        parent = header,
        x = 60,
        y = 8,
        w = 360,
        h = 28,
        text = "网络状态",
        font_size = 20,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0,
        y = 44,
        w = 480,
        h = 228,
        color = COLOR_BG
    })

    -- 4G信号卡片
    local card1 = airui.container({
        parent = content,
        x = 10,
        y = 8,
        w = 460,
        h = 50,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = card1,
        x = 10,
        y = 4,
        w = 80,
        h = 18,
        text = "4G信号",
        font_size = 13,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    signal_label = airui.label({
        parent = card1,
        x = 10,
        y = 24,
        w = 440,
        h = 20,
        text = "获取中...",
        font_size = 17,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- WiFi状态卡片
    local card2 = airui.container({
        parent = content,
        x = 10,
        y = 66,
        w = 460,
        h = 50,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = card2,
        x = 10,
        y = 4,
        w = 80,
        h = 18,
        text = "WiFi",
        font_size = 13,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    wifi_label = airui.label({
        parent = card2,
        x = 10,
        y = 24,
        w = 440,
        h = 20,
        text = "未连接",
        font_size = 17,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 以太网1状态卡片
    local card3 = airui.container({
        parent = content,
        x = 10,
        y = 124,
        w = 460,
        h = 42,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = card3,
        x = 10,
        y = 11,
        w = 80,
        h = 20,
        text = "以太网1",
        font_size = 13,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    eth1_label = airui.label({
        parent = card3,
        x = 95,
        y = 11,
        w = 355,
        h = 20,
        text = "获取中...",
        font_size = 15,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 以太网2状态卡片
    local card4 = airui.container({
        parent = content,
        x = 10,
        y = 172,
        w = 460,
        h = 42,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = card4,
        x = 10,
        y = 11,
        w = 80,
        h = 20,
        text = "以太网2",
        font_size = 13,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    eth2_label = airui.label({
        parent = card4,
        x = 95,
        y = 11,
        w = 355,
        h = 20,
        text = "获取中...",
        font_size = 15,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    sys.subscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    sys.subscribe("STATUS_ETH_UPDATED", on_status_eth_updated)
    -- 主动查询一次各网络状态, 确保页面打开时显示最新值
    sys.publish("NETWORK_STATUS_QUERY")
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
    signal_label = nil
    wifi_label = nil
    eth1_label = nil
    eth2_label = nil
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_status_wifi_updated)
    sys.unsubscribe("STATUS_ETH_UPDATED", on_status_eth_updated)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    -- 重新获得焦点时也主动刷新一次, 保证数据最新
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus()
    -- 不需要特殊处理
end

--[[
OPEN_NETWORK_WIN 消息处理器

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

sys.subscribe("OPEN_NETWORK_WIN", open_handler)
