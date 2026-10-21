--[[
@module  sysinfo_win
@summary 系统信息页面，显示固件版本、运行时间、RAM、文件系统信息（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
本页面只读展示系统信息：
1、固件版本（VERSION）
2、运行时间（mcu.ticks 转换时分秒）
3、内存使用（rtos.meminfo 多值返回，字节转MB，系统内存+Lua内存）
4、文件系统信息（订阅 FLASH_MOUNT_STATUS，外部Flash文件系统使用情况）
底部危险色"恢复出厂设置"按钮，确认后发布 FACTORY_RESET_REQUEST。
页面打开期间每 2 秒自动刷新运行时间与内存。
页面打开时发布 REQUEST_STATUS_REFRESH 主动刷新文件系统状态。

视觉：ui_theme 深色玻璃态（4 条键值行 + 底部危险色操作按钮）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local ver_label, uptime_label, ram_label, flash_label

-- 自动刷新定时器
local refresh_timer = nil

-- 布局常量（内容区 464×210）
local ROW_H   = 36
local ROW_GAP = 5
local BTN_H   = 32
local BTN_GAP = 8

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
恢复出厂设置确认对话框的"确定"按钮回调

@local
@function on_factory_reset_ok
@param self userdata msgbox对象
]]
local function on_factory_reset_ok(self)
    self:hide()
    sys.publish("FACTORY_RESET_REQUEST")
end

--[[
恢复出厂设置确认对话框的"取消"按钮回调

@local
@function on_factory_reset_cancel
@param self userdata msgbox对象
]]
local function on_factory_reset_cancel(self)
    self:hide()
end

--[[
恢复出厂设置msgbox按钮回调

@local
@function on_factory_reset_action
@param self userdata msgbox对象
@param label string 按钮文字
]]
local function on_factory_reset_action(self, label)
    if label == "确定" then
        on_factory_reset_ok(self)
    elseif label == "取消" then
        on_factory_reset_cancel(self)
    end
end

--[[
恢复出厂设置按钮点击：弹出确认对话框

@local
@function on_factory_reset_click
]]
local function on_factory_reset_click()
    if not exwin.is_active(win_id) then return end
    local mb = airui.msgbox({
        title = "警告",
        text = "确定恢复出厂设置？\n此操作将清除所有配置！",
        buttons = {"确定", "取消"},
        on_action = on_factory_reset_action
    })
    mb:show()
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

    -- 内存信息: rtos.meminfo 返回两个值(总, 已用/峰值), 单位字节
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

    -- Flash 信息由 FLASH_MOUNT_STATUS 消息更新, 此处不主动查询
end

--[[
Flash 挂载状态回调: 更新文件系统信息显示

@local
@function on_flash_mount_status
@param mounted boolean 是否挂载成功
@param total_kb number 文件系统总容量KB
@param used_kb number 文件系统已用KB
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
            flash_label:set_text("未挂载")
            flash_label:set_color(theme.SEM.danger)
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

    local y = ctx.y

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
    y = y + ROW_H + BTN_GAP

    -- 底部危险色按钮
    theme.btn(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = BTN_H,
        text = "恢复出厂设置",
        bg = theme.SEM.danger, fg = theme.C.on_amber,
        on_click = on_factory_reset_click,
    })

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
    -- 主动请求一次 Flash 状态(flash_app 只在开机发布一次, 页面打开时需重新拉取)
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
OPEN_SYSINFO_WIN 消息处理器

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

sys.subscribe("OPEN_SYSINFO_WIN", open_handler)
