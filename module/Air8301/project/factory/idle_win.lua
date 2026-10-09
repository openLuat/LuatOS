--[[
@module  idle_win
@summary 总览首页·实时状态仪表盘（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
界面范式（方案A：仪表盘 + 底部 Dock 分区导航）：
本页由「14 项功能磁贴总菜单」重构为「实时状态仪表盘」，信息架构层级如下：
  顶部状态条 —— 标题 + 时间 + 信号/WiFi/告警三个指示灯
  中部 2×2  —— 蜂窝网络 / RS485-1 / 继电器 / DO 输出 四张实时状态卡
  底部 Dock  —— 总览 / 通信 / IO / 系统 四分区切换（当前分区琥珀高亮）

交互：
  - 点击任意状态卡 → 进入对应功能详情页
      （OPEN_NETWORK_WIN / OPEN_RS485_WIN / OPEN_RELAY_WIN / OPEN_DO_WIN）
  - 点击 Dock 分区  → 关闭本页并切换到目标分区页

数据来源（全部为既有消息接口，本页只做订阅展示，不做业务逻辑）：
  STATUS_SIGNAL_UPDATED(level)            4G 信号等级
  STATUS_WIFI_UPDATED(conn,ssid,lv,rssi)  WiFi 状态（仅驱动状态条指示灯）
  RS485_DATA_RECEIVED(port, data)         RS485 接收（本页仅统计接收帧数）
  RELAY_STATUS_UPDATE(state)              继电器 4 路状态（stat_card 显示接通路数）
  NETWORK_STATUS_QUERY                    打开页面时主动查询一次网络状态

@note
  1) 本页只承载 Air8301 实际支持的功能，不引入 8601 等大屏机型才有的应用；
  2) DO 输出无「状态回读」消息（do_app 只收 DO_SET_REQUEST、不回发），
     故 DO 卡片展示的是引脚映射与入口，不伪造实时电平；如需实时电平须新增回读协议。
]]

local theme = require "ui_theme"
require "theme"   -- 设置全局 T（提供按键音兜底 T.with_beep）

local win_id = nil
local main_container
local status                                          -- 状态条句柄（time/signal/wifi/alarm）
local card_net, card_rs485, card_relay, card_do        -- 四张状态卡句柄
local clock_timer = nil

-- RS485-1 接收帧计数（本页仅做概览统计）
local rs485_rx = 0

-- 当前分区标识（与 ui_theme.NAV 的 key 对应）与切换防抖标志
local NAV_KEY = "overview"
local nav_busy = false

-- 状态卡间距（内容区 464×182：2 列 229×2 + 6；2 行 88×2 + 6）
local CARD_GAP = 6

-- ==================== 时钟 ====================

--[[
刷新状态条时钟（每秒触发）

@local
@function refresh_clock
]]
local function refresh_clock()
    -- 仅在本页可见（栈顶）时刷新，避免被分区页覆盖后仍反复重绘（首页为常驻宿主，故必须加此判断）
    if not exwin.is_active(win_id) then return end
    if status and status.time then
        status.time:set_text(os.date("%H:%M"))
    end
end

-- ==================== 状态卡点击回调（命名函数，禁止匿名函数） ====================

local function on_net_card_click()   sys.publish("OPEN_NETWORK_WIN") end
local function on_485_card_click()   sys.publish("OPEN_RS485_WIN")   end
local function on_relay_card_click() sys.publish("OPEN_RELAY_WIN")   end
local function on_do_card_click()    sys.publish("OPEN_DO_WIN")      end

-- ==================== Dock 分区导航 ====================

--[[
切换防抖复位：一次切换事务开始时置忙，短暂延时后自动解除

@local
@function reset_nav_busy
]]
local function reset_nav_busy()
    nav_busy = false
end

--[[
Dock 分区点击回调（exwin v2.1 事务式切换，杜绝白屏）

切换流程（与旧实现的关键差异）：
  旧：先 close 自己 → 延迟 30ms → 再开目标页。中间窗口栈为空，必然白屏一闪；
      且连点会创建多个页面，导致栈顶错乱、is_active 判定失败（表现为「点不动」）。
  新：不关自己，而是向 exwin 声明「一级菜单切换事务」（宿主 = 本常驻首页），
      再由消息打开目标页；exwin 会在新页创建完成后自动回收宿主的旧子页。
      全程始终有窗口在屏 → 无白屏；页面数恒定 → 不堆积 → 交互不再失效。

@local
@function on_nav
@param key string 目标分区标识
@param msg string 目标分区页的打开消息
]]
local function on_nav(key, msg)
    if key == NAV_KEY or nav_busy then return end
    nav_busy = true
    local host = _G.UIFW_HOST_WIN or win_id
    if host and exwin.begin_menu_switch then
        exwin.begin_menu_switch(host)
    end
    sys.publish(msg)
    sys.timerStart(reset_nav_busy, 400)
end

-- ==================== 状态卡实时刷新 ====================

--[[
4G 信号等级更新（写入蜂窝网络卡 + 状态条信号灯）

@local
@function on_signal_updated
@param level number 信号等级(0~5)，0 表示无服务
]]
local function on_signal_updated(level)
    if not exwin.is_active(win_id) or not card_net then return end
    local text, sub, color
    if level == nil or level == 0 then
        text, sub, color = "无服务", "请检查天线与SIM卡", theme.SEM.danger
    elseif level <= 2 then
        text, sub, color = tostring(level) .. " 级 偏弱", "信号较弱", theme.SEM.warning
    elseif level == 3 then
        text, sub, color = "3 级 一般", "信号一般", theme.SEM.warning
    elseif level == 4 then
        text, sub, color = "4 级 良好", "信号良好", theme.SEM.success
    else
        text, sub, color = "5 级 极强", "信号极强", theme.SEM.success
    end
    card_net.value:set_text(text)
    card_net.value:set_color(color)
    card_net.sub:set_text(sub)
    if card_net.dot then card_net.dot:set_color(color, 255) end
    if status and status.signal then status.signal:set_color(color, 255) end
end

--[[
WiFi 状态更新（仅驱动状态条 WiFi 指示灯）

@local
@function on_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi 名称
@param level number 信号等级
@param rssi number 信号强度(dBm)
]]
local function on_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    local color = connected and theme.SEM.success or theme.C.t3
    if status and status.wifi then status.wifi:set_color(color, 255) end
end

--[[
RS485 接收统计（仅统计 Port1）

@local
@function on_rs485_received
@param port number 端口号(1或2)
@param data string 接收数据
]]
local function on_rs485_received(port, data)
    if port ~= 1 then return end
    rs485_rx = rs485_rx + 1
    if not exwin.is_active(win_id) or not card_rs485 then return end
    card_rs485.value:set_text("收 " .. tostring(rs485_rx) .. " 帧")
end

--[[
继电器状态更新：统计 4 路中接通的通道数

@local
@function on_relay_status_update
@param state table 继电器状态数组（1-based，state[i]=1 表示接通）
]]
local function on_relay_status_update(state)
    if not exwin.is_active(win_id) or not card_relay then return end
    if type(state) ~= "table" then return end
    local n = 0
    for i = 1, 4 do
        if state[i] == 1 then n = n + 1 end
    end
    local text, color
    if n == 0 then
        text, color = "全部断开", theme.C.t2
    elseif n == 4 then
        text, color = "4/4 接通", theme.SEM.success
    else
        text, color = tostring(n) .. "/4 接通", theme.SEM.warning
    end
    card_relay.value:set_text(text)
    card_relay.value:set_color(color)
    if card_relay.dot then card_relay.dot:set_color(color, 255) end
end

-- ==================== UI 构建 ====================

--[[
创建仪表盘首页 UI

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
    rs485_rx = 0

    -- 2×2 状态卡布局
    local cw = math.floor((ctx.w - CARD_GAP) / 2)
    local ch = math.floor((ctx.h - CARD_GAP) / 2)
    local x2 = ctx.x + cw + CARD_GAP
    local y2 = ctx.y + ch + CARD_GAP
    local card

    card, card_net = theme.stat_card(ctx.base, {
        x = ctx.x, y = ctx.y, w = cw, h = ch,
        title = "蜂窝网络", value = "获取中", sub = "正在查询...",
        on_click = T.with_beep(on_net_card_click),
    })

    card, card_rs485 = theme.stat_card(ctx.base, {
        x = x2, y = ctx.y, w = cw, h = ch,
        title = "RS485-1", value = "收 0 帧", sub = "9600 | 8N1 | Port1",
        on_click = T.with_beep(on_485_card_click),
    })

    card, card_relay = theme.stat_card(ctx.base, {
        x = ctx.x, y = y2, w = cw, h = ch,
        title = "继电器", value = "读取中", sub = "485 主站 | 4 路",
        value_px = theme.fs("h2"),
        on_click = T.with_beep(on_relay_card_click),
    })

    card, card_do = theme.stat_card(ctx.base, {
        x = x2, y = y2, w = cw, h = ch,
        title = "DO 输出", value = "DO1 | DO2", sub = "GPIO24 | GPIO25 点击控制",
        value_px = theme.fs("h2"),
        dot_color = theme.C.t3,
        on_click = T.with_beep(on_do_card_click),
    })
end

-- ==================== 窗口生命周期 ====================

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("idle_win", "[UI-MARK] 总览仪表盘 v1.0 已加载（品牌标题 + 事务式分区导航）")
    create_ui()
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.subscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.subscribe("RS485_DATA_RECEIVED", on_rs485_received)
    sys.subscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    -- 主动查询一次网络状态，避免打开页面时显示"获取中"
    sys.publish("NETWORK_STATUS_QUERY")
    sys.publish("RELAY_SET_REQ", nil, "read")
    clock_timer = sys.timerLoopStart(refresh_clock, 1000)
end

--[[
窗口销毁回调：释放组件、停表、退订

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
    card_net = nil
    card_rs485 = nil
    card_relay = nil
    card_do = nil
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.unsubscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.unsubscribe("RS485_DATA_RECEIVED", on_rs485_received)
    sys.unsubscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    if _G.UIFW_HOST_WIN == win_id then _G.UIFW_HOST_WIN = nil end
    win_id = nil
end

--[[
窗口获得焦点回调：刷新时钟并重新查询网络与继电器状态

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_clock()
    sys.publish("NETWORK_STATUS_QUERY")
    sys.publish("RELAY_SET_REQ", nil, "read")
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_IDLE_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    if win_id then
        -- 首页为常驻宿主：已存在时不重复建窗，仅回收其子页回到首页
        if not exwin.is_active(win_id) and exwin.close_children_of then
            exwin.close_children_of(win_id)
        end
        return
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
    -- 登记为分区切换的常驻宿主（各分区页 Dock 切换时作为 host 引用）
    _G.UIFW_HOST_WIN = win_id
end

sys.subscribe("OPEN_IDLE_WIN", open_handler)
