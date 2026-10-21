--[[
@module  comm_win
@summary 通信分区页（网络状态 / WiFi / RS485-1 / Modbus / 多网融合）（8301出厂固件）
@version 1.0
@date    2026.10.13
@author  江访

@usage
方案A 界面范式中的「通信」分区页：
  顶部状态条 + 中部 3×2 磁贴（5 项）+ 底部 Dock 分区导航。
每个磁贴 = 图标 + 名称 + 实时状态摘要，一眼看清各通道通断。
点击磁贴进入对应功能详情页。

分区划分（业务模式全部页面）：
  主页 —— 时间与天气仪表盘（idle_win）
  通信 —— 本页：网络状态 / WiFi / RS485-1 / Modbus / 多网融合
  IO   —— DI / DO / 继电器 / 蜂鸣器 / 状态灯（io_win）
  系统 —— 看门狗 / Flash / 系统信息 / 远程升级 / RELOAD（sys_win）

数据来源（既有消息接口）：
  STATUS_SIGNAL_UPDATED(level)                  4G 信号（「网络状态」磁贴摘要）
  STATUS_WIFI_UPDATED(conn,ssid,level,rssi)     WiFi
  NET_ACTIVE_UPDATED(net_type,adapter,name)     当前生效链路（多网融合）
  NETWORK_STATUS_QUERY                          打开时主动查询

@note 本页只承载 Air8301 实际支持的功能（RS232 仅产测模式有，故业务模式通信分区不设）。
@note 变更 26（体积优化）：时钟刷新 / Dock 导航 / 磁贴状态刷新 / 磁贴网格铺设改由 ui_theme
      公共样板提供（theme.make_clock / make_nav / tile_state / tile_grid），页面元素、几何、
      配色与消息接口均未变化。
@note 变更：WiFi 磁贴副标题由原来的动态文字（未连接 / SSID）改为固定「WiFi配网」，
      与其它磁贴的固定摘要风格一致（网络状态「x 级」、RS485-1「9600」、Modbus「从站」）；
      连接状态仍由磁贴指示灯颜色表达（已连接=绿，未连接=红），功能与消息接口均未变化。
]]

local theme = require "ui_theme"
require "theme"   -- 设置全局 T（提供按键音兜底 T.with_beep）

local win_id = nil
local main_container
local status                       -- 状态条句柄
local clock_timer = nil

-- 磁贴句柄：sub / 灯色可动态刷新（5 个：网络状态 / WiFi / RS485-1 / Modbus / 多网融合）
local tile_net, tile_wifi, tile_485a, tile_modbus, tile_multi

-- 当前分区标识
local NAV_KEY = "comm"

-- 状态条时钟刷新（公共样板：仅在本页可见时刷新状态条时间）
local refresh_clock = theme.make_clock(function() return win_id end, function() return status end)

-- Dock 分区导航（公共样板：400ms 防抖 + exwin 菜单切换事务）
local on_nav = theme.make_nav(NAV_KEY, function() return win_id end)

-- ==================== 磁贴点击回调（命名函数，禁止匿名函数） ====================

-- 「网络状态」磁贴打开 network_win（原「蜂窝网络」/「以太网」两个磁贴已合并为一项）
local function on_net_click()    sys.publish("OPEN_NETWORK_WIN") end
local function on_wifi_click()   sys.publish("OPEN_WIFI_WIN")    end
local function on_485a_click()   sys.publish("OPEN_RS485_WIN")   end
local function on_modbus_click() sys.publish("OPEN_MODBUS_WIN")  end
local function on_multi_click()  sys.publish("OPEN_MULTINET_WIN") end

-- ==================== 状态刷新 ====================

--[[4G 信号更新

@local
@function on_signal_updated
@param level number 信号等级(0~5)
]]
local function on_signal_updated(level)
    if not exwin.is_active(win_id) then return end
    local text, color
    if level == nil or level == 0 then
        text, color = "无服务", theme.SEM.danger
    elseif level <= 3 then
        text, color = tostring(level) .. " 级", theme.SEM.warning
    else
        text, color = tostring(level) .. " 级", theme.SEM.success
    end
    theme.tile_state(tile_net, text, color)
    if status and status.signal then status.signal:set_color(color, 255) end
end

--[[WiFi 状态更新

@local
@function on_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi 名称
@param level number 信号等级
@param rssi number 信号强度(dBm)
]]
local function on_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    -- 磁贴副标题固定显示「WiFi配网」，与其它磁贴的固定摘要风格保持一致
    -- （RS485-1 显示「9600」、Modbus 显示「从站」）；连接状态由指示灯颜色表达。
    local color = connected and theme.SEM.success or theme.SEM.danger
    theme.tile_state(tile_wifi, "WiFi配网", color)
    if status and status.wifi then status.wifi:set_color(color, 255) end
end

--[[多网融合：当前生效链路更新（「多网融合」磁贴摘要显示当前生效网卡）

@local
@function on_active_updated
@param net_type string|nil 网卡类型字符串
@param adapter number 网卡编号
@param name string 中文网卡名
]]
local function on_active_updated(net_type, adapter, name)
    if not exwin.is_active(win_id) then return end
    local text = name or "查询中"
    local color = theme.SEM.info
    if text == "无可用网络" then color = theme.SEM.danger end
    theme.tile_state(tile_multi, text, color)
end

--[[RS485-1 从站请求/应答（业务模式 RS485-1 = Modbus RTU 从站，摘要显示"通信中"）

数据源：MODBUS_RTU_REQ（rtu_slave_regmap.lua 每次请求/应答后发布）。
v1.4 修正：原订阅 RS485_DATA_RECEIVED，该消息在业务模式下没有任何发布方
          （仅产测 prod_rs485_app 发布），磁贴永远不会变为"通信中"。

@local
@function on_rtu_req
@param text string "[RTU] 请求:xx  应答:xx"
]]
local function on_rtu_req(text)
    if not exwin.is_active(win_id) then return end
    theme.tile_state(tile_485a, "通信中", theme.SEM.success)
end

-- ==================== UI 构建 ====================

--[[创建通信分区页 UI

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.shell({
        title = theme.BRAND,   -- 左上角统一显示「合宙工业网关Air8301」
        active = NAV_KEY,
        on_nav = on_nav,
        time = os.date("%H:%M"),
    })
    main_container = ctx.base
    status = ctx.status

    -- 依次摆放 5 个磁贴（3 列 × 2 行，第 6 格留空）
    local cells = {
        { icon = "/luadb/hw_network.png",  text = "网络状态", sub = "查询中...", dot = theme.C.t3, on_click = T.with_beep(on_net_click) },
        { icon = "/luadb/hw_wifi.png",     text = "WiFi",     sub = "WiFi配网",  dot = theme.C.t3, on_click = T.with_beep(on_wifi_click) },
        { icon = "/luadb/hw_rs485.png",    text = "RS485-1",  sub = "9600",      dot = theme.SEM.success, on_click = T.with_beep(on_485a_click) },
        { icon = "/luadb/hw_modbus.png",   text = "Modbus",   sub = "从站",      dot = theme.SEM.info, on_click = T.with_beep(on_modbus_click) },
        { icon = "/luadb/hw_multinet.png", text = "多网融合", sub = "查询中...", dot = theme.C.t3, on_click = T.with_beep(on_multi_click) },
    }
    local handles = theme.tile_grid(ctx, cells, { nav_key = NAV_KEY })

    tile_net    = handles[1]
    tile_wifi   = handles[2]
    tile_485a   = handles[3]
    tile_modbus = handles[4]
    tile_multi  = handles[5]
end

-- ==================== 窗口生命周期 ====================

--[[窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("comm_win", "[UI-MARK] 通信分区页 v1.4 已加载（RS485-1 磁贴改订阅 MODBUS_RTU_REQ）")
    create_ui()
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.subscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.subscribe("MODBUS_RTU_REQ", on_rtu_req)
    sys.subscribe("NET_ACTIVE_UPDATED", on_active_updated)
    sys.publish("NETWORK_STATUS_QUERY")
    clock_timer = sys.timerLoopStart(refresh_clock, 1000)
end

--[[窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if clock_timer then
        sys.timerStop(clock_timer)
        clock_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status = nil
    tile_net, tile_wifi, tile_485a, tile_modbus, tile_multi = nil, nil, nil, nil, nil
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.unsubscribe("MODBUS_RTU_REQ", on_rtu_req)
    sys.unsubscribe("NET_ACTIVE_UPDATED", on_active_updated)
    win_id = nil
end

--[[窗口获得焦点回调：刷新时钟并重新查询网络状态

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_clock()
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[OPEN_COMM_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end
end

sys.subscribe("OPEN_COMM_WIN", open_handler)
