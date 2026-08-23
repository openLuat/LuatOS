--[[
@module  flash_win
@summary Flash存储页面，显示芯片容量与文件系统使用情况
@version 1.0.0
@date    2026.08.04
@author  合宙 Air8301
@usage
本页面只读展示外部 SPI Flash 存储信息：
1、芯片容量（lf.getInfo 读取的物理容量）
2、文件系统（挂载后总容量/已用/可用）
3、挂载状态（已挂载/未挂载）
监听 FLASH_MOUNT_STATUS 消息，页面打开时发布 REQUEST_STATUS_REFRESH 主动拉取。
]]

local win_id = nil
local main_container, content
local chip_label, fs_label, status_label

-- 颜色常量
local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF
local COLOR_GREEN = 0x4CAF50
local COLOR_RED = 0xF44336

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
Flash 挂载状态回调: 更新显示

@local
@function on_flash_mount_status
@param mounted boolean 是否挂载成功
@param total_kb number 文件系统总容量KB
@param used_kb number 文件系统已用KB
@param capacity_kb number Flash芯片总容量KB
]]
local function on_flash_mount_status(mounted, total_kb, used_kb, capacity_kb)
    if not exwin.is_active(win_id) then return end

    -- 挂载状态
    if status_label then
        if mounted then
            status_label:set_text("已挂载")
            status_label:set_color(COLOR_GREEN)
        else
            status_label:set_text("未挂载")
            status_label:set_color(COLOR_RED)
        end
    end

    -- 芯片容量行
    if chip_label then
        if capacity_kb and capacity_kb > 0 then
            local cap_mb = capacity_kb / 1024
            if cap_mb >= 1024 then
                chip_label:set_text(string.format("芯片容量: %.2f GB", cap_mb / 1024))
            else
                chip_label:set_text(string.format("芯片容量: %.0f MB", cap_mb))
            end
            chip_label:set_color(COLOR_TEXT)
        else
            chip_label:set_text("芯片容量: 未知")
            chip_label:set_color(COLOR_SECONDARY)
        end
    end

    -- 文件系统行
    if fs_label then
        if mounted and total_kb and total_kb > 0 then
            local total_mb = total_kb / 1024
            local used_mb = used_kb / 1024
            local free_mb = total_mb - used_mb
            fs_label:set_text(string.format("总 %.1f MB  已用 %.1f MB  可用 %.1f MB",
                total_mb, used_mb, free_mb))
            fs_label:set_color(COLOR_TEXT)
        else
            fs_label:set_text("--")
            fs_label:set_color(COLOR_SECONDARY)
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
        text = "Flash存储",
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

    -- 挂载状态卡片
    local status_card = airui.container({
        parent = content,
        x = 10,
        y = 10,
        w = 460,
        h = 60,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = status_card,
        x = 10,
        y = 4,
        w = 100,
        h = 20,
        text = "挂载状态",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    status_label = airui.label({
        parent = status_card,
        x = 10,
        y = 28,
        w = 200,
        h = 24,
        text = "获取中...",
        font_size = 18,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 芯片容量卡片
    local chip_card = airui.container({
        parent = content,
        x = 10,
        y = 80,
        w = 460,
        h = 60,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = chip_card,
        x = 10,
        y = 4,
        w = 100,
        h = 20,
        text = "芯片容量",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    chip_label = airui.label({
        parent = chip_card,
        x = 10,
        y = 28,
        w = 300,
        h = 24,
        text = "获取中...",
        font_size = 18,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 文件系统卡片
    local fs_card = airui.container({
        parent = content,
        x = 10,
        y = 150,
        w = 460,
        h = 60,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = fs_card,
        x = 10,
        y = 4,
        w = 100,
        h = 20,
        text = "文件系统",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    fs_label = airui.label({
        parent = fs_card,
        x = 10,
        y = 28,
        w = 440,
        h = 24,
        text = "获取中...",
        font_size = 16,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
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
    content = nil
    status_label = nil
    chip_label = nil
    fs_label = nil
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
OPEN_FLASH_WIN 消息处理器

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

sys.subscribe("OPEN_FLASH_WIN", open_handler)
