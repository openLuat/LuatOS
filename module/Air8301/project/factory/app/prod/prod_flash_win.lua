--[[
@module  prod_flash_win
@summary Flash存储页面（产测模式），显示挂载状态与芯片容量
@version 1.0
@date    2026.10.09
@author  江访
@version_note
  v1.2 产测模式改为「有值就显示、无值就显示 --」：
       1、移除「文件系统」行（产测不展示文件系统信息，与系统信息页保持一致）；
       2、挂载状态 / 芯片容量两行常显：取得真实值就写真实值，取不到值就写 "--"，
          不再整行隐藏，也不再出现「按需挂载（产测）」「按需读取」这类占位文案。
  v1.1 产测模式曾改为「按需显示」（取到值才显示该行，取不到整行隐藏）
  v1.0 产测专属：消息名前缀 OPEN_PROD_FLASH_WIN，避免与业务页面冲突

@usage
本页面只读展示外部 SPI Flash 存储信息：
1、挂载状态（取得真实挂载成功后显示「已挂载」，未取得过真实值显示 "--"）
2、芯片容量（lf.getInfo 读取的物理容量，未取得过真实值显示 "--"）

产测模式下 Flash 由 prod_test.lua 的 FLASH_TEST 指令「按需挂载 → 写读 → 卸载」，页面平时取不到
真实值：此时两行显示 "--"；执行过 FLASH_TEST 后显示最近一次取得的真实值（缓存为模块级，
跨页面实例保留，重开页面结果不丢失）。

数据来源：prod_test.lua 在 FLASH_TEST 挂载成功后 sys.publish("FLASH_MOUNT_STATUS", ...) 上报；
页面打开时发布 REQUEST_STATUS_REFRESH 主动拉取。

视觉：ui_theme 深色玻璃态（键值行，语义色表达挂载状态）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container
local status_label, chip_label

-- 布局常量（内容区 464×208：2×48 + 1×8 = 104，上下居中）
local ROW_H   = 48
local ROW_GAP = 8

-- 无真实值时的占位符
local PLACEHOLDER = "--"

-- 最近一次取得的真实值缓存（模块级，跨页面实例保留）
-- 产测下 Flash 按需挂载，页面打开瞬间取不到值；缓存保证已测过的结果不会随页面关闭而丢失
local cache_mounted     = false   -- 是否曾测得 Flash 挂载成功
local cache_capacity_kb = 0       -- 最近一次测得的芯片容量KB

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
格式化芯片容量显示文本

@local
@function format_capacity
@param capacity_kb number 芯片容量KB
@return string 显示文本（>=1024MB 用 GB，否则用 MB）
]]
local function format_capacity(capacity_kb)
    local cap_mb = capacity_kb / 1024
    if cap_mb >= 1024 then
        return string.format("%.2f GB", cap_mb / 1024)
    end
    return string.format("%.0f MB", cap_mb)
end

--[[
刷新两行显示：有真实值就写真实值，没有就写 "--"

@local
@function refresh_display
]]
local function refresh_display()
    if status_label then
        if cache_mounted then
            status_label:set_text("已挂载")
            status_label:set_color(theme.SEM.success)
        else
            status_label:set_text(PLACEHOLDER)
            status_label:set_color(theme.C.t2)
        end
    end

    if chip_label then
        if cache_capacity_kb > 0 then
            chip_label:set_text(format_capacity(cache_capacity_kb))
            chip_label:set_color(theme.C.t1)
        else
            chip_label:set_text(PLACEHOLDER)
            chip_label:set_color(theme.C.t2)
        end
    end
end

--[[
Flash 挂载状态回调: 记录真实值并刷新显示

页面只关心「是否挂载成功」与「芯片容量」两项：
  1、mounted == true 时记下挂载成功，显示「已挂载」；
  2、capacity_kb > 0 时记下芯片容量并显示；
  3、其余情况两行保持 "--"（不写任何占位文案，也不隐藏整行）。

@local
@function on_flash_mount_status
@param mounted boolean 是否挂载成功
@param total_kb number 文件系统总容量KB（本页不再展示文件系统，保留入参兼容既有消息）
@param used_kb number 文件系统已用KB（本页不再展示文件系统，保留入参兼容既有消息）
@param capacity_kb number Flash芯片总容量KB
]]
local function on_flash_mount_status(mounted, total_kb, used_kb, capacity_kb)
    if not exwin.is_active(win_id) then return end

    if mounted == true then
        cache_mounted = true
    end
    if capacity_kb and capacity_kb > 0 then
        cache_capacity_kb = capacity_kb
    end

    refresh_display()
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "Flash存储", on_back = on_back_click })
    main_container = ctx.base

    -- 两行整体在内容区垂直居中
    local total_h = ROW_H * 2 + ROW_GAP
    local y0 = ctx.y + math.floor((ctx.h - total_h) / 2)
    if y0 < ctx.y then y0 = ctx.y end

    local _, l_status = theme.kv_row(ctx.base, {
        x = ctx.x, y = y0, w = ctx.w, h = ROW_H, label_w = 100,
        label = "挂载状态", value = PLACEHOLDER, value_color = theme.C.t2 })
    status_label = l_status

    local _, l_chip = theme.kv_row(ctx.base, {
        x = ctx.x, y = y0 + ROW_H + ROW_GAP, w = ctx.w, h = ROW_H, label_w = 100,
        label = "芯片容量", value = PLACEHOLDER, value_color = theme.C.t2 })
    chip_label = l_chip

    -- 用缓存中的真实值刷新（有就写，没有保持 "--"）
    refresh_display()
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    -- 有效值缓存为模块级、跨页面实例保留：重新打开页面仍显示最近一次取得的真实结果
    -- （产测模式下 flash_app 不参与挂载，页面无法在打开瞬间重新取得真实值）
    create_ui()
    sys.subscribe("FLASH_MOUNT_STATUS", on_flash_mount_status)
    -- 主动请求一次 Flash 状态(flash_app 只在开机发布一次, 页面打开时需重新拉取)
    sys.publish("REQUEST_STATUS_REFRESH")
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
    status_label, chip_label = nil, nil
    -- 注意：不清空 cache_mounted / cache_capacity_kb
    --       这两项为模块级有效值缓存，跨页面实例保留（重开页面仍显示最近一次真实结果）
    sys.unsubscribe("FLASH_MOUNT_STATUS", on_flash_mount_status)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    -- 重新进入页面时刷新 Flash 状态
    if exwin.is_active(win_id) then
        sys.publish("REQUEST_STATUS_REFRESH")
    end
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
OPEN_PROD_FLASH_WIN 消息处理器

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

sys.subscribe("OPEN_PROD_FLASH_WIN", open_handler)
