--[[
@module  prod_sysinfo_win
@summary 系统信息页面（产测模式），显示固件版本、运行时间、RAM、文件系统信息
@version 1.0
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_SYSINFO_WIN；去掉恢复出厂按钮（产测用 U 盘/指令 RST#）

@usage
本页面只读展示系统信息：
1、固件版本（VERSION）
2、运行时间（mcu.ticks 转换时分秒）
3、内存使用（rtos.meminfo 多值返回，字节转MB，系统内存+Lua内存）
4、文件系统信息（订阅 FLASH_MOUNT_STATUS）
页面打开期间每 2 秒自动刷新运行时间与内存。

视觉：ui_theme 深色玻璃态（4 条键值行，无操作按钮）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local ver_label, uptime_label, ram_label, flash_label

-- 自动刷新定时器
local refresh_timer = nil

-- 布局常量（内容区 464×210：4×40 + 3×8 = 184，上下居中）
local ROW_H   = 40
local ROW_GAP = 8

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
更新系统信息显示

@local
@function refresh_sysinfo
]]
local function refresh_sysinfo()
    -- 版本号
    local ver = VERSION or "未知"
    if ver_label then
        ver_label:set_text(tostring(ver))
        ver_label:set_color(theme.C.t1)
    end

    -- 运行时间（mcu.ticks → 时分秒）
    local ticks = mcu.ticks() or 0
    local total_sec = math.floor(ticks / 1000)
    local hours = math.floor(total_sec / 3600)
    local mins = math.floor((total_sec % 3600) / 60)
    local secs = total_sec % 60
    if uptime_label then
        uptime_label:set_text(string.format("%02d:%02d:%02d", hours, mins, secs))
        uptime_label:set_color(theme.C.t1)
    end

    -- RAM信息: rtos.meminfo 返回两个值(总, 已用), 单位字节
    -- 防御: 某些固件可能只返回部分值, 用 or 0 兜底避免格式化报错
    local total_sys, used_sys = rtos.meminfo("sys")
    local total_lua, used_lua = rtos.meminfo("lua")
    total_sys = total_sys or 0
    used_sys = used_sys or 0
    total_lua = total_lua or 0
    used_lua = used_lua or 0

    if ram_label then
        local sys_line, lua_line
        if total_sys > 0 then
            sys_line = string.format("%.1f/%.1f MB", used_sys / 1024 / 1024, total_sys / 1024 / 1024)
        else
            sys_line = "不支持"
        end
        if total_lua > 0 then
            lua_line = string.format("%.1f/%.1f MB", used_lua / 1024 / 1024, total_lua / 1024 / 1024)
        else
            lua_line = "不支持"
        end
        ram_label:set_text(string.format("系统 %s %s Lua %s", sys_line, theme.CHAR.sep, lua_line))
        ram_label:set_color(theme.C.t1)
    end
end

--[[
Flash 挂载状态回调: 更新文件系统信息显示

@local
@function on_flash_mount_status
]]
local function on_flash_mount_status(mounted, total_kb, used_kb)
    if not exwin.is_active(win_id) then return end

    if flash_label then
        if mounted and total_kb and total_kb > 0 then
            local total_mb = total_kb / 1024
            local used_mb = used_kb / 1024
            local free_mb = total_mb - used_mb
            flash_label:set_text(string.format("可用 %.1f MB %s 共 %.1f MB",
                free_mb, theme.CHAR.sep, total_mb))
            flash_label:set_color(theme.SEM.success)
        else
            -- 产测模式不常驻挂载：Flash 由 prod_test 的 FLASH_TEST 指令按需挂载，
            -- 此处是「按需状态」而非故障，用琥珀提示色，避免测试员误判
            flash_label:set_text("按需挂载（产测）")
            flash_label:set_color(theme.SEM.warning)
        end
    end
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "系统信息", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- 上下居中：总高 184，内容区 210，顶部留白 13
    local y = ctx.y + math.floor((ctx.h - (ROW_H * 4 + ROW_GAP * 3)) / 2)

    local _, l_ver = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 110,
        label = "固件版本", value = "--" })
    ver_label = l_ver
    y = y + ROW_H + ROW_GAP

    local _, l_uptime = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 110,
        label = "运行时间", value = "00:00:00" })
    uptime_label = l_uptime
    y = y + ROW_H + ROW_GAP

    local _, l_ram = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 110,
        label = "内存", value = "加载中..." })
    ram_label = l_ram
    y = y + ROW_H + ROW_GAP

    local _, l_flash = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 110,
        label = "文件系统", value = "加载中..." })
    flash_label = l_flash

    -- 刷新信息
    refresh_sysinfo()
end

--[[
系统信息自动刷新回调：每2秒刷新运行时间+内存

@local
@function refresh_timer_cb
]]
local function refresh_timer_cb()
    if exwin.is_active(win_id) then
        refresh_sysinfo()
    end
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("FLASH_MOUNT_STATUS", on_flash_mount_status)
    -- 主动请求一次 Flash 状态
    sys.publish("REQUEST_STATUS_REFRESH")
    -- 启动自动刷新(每2秒刷新运行时间+内存)
    if not refresh_timer then
        refresh_timer = sys.timerLoopStart(refresh_timer_cb, 2000)
    end
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if refresh_timer then
        sys.timerStop(refresh_timer)
        refresh_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    ver_label = nil
    uptime_label = nil
    ram_label = nil
    flash_label = nil
    sys.unsubscribe("FLASH_MOUNT_STATUS", on_flash_mount_status)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    if exwin.is_active(win_id) then
        refresh_sysinfo()
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
OPEN_PROD_SYSINFO_WIN 消息处理器

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

sys.subscribe("OPEN_PROD_SYSINFO_WIN", open_handler)
