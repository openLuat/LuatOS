--[[
@module  prod_sysinfo_win
@summary 系统信息页面（产测模式），显示固件版本、运行时间、RAM、文件系统信息
@version 2.0.0
@date    2026.09.24
@version_note 产测专属：消息名前缀改 OPEN_PROD_SYSINFO_WIN；去掉恢复出厂按钮（产测用 U 盘/指令 RST#）
@usage
本页面只读展示系统信息：
1、固件版本（VERSION）
2、运行时间（mcu.ticks 转换时分秒）
3、RAM使用（rtos.meminfo 多值返回，字节转MB，系统内存+Lua内存）
4、文件系统信息（订阅 FLASH_MOUNT_STATUS）
页面打开期间每 2 秒自动刷新运行时间与内存。
]]

local win_id = nil
local main_container, content
local uptime_label, ram_label, flash_label

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

    -- RAM信息: rtos.meminfo 返回两个值(总, 已用), 单位字节
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
            flash_label:set_text(string.format("总容量: %.1f MB\n可用容量: %.1f MB", total_mb, free_mb))
            flash_label:set_color(T.COLOR_GREEN)
        else
            flash_label:set_text("未挂载")
            flash_label:set_color(T.COLOR_DANGER)
        end
    end
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    -- 顶部标题栏
    T.titlebar(main_container, "系统信息", on_back_click)

    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0,
        y = T.CONTENT_Y,
        w = T.SCREEN_W,
        h = T.CONTENT_H,
        color = T.COLOR_BG
    })

    -- 固件版本+运行时间卡片
    local _, _, uptime_content = T.info_card(content, 6, 48, "固件 / 运行时间", "加载中...")
    uptime_label = uptime_content

    -- RAM状态卡片（系统内存 + Lua内存 两行）
    local ram_card = airui.container({
        parent = content,
        x = T.MARGIN,
        y = 62,
        w = T.CARD_W,
        h = 56,
        color = T.COLOR_CARD,
        radius = T.CARD_RADIUS
    })
    airui.label({
        parent = ram_card,
        x = 10,
        y = 4,
        w = T.CARD_W - 20,
        h = 20,
        text = "内存信息",
        font_size = T.FONT_CARD_TITLE,
        color = T.COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    ram_label = airui.label({
        parent = ram_card,
        x = 10,
        y = 22,
        w = T.CARD_W - 20,
        h = 32,
        text = "加载中...",
        font_size = T.FONT_SMALL,
        color = T.COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 文件系统卡片
    local _, _, flash_content = T.info_card(content, 122, 60, "文件系统", "加载中...")
    flash_label = flash_content

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
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_PROD_SYSINFO_WIN", open_handler)
