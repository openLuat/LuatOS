--[[
@module  io_win
@summary IO 分区页（DI / DO / 继电器 / 蜂鸣器 / 状态灯）（8301出厂固件）
@version 1.1
@date    2026.10.10
@author  江访

@usage
方案A 界面范式中的「IO」分区页：
  顶部状态条 + 中部功能磁贴（3×2，5 项）+ 底部 Dock 分区导航。
每个磁贴 = 图标 + 名称 + 实时状态摘要。点击磁贴进入对应功能详情页。

分区划分（业务模式全部页面）：
  主页 —— 时间与天气仪表盘（idle_win）
  通信 —— 网络状态 / WiFi / RS485-1 / Modbus / 多网融合（comm_win）
  IO   —— 本页：DI / DO / 继电器 / 蜂鸣器 / 状态灯
  系统 —— 看门狗 / Flash / 系统信息 / 远程升级 / RELOAD（sys_win）

数据来源（既有消息接口）：
  DI_STATUS_CHANGED(di1, di2)    DI1/DI2 电平
  RELAY_STATUS_UPDATE(state)     继电器 4 路状态

@note 本页只承载 Air8301 实际支持的功能；DO 无状态回读消息，故展示引脚映射。
@note 变更 26（体积优化）：时钟刷新 / Dock 导航 / 磁贴状态刷新 / 磁贴网格铺设改由 ui_theme
      公共样板提供，页面元素、几何、配色与消息接口均未变化。
]]

local theme = require "ui_theme"
require "theme"   -- 设置全局 T（提供按键音兜底 T.with_beep）

local win_id = nil
local main_container
local status                       -- 状态条句柄
local clock_timer = nil

-- 磁贴句柄：sub / 灯色可动态刷新
local tile_di, tile_relay

-- 当前分区标识
local NAV_KEY = "io"

-- 状态条时钟刷新（公共样板）
local refresh_clock = theme.make_clock(function() return win_id end, function() return status end)

-- Dock 分区导航（公共样板：400ms 防抖 + exwin 菜单切换事务）
local on_nav = theme.make_nav(NAV_KEY, function() return win_id end)

-- ==================== 磁贴点击回调（命名函数，禁止匿名函数） ====================

local function on_di_click()       sys.publish("OPEN_DI_WIN")       end
local function on_do_click()       sys.publish("OPEN_DO_WIN")       end
local function on_relay_click()    sys.publish("OPEN_RELAY_WIN")    end
local function on_buzzer_click()   sys.publish("OPEN_BUZZER_WIN")   end
local function on_led_click()      sys.publish("OPEN_LED_WIN")      end

-- ==================== 状态刷新 ====================

--[[DI 电平更新

@local
@function on_di_changed
@param di1 number DI1 电平(0/1)
@param di2 number DI2 电平(0/1)
]]
local function on_di_changed(di1, di2)
    if not exwin.is_active(win_id) then return end
    local on1 = (di1 == 1 or di1 == true)
    local on2 = (di2 == 1 or di2 == true)
    local color = (on1 or on2) and theme.SEM.success or theme.C.t2
    theme.tile_state(tile_di, "DI1 " .. (on1 and "ON" or "OFF") .. " | DI2 " .. (on2 and "ON" or "OFF"), color)
end

--[[继电器状态更新

@local
@function on_relay_status_update
@param state table 继电器状态数组（1-based，state[i]=1 表示接通）
]]
local function on_relay_status_update(state)
    if not exwin.is_active(win_id) then return end
    if type(state) ~= "table" then return end
    local n = 0
    for i = 1, 4 do
        if state[i] == 1 then n = n + 1 end
    end
    local color = (n > 0) and theme.SEM.success or theme.C.t2
    theme.tile_state(tile_relay, tostring(n) .. "/4 接通", color)
end

-- ==================== UI 构建 ====================

--[[创建 IO 分区页 UI

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

    -- 5 项依次摆放（3 列 × 2 行，第 6 格留空）
    local cells = {
        { icon = "/luadb/hw_di.png",       text = "DI 输入",  sub = "等待状态...", dot = theme.C.t3, on_click = T.with_beep(on_di_click) },
        { icon = "/luadb/hw_do.png",       text = "DO 输出",  sub = "GPIO24 | 25", dot = theme.C.t3, on_click = T.with_beep(on_do_click) },
        { icon = "/luadb/hw_reload.png",   text = "继电器",   sub = "读取中...",   dot = theme.C.t3, on_click = T.with_beep(on_relay_click) },
        { icon = "/luadb/hw_buzzer.png",   text = "蜂鸣器",   sub = "按键音测试",  dot = theme.SEM.info, on_click = T.with_beep(on_buzzer_click) },
        { icon = "/luadb/hw_led.png",      text = "状态灯",   sub = "4G | WiFi",   dot = theme.SEM.info, on_click = T.with_beep(on_led_click) },
    }
    local handles = theme.tile_grid(ctx, cells, { nav_key = NAV_KEY })

    tile_di    = handles[1]
    tile_relay = handles[3]
end

-- ==================== 窗口生命周期 ====================

--[[窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("io_win", "[UI-MARK] IO 分区页 v1.1 已加载（公共样板下沉）")
    create_ui()
    sys.subscribe("DI_STATUS_CHANGED", on_di_changed)
    sys.subscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    -- 主动回读一次继电器状态
    sys.publish("RELAY_SET_REQ", nil, "read")
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
    tile_di, tile_relay = nil, nil
    sys.unsubscribe("DI_STATUS_CHANGED", on_di_changed)
    sys.unsubscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    win_id = nil
end

--[[窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_clock()
    sys.publish("RELAY_SET_REQ", nil, "read")
end

--[[窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[OPEN_IO_WIN 消息处理器

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

sys.subscribe("OPEN_IO_WIN", open_handler)
