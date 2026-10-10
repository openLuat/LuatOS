--[[
@module  sys_win
@summary 系统分区页（看门狗 / Flash / 系统信息 / 远程升级 / RELOAD）（8301出厂固件）
@version 1.5
@date    2026.10.10
@author  江访

@usage
方案A 界面范式中的「系统」分区页：
  顶部状态条 + 中部功能磁贴（3×2，5 项）+ 底部 Dock 分区导航。
每个磁贴 = 图标 + 名称 + 实时状态摘要。点击磁贴进入对应功能详情页。

分区划分（业务模式全部页面）：
  主页 —— 时间与天气仪表盘（idle_win）
  通信 —— 网络状态 / WiFi / RS485-1 / Modbus / 多网融合（comm_win）
  IO   —— DI / DO / 继电器 / 蜂鸣器 / 状态灯（io_win）
  系统 —— 本页：看门狗 / Flash / 系统信息 / 远程升级 / RELOAD

数据来源（既有消息接口）：
  WATCHDOG_STATUS(enabled, timeout)                   看门狗状态
  WATCHDOG_LAST_FEED(ms)                              上次喂狗时间
  FLASH_MOUNT_STATUS(mounted,total_kb,used_kb,cap_kb) Flash 挂载状态
  REQUEST_STATUS_REFRESH / WATCHDOG_GET_STATUS_REQUEST 打开时主动查询

@note 本页只承载 Air8301 实际支持的功能。
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
local tile_wdt, tile_flash

-- 当前分区标识
local NAV_KEY = "system"

-- 状态条时钟刷新（公共样板）
local refresh_clock = theme.make_clock(function() return win_id end, function() return status end)

-- Dock 分区导航（公共样板：400ms 防抖 + exwin 菜单切换事务）
local on_nav = theme.make_nav(NAV_KEY, function() return win_id end)

-- ==================== 磁贴点击回调（命名函数，禁止匿名函数） ====================

local function on_watchdog_click()  sys.publish("OPEN_WATCHDOG_WIN")  end
local function on_flash_click()     sys.publish("OPEN_FLASH_WIN")     end
local function on_sysinfo_click()   sys.publish("OPEN_SYSINFO_WIN")   end
local function on_fota_click()      sys.publish("OPEN_FOTA_WIN")      end
local function on_reload_click()    sys.publish("OPEN_RELOAD_WIN")    end

-- ==================== 状态刷新 ====================

--[[看门狗状态更新

@local
@function on_watchdog_status
@param enabled boolean 是否启用
@param timeout number 超时秒数
]]
local function on_watchdog_status(enabled, timeout)
    if not exwin.is_active(win_id) then return end
    local text, color
    if enabled then
        text, color = "已启用 " .. tostring(timeout or "--") .. "s", theme.SEM.success
    else
        text, color = "已停用", theme.C.t2
    end
    theme.tile_state(tile_wdt, text, color)
end

--[[Flash 挂载状态更新

@local
@function on_flash_mount_status
@param mounted boolean 是否已挂载
@param total_kb number 总容量(KB)
@param used_kb number 已用(KB)
@param capacity_kb number 物理容量(KB)
]]
local function on_flash_mount_status(mounted, total_kb, used_kb, capacity_kb)
    if not exwin.is_active(win_id) then return end
    local text, color
    if mounted then
        text, color = "已挂载", theme.SEM.success
    else
        text, color = "未挂载", theme.SEM.danger
    end
    theme.tile_state(tile_flash, text, color)
end

-- ==================== UI 构建 ====================

--[[创建系统分区页 UI

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
        { icon = "/luadb/hw_watchdog.png", text = "看门狗",   sub = "查询中...",   dot = theme.C.t3,    on_click = T.with_beep(on_watchdog_click) },
        { icon = "/luadb/hw_flash.png",    text = "Flash 存储", sub = "查询中...", dot = theme.C.t3,    on_click = T.with_beep(on_flash_click) },
        { icon = "/luadb/hw_sysinfo.png",  text = "系统信息", sub = "固件 | 内存",  dot = theme.SEM.info, on_click = T.with_beep(on_sysinfo_click) },
        { icon = "/luadb/hw_fota.png",     text = "远程升级", sub = "FOTA",       dot = theme.SEM.info, on_click = T.with_beep(on_fota_click) },
        { icon = "/luadb/hw_reload.png",   text = "RELOAD",  sub = "恢复出厂",    dot = theme.SEM.info, on_click = T.with_beep(on_reload_click) },
    }
    local handles = theme.tile_grid(ctx, cells, { nav_key = NAV_KEY })

    tile_wdt   = handles[1]
    tile_flash = handles[2]
end

-- ==================== 窗口生命周期 ====================

--[[窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("sys_win", "[UI-MARK] 系统分区页 v1.5 已加载（公共样板下沉）")
    create_ui()
    sys.subscribe("WATCHDOG_STATUS", on_watchdog_status)
    sys.subscribe("FLASH_MOUNT_STATUS", on_flash_mount_status)
    -- 主动查询一次看门狗与 Flash 状态
    sys.publish("WATCHDOG_GET_STATUS_REQUEST")
    sys.publish("REQUEST_STATUS_REFRESH")
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
    tile_wdt, tile_flash = nil, nil
    sys.unsubscribe("WATCHDOG_STATUS", on_watchdog_status)
    sys.unsubscribe("FLASH_MOUNT_STATUS", on_flash_mount_status)
    win_id = nil
end

--[[窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_clock()
    sys.publish("WATCHDOG_GET_STATUS_REQUEST")
    sys.publish("REQUEST_STATUS_REFRESH")
end

--[[窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[OPEN_SYS_WIN 消息处理器

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

sys.subscribe("OPEN_SYS_WIN", open_handler)
