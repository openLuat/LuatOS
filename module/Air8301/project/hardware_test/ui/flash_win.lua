--[[
@module  flash_win
@summary Flash存储页面，显示芯片容量与文件系统使用情况
@version 2.0.0
@date    2026.08.14
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
            status_label:set_color(T.COLOR_GREEN)
        else
            status_label:set_text("未挂载")
            status_label:set_color(T.COLOR_DANGER)
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
            chip_label:set_color(T.COLOR_TEXT)
        else
            chip_label:set_text("芯片容量: 未知")
            chip_label:set_color(T.COLOR_TEXT_SECONDARY)
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
            fs_label:set_color(T.COLOR_TEXT)
        else
            fs_label:set_text("--")
            fs_label:set_color(T.COLOR_TEXT_SECONDARY)
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
    T.titlebar(main_container, "Flash存储", on_back_click)

    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0,
        y = T.CONTENT_Y,
        w = T.SCREEN_W,
        h = T.CONTENT_H,
        color = T.COLOR_BG
    })

    -- 挂载状态卡片
    local _, _, status_content = T.info_card(content, 10, 60, "挂载状态", "获取中...")
    status_label = status_content

    -- 芯片容量卡片
    local _, _, chip_content = T.info_card(content, 80, 60, "芯片容量", "获取中...")
    chip_label = chip_content

    -- 文件系统卡片
    local _, _, fs_content = T.info_card(content, 150, 60, "文件系统", "获取中...")
    fs_label = fs_content
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
