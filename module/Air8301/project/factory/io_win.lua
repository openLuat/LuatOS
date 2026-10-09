--[[
@module  io_win
@summary IO 分区页（DI / DO / 继电器 / 蜂鸣器 / 状态灯）（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
方案A 界面范式中的「IO」分区页：
  顶部状态条 + 中部功能磁贴（3×2，5 项）+ 底部 Dock 分区导航。
每个磁贴 = 图标 + 名称 + 实时状态摘要 + 右上状态指示灯。
点击磁贴进入对应功能详情页。

分区划分（业务模式全部页面）：
  主页 —— 时间与天气仪表盘（idle_win）
  通信 —— 蜂窝 / WiFi / RS485-1 / RS485-2 / 以太网 / Modbus（comm_win）
  IO   —— 本页：DI / DO / 继电器 / 蜂鸣器 / 状态灯
  系统 —— 看门狗 / Flash / 系统信息 / 远程升级 / RELOAD（sys_win）

数据来源（既有消息接口）：
  DI_STATUS_CHANGED(di1, di2)    DI1/DI2 电平
  RELAY_STATUS_UPDATE(state)     继电器 4 路状态

@note 本页只承载 Air8301 实际支持的功能；DO 无状态回读消息，故展示引脚映射。
]]

local theme = require "ui_theme"
require "theme"   -- 设置全局 T（提供按键音兜底 T.with_beep）

local win_id = nil
local main_container
local status                       -- 状态条句柄
local clock_timer = nil

-- 磁贴句柄：sub / dot 可动态刷新
local tile_di, tile_relay

-- 当前分区标识与切换防抖标志
local NAV_KEY = "io"
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

local function on_di_click()       sys.publish("OPEN_DI_WIN")       end
local function on_do_click()       sys.publish("OPEN_DO_WIN")       end
local function on_relay_click()    sys.publish("OPEN_RELAY_WIN")    end
local function on_buzzer_click()   sys.publish("OPEN_BUZZER_WIN")   end
local function on_led_click()      sys.publish("OPEN_LED_WIN")      end

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
DI 电平更新

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
    set_tile_state(tile_di, "DI1 " .. (on1 and "ON" or "OFF") .. " | DI2 " .. (on2 and "ON" or "OFF"), color)
end

--[[
继电器状态更新

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
    set_tile_state(tile_relay, tostring(n) .. "/4 接通", color)
end

-- ==================== UI 构建 ====================

--[[
创建 IO 分区页 UI

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

    -- 5 项依次摆放（3 列 × 2 行，第 6 格留空）
    local cells = {
        { icon = "/luadb/hw_di.png",       text = "DI 输入",  sub = "等待状态...", dot = theme.C.t3, on_click = T.with_beep(on_di_click) },
        { icon = "/luadb/hw_do.png",       text = "DO 输出",  sub = "GPIO24 | 25", dot = theme.C.t3, on_click = T.with_beep(on_do_click) },
        { icon = "/luadb/hw_reload.png",   text = "继电器",   sub = "读取中...",   dot = theme.C.t3, on_click = T.with_beep(on_relay_click) },
        { icon = "/luadb/hw_buzzer.png",   text = "蜂鸣器",   sub = "按键音测试",  dot = theme.SEM.info, on_click = T.with_beep(on_buzzer_click) },
        { icon = "/luadb/hw_led.png",      text = "状态灯",   sub = "4G | WiFi",   dot = theme.SEM.info, on_click = T.with_beep(on_led_click) },
    }
    local sect = theme.pal(NAV_KEY)       -- IO 分区配色（绿）
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

    tile_di    = handles[1]
    tile_relay = handles[3]
end

-- ==================== 窗口生命周期 ====================

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("io_win", "[UI-MARK] IO 分区页 v1.0 已加载（品牌标题 + 事务式分区导航）")
    create_ui()
    sys.subscribe("DI_STATUS_CHANGED", on_di_changed)
    sys.subscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    -- 主动回读一次继电器状态
    sys.publish("RELAY_SET_REQ", nil, "read")
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
    tile_di, tile_relay = nil, nil
    sys.unsubscribe("DI_STATUS_CHANGED", on_di_changed)
    sys.unsubscribe("RELAY_STATUS_UPDATE", on_relay_status_update)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_clock()
    sys.publish("RELAY_SET_REQ", nil, "read")
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_IO_WIN 消息处理器

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
