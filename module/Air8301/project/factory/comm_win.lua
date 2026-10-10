--[[
@module  comm_win
@summary 通信分区页（网络状态 / WiFi / RS485-1 / Modbus / 多网融合）（8301出厂固件）
@version 1.1
@date    2026.10.10
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
@note 变更 22：通信分区磁贴由 6 格调整为 5 格（第 6 格留空）——原「蜂窝网络」与「以太网」
      两个磁贴落点同为 network_win（功能完全重复），已合并为单一「网络状态」磁贴
      （沿用 hw_network.png）；同时 Modbus 换独立图标 hw_modbus.png、
      多网融合换 hw_multinet.png，消除图标撞图。
]]

local theme = require "ui_theme"
require "theme"   -- 设置全局 T（提供按键音兜底 T.with_beep）

local win_id = nil
local main_container
local status                       -- 状态条句柄
local clock_timer = nil

-- 磁贴句柄：name/sub/dot 可动态刷新（变更 22 起为 5 个：网络状态 / WiFi / RS485-1 / Modbus / 多网融合）
local tile_net, tile_wifi, tile_485a, tile_modbus, tile_multi

-- 当前分区标识与切换防抖标志
local NAV_KEY = "comm"
local nav_busy = false

-- 磁贴网格几何（内容区 464×182：3 列 150×3 + 6×2；2 行 88×2 + 6）
local COLS, ROWS = 3, 2
local GAP = 6

-- ==================== 时钟 ====================

--[[
刷新状态条时钟（每秒触发）

@local
@function refresh_clock
]]
local function refresh_clock()
    -- 仅在本页可见（栈顶）时刷新，避免窗口失焦后仍反复重绘
    if not exwin.is_active(win_id) then return end
    if status and status.time then
        status.time:set_text(os.date("%H:%M"))
    end
end

-- ==================== 磁贴点击回调（命名函数，禁止匿名函数） ====================

-- 「网络状态」磁贴（原「蜂窝网络」）打开 network_win；
-- 原独立「以太网」磁贴与它落点完全相同（同为 OPEN_NETWORK_WIN），变更 22 已合并，故删除 on_eth_click
local function on_net_click()    sys.publish("OPEN_NETWORK_WIN") end
local function on_wifi_click()   sys.publish("OPEN_WIFI_WIN")    end
local function on_485a_click()   sys.publish("OPEN_RS485_WIN")   end
local function on_modbus_click() sys.publish("OPEN_MODBUS_WIN")  end
local function on_multi_click()  sys.publish("OPEN_MULTINET_WIN") end

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
  新：不关自己，而是向 exwin 声明「一级菜单切换事务」（宿主 = 常驻首页 idle_win），
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

-- ==================== 状态刷新 ====================

-- 统一样式化磁贴状态：摘要文字 + 指示灯颜色
local function set_tile_state(handle, sub, color)
    if not handle then return end
    if handle[2] then handle[2]:set_text(sub) end
    if handle[3] then handle[3]:set_color(color, 255) end
end

--[[
4G 信号更新

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
    set_tile_state(tile_net, text, color)
    if status and status.signal then status.signal:set_color(color, 255) end
end

--[[
WiFi 状态更新

@local
@function on_wifi_updated
@param connected boolean 是否已连接
@param ssid string WiFi 名称
@param level number 信号等级
@param rssi number 信号强度(dBm)
]]
local function on_wifi_updated(connected, ssid, level, rssi)
    if not exwin.is_active(win_id) then return end
    local text, color
    if connected then
        text = tostring(ssid or "已连接")
        if #text > 8 then text = string.sub(text, 1, 8) end
        color = theme.SEM.success
    else
        text, color = "未连接", theme.SEM.danger
    end
    set_tile_state(tile_wifi, text, color)
    if status and status.wifi then status.wifi:set_color(color, 255) end
end

-- （变更 22 已删除原「以太网」磁贴：它与「蜂窝网络」磁贴落点相同、功能重复。
--   原 on_eth_updated 回调与 STATUS_ETH_UPDATED 订阅一并移除；以太网（网口1/2）状态
--   仍由 network_win（「网络状态」页）统一展示，功能无丢失。）

--[[
多网融合：当前生效链路更新（「多网融合」磁贴摘要显示当前生效网卡）

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
    set_tile_state(tile_multi, text, color)
end

--[[
RS485 数据接收（业务模式仅 RS485-1 开放，摘要显示"通信中"）

@local
@function on_rs485_received
@param port number 端口号(1或2)
@param data string 接收数据
]]
local function on_rs485_received(port, data)
    if not exwin.is_active(win_id) then return end
    -- 业务模式只有 RS485-1 开放；RS485-2(UART11) 已由继电器主站占用，不再展示
    if port == 1 then
        set_tile_state(tile_485a, "通信中", theme.SEM.success)
    end
end

-- ==================== UI 构建 ====================

--[[
创建通信分区页 UI

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

    local cw = math.floor((ctx.w - GAP * (COLS - 1)) / COLS)
    local ch = math.floor((ctx.h - GAP * (ROWS - 1)) / ROWS)

    -- 依次摆放 5 个磁贴（3 列 × 2 行，第 6 格留空）
    -- 变更 22：「蜂窝网络」+「以太网」合并为「网络状态」（两者本就打开同一页面）；
    --          Modbus 换 hw_modbus.png、多网融合换 hw_multinet.png，四类磁贴不再撞图
    local cells = {
        { icon = "/luadb/hw_network.png",  text = "网络状态", sub = "查询中...", dot = theme.C.t3, on_click = T.with_beep(on_net_click) },
        { icon = "/luadb/hw_wifi.png",     text = "WiFi",     sub = "查询中...", dot = theme.C.t3, on_click = T.with_beep(on_wifi_click) },
        { icon = "/luadb/hw_rs485.png",    text = "RS485-1",  sub = "9600",      dot = theme.SEM.success, on_click = T.with_beep(on_485a_click) },
        { icon = "/luadb/hw_modbus.png",   text = "Modbus",   sub = "从站",      dot = theme.SEM.info, on_click = T.with_beep(on_modbus_click) },
        { icon = "/luadb/hw_multinet.png", text = "多网融合", sub = "查询中...", dot = theme.C.t3, on_click = T.with_beep(on_multi_click) },
    }
    local sect = theme.pal(NAV_KEY)       -- 通信分区配色（青）
    local handles = {}
    for i, c in ipairs(cells) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local x = ctx.x + col * (cw + GAP)
        local y = ctx.y + row * (ch + GAP)
        local _, _, sub_label, dot = theme.tile(ctx.base, {
            x = x, y = y, w = cw, h = ch,
            icon = c.icon, text = c.text, sub = c.sub, dot = c.dot,
            accent_soft = sect.soft, accent_line = sect.line,
            on_click = c.on_click,
        })
        handles[i] = { nil, sub_label, dot }
    end

    tile_net    = handles[1]
    tile_wifi   = handles[2]
    tile_485a   = handles[3]
    tile_modbus = handles[4]
    tile_multi  = handles[5]
end

-- ==================== 窗口生命周期 ====================

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("comm_win", "[UI-MARK] 通信分区页 v1.1 已加载（网络状态磁贴合并 + 图标差异化）")
    create_ui()
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_signal_updated)
    sys.subscribe("STATUS_WIFI_UPDATED", on_wifi_updated)
    sys.subscribe("RS485_DATA_RECEIVED", on_rs485_received)
    sys.subscribe("NET_ACTIVE_UPDATED", on_active_updated)
    sys.publish("NETWORK_STATUS_QUERY")
    clock_timer = sys.timerLoopStart(refresh_clock, 1000)
end

--[[
窗口销毁回调

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
    sys.unsubscribe("RS485_DATA_RECEIVED", on_rs485_received)
    sys.unsubscribe("NET_ACTIVE_UPDATED", on_active_updated)
    win_id = nil
end

--[[
窗口获得焦点回调：刷新时钟并重新查询网络状态

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_clock()
    sys.publish("NETWORK_STATUS_QUERY")
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_COMM_WIN 消息处理器

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
