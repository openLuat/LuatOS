--[[
@module  sysinfo_win
@summary 系统信息页面，显示固件版本、运行时间、RAM、文件系统信息
@version 1.3.0
@date    2026.08.04
@author  合宙 Air8301
@usage
本页面只读展示系统信息：
1、固件版本（VERSION）
2、运行时间（mcu.ticks 转换时分秒）
3、RAM使用（rtos.meminfo 多值返回，字节转MB，系统内存+Lua内存）
4、文件系统信息（订阅 FLASH_MOUNT_STATUS，外部Flash文件系统使用情况）
底部红色"恢复出厂设置"按钮，确认后发布 FACTORY_RESET_REQUEST。
页面打开期间每 2 秒自动刷新运行时间与内存。
页面打开时发布 REQUEST_STATUS_REFRESH 主动刷新文件系统状态。
Flash 芯片容量已移至独立页面 flash_win。
]]

local win_id = nil
local main_container, content
local uptime_label, ram_label, flash_label

-- 颜色常量
local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF
local COLOR_RED = 0xF44336
local COLOR_GREEN = 0x4CAF50

-- 自动刷新定时器
local refresh_timer = nil

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

    -- 运行时间（mcu.ticks → 时分秒）
    local ticks = mcu.ticks() or 0
    local total_sec = math.floor(ticks / 1000)
    local hours = math.floor(total_sec / 3600)
    local mins = math.floor((total_sec % 3600) / 60)
    local secs = total_sec % 60
    local uptime_str = string.format("%02d:%02d:%02d", hours, mins, secs)
    local full_uptime = "固件: " .. ver .. "\n运行时间: " .. uptime_str

    if uptime_label then
        uptime_label:set_text(full_uptime)
    end

    -- RAM信息: rtos.meminfo 返回三个值(总, 已用, 峰值), 单位字节
    -- 系统内存(SRAM/系统堆) + Lua虚拟机内存 两行显示
    -- 防御: 某些固件可能只返回部分值, 用 or 0 兜底避免格式化报错
    local total_sys, used_sys = rtos.meminfo("sys")
    local total_lua, used_lua = rtos.meminfo("lua")
    total_sys = total_sys or 0
    used_sys = used_sys or 0
    total_lua = total_lua or 0
    used_lua = used_lua or 0

    if ram_label then
        local sys_line = "系统内存: "
        local lua_line = "Lua内存: "
        if total_sys > 0 then
            sys_line = sys_line .. string.format("总 %.1f MB 已用 %.1f MB",
                total_sys / 1024 / 1024, used_sys / 1024 / 1024)
        else
            sys_line = sys_line .. "不支持"
        end
        if total_lua > 0 then
            lua_line = lua_line .. string.format("总 %.1f MB 已用 %.1f MB",
                total_lua / 1024 / 1024, used_lua / 1024 / 1024)
        else
            lua_line = lua_line .. "不支持"
        end
        ram_label:set_text(sys_line .. "\n" .. lua_line)
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
@param capacity_kb number Flash芯片总容量KB(本页不使用, 由flash_win显示)
]]
local function on_flash_mount_status(mounted, total_kb, used_kb)
    if not exwin.is_active(win_id) then return end

    -- 文件系统容量行(第2/3参): 挂载后总容量/可用容量
    if flash_label then
        if mounted and total_kb and total_kb > 0 then
            local total_mb = total_kb / 1024
            local used_mb = used_kb / 1024
            local free_mb = total_mb - used_mb
            flash_label:set_text(string.format("文件系统: 总 %.1f MB 可用 %.1f MB", total_mb, free_mb))
            flash_label:set_color(COLOR_GREEN)
        else
            flash_label:set_text("未挂载")
            flash_label:set_color(COLOR_RED)
        end
    end
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 272, color = COLOR_BG, parent = airui.screen })

    -- 顶部导航栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 44, color = COLOR_PRIMARY })

    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 0,
        y = 0,
        w = 60,
        h = 44,
        on_click = on_back_click
    })
    airui.label({
        parent = back_btn,
        x = 5,
        y = 10,
        w = 50,
        h = 24,
        text = "< 返回",
        font_size = 16,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题
    airui.label({
        parent = header,
        x = 60,
        y = 8,
        w = 360,
        h = 28,
        text = "系统信息",
        font_size = 20,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0,
        y = 44,
        w = 480,
        h = 228,
        color = COLOR_BG
    })

    -- 固件版本+运行时间卡片
    local info_card1 = airui.container({
        parent = content,
        x = 10,
        y = 8,
        w = 460,
        h = 52,
        color = COLOR_CARD,
        radius = 6
    })
    uptime_label = airui.label({
        parent = info_card1,
        x = 10,
        y = 4,
        w = 440,
        h = 44,
        text = "加载中...",
        font_size = 14,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- RAM状态卡片（系统内存 + Lua内存 两行）
    local info_card2 = airui.container({
        parent = content,
        x = 10,
        y = 68,
        w = 460,
        h = 56,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = info_card2,
        x = 10,
        y = 4,
        w = 100,
        h = 18,
        text = "内存信息",
        font_size = 12,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    ram_label = airui.label({
        parent = info_card2,
        x = 10,
        y = 22,
        w = 440,
        h = 32,
        text = "加载中...",
        font_size = 13,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 文件系统卡片（外部Flash文件系统使用情况）
    local info_card3 = airui.container({
        parent = content,
        x = 10,
        y = 132,
        w = 460,
        h = 42,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = info_card3,
        x = 10,
        y = 11,
        w = 100,
        h = 18,
        text = "文件系统",
        font_size = 12,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    flash_label = airui.label({
        parent = info_card3,
        x = 110,
        y = 11,
        w = 340,
        h = 18,
        text = "加载中...",
        font_size = 14,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 底部红色恢复出厂设置按钮
    local factory_reset_btn = airui.container({
        parent = content,
        x = 60,
        y = 190,
        w = 360,
        h = 32,
        color = COLOR_RED,
        radius = 6,
        on_click = on_factory_reset_click
    })
    airui.label({
        parent = factory_reset_btn,
        x = 0,
        y = 4,
        w = 360,
        h = 24,
        text = "恢复出厂设置",
        font_size = 16,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 刷新信息
    refresh_sysinfo()
end

-- 系统信息自动刷新回调：每2秒刷新运行时间+内存
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
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_SYSINFO_WIN", open_handler)
