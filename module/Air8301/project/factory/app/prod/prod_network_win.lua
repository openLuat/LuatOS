--[[
@module  prod_network_win
@summary 网络状态页面（产测模式），显示4G信号强度、WiFi状态和以太网1/2状态
@version 1.0
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_NETWORK_WIN，避免与业务页面冲突

@usage
本页面只读展示三种网络状态：
1、4G信号强度（等级1~5或"无服务"）
2、WiFi连接状态
3、以太网1/2连接状态（分开两行显示 IP，产测模式下为 DHCP 获取）

WiFi 状态获取：
- 订阅 STATUS_WIFI_UPDATED(connected, ssid, level, rssi) 实时更新
- 打开页面时发布 NETWORK_STATUS_QUERY 主动查询一次

视觉：ui_theme 深色玻璃态（4 条键值卡片，统一 48px 行高，语义色表达连接状态）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local signal_label, wifi_label, eth1_label, eth2_label

-- 卡片行高与间距（4 行 x 48 + 3 x 6 = 210，正好铺满内容区）
local ROW_H   = 48
local ROW_GAP = 6

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
    local text, color
    if level == nil or level == 0 then
        text, color = "无服务", theme.SEM.danger
    elseif level == 1 then
        text, color = "信号：1级（微弱）", theme.SEM.danger
    elseif level == 2 then
        text, color = "信号：2级（较差）", theme.SEM.warning
    elseif level == 3 then
        text, color = "信号：3级（一般）", theme.SEM.warning
    elseif level == 4 then
        text, color = "信号：4级（良好）", theme.SEM.success
    elseif level == 5 then
        text, color = "信号：5级（极强）", theme.SEM.success
    else
        text, color = "--", theme.C.t1
    end
    signal_label:set_text(text)
    signal_label:set_color(color)
end

--[[
更新WiFi状态显示

@local
@function on_status_wifi_updated
]]
local function on_status_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    if not wifi_label then return end
    local text, color
    if connected then
        text = "已连接 " .. tostring(ssid or "") .. theme.CHAR.sep
        if rssi and rssi ~= 0 then
            text = text .. " " .. tostring(rssi) .. "dBm"
        end
        color = theme.SEM.success
    else
        text, color = "未连接", theme.SEM.danger
    end
    wifi_label:set_text(text)
    wifi_label:set_color(color)
end

--[[
更新以太网1状态显示

@local
@function update_eth1
]]
local function update_eth1(eth1_state, eth1_ip)
    if not eth1_label then return end
    if eth1_state and eth1_state > 0 then
        eth1_label:set_text("已连接 " .. theme.CHAR.sep .. " " .. (eth1_ip or ""))
        eth1_label:set_color(theme.SEM.success)
    else
        eth1_label:set_text("未连接")
        eth1_label:set_color(theme.SEM.danger)
    end
end

--[[
更新以太网2状态显示

@local
@function update_eth2
]]
local function update_eth2(eth2_state, eth2_ip)
    if not eth2_label then return end
    if eth2_state and eth2_state > 0 then
        eth2_label:set_text("已连接 " .. theme.CHAR.sep .. " " .. (eth2_ip or ""))
        eth2_label:set_color(theme.SEM.success)
    else
        eth2_label:set_text("未连接")
        eth2_label:set_color(theme.SEM.danger)
    end
end

--[[
更新以太网状态显示（ETH1/ETH2分开两行）

@local
@function on_status_eth_updated
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
    local ctx = theme.page({ title = "网络状态", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    local y = ctx.y

    local _, l1 = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label = "4G信号", value = "获取中..." })
    signal_label = l1
    y = y + ROW_H + ROW_GAP

    local _, l2 = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label = "WiFi", value = "未连接" })
    wifi_label = l2
    y = y + ROW_H + ROW_GAP

    local _, l3 = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label = "以太网1", value = "获取中..." })
    eth1_label = l3
    y = y + ROW_H + ROW_GAP

    local _, l4 = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label = "以太网2", value = "获取中..." })
    eth2_label = l4
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
OPEN_PROD_NETWORK_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    -- 单实例保护：避免同页多实例并存时互相覆盖 win_id（会使点击准入判定失效）
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_PROD_NETWORK_WIN", open_handler)
