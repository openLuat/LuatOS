--[[
@module  prod_flash_win
@summary Flash存储页面（产测模式），显示芯片容量与文件系统使用情况
@version 1.0
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_FLASH_WIN，避免与业务页面冲突

@usage
本页面只读展示外部 SPI Flash 存储信息：
1、挂载状态（已挂载/未挂载）
2、芯片容量（lf.getInfo 读取的物理容量）
3、文件系统（挂载后总容量/已用/可用）
监听 FLASH_MOUNT_STATUS 消息，页面打开时发布 REQUEST_STATUS_REFRESH 主动拉取。

视觉：ui_theme 深色玻璃态（3 条键值行，语义色表达挂载状态）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local status_label, chip_label, fs_label

-- 布局常量（内容区 464×210：3×48 + 2×8 = 160，上下居中）
local ROW_H   = 48
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
            status_label:set_color(theme.SEM.success)
        else
            -- 产测模式不常驻挂载：Flash 由 prod_test 的 FLASH_TEST 指令自包含地
            -- 「按需挂载 → 写读 → 卸载」，flash_app 不参与，故此处是「按需状态」
            -- 而非故障，用琥珀提示色，避免测试员误判为异常
            if IS_FACTORY_MODE then
                status_label:set_text("按需挂载（产测）")
                status_label:set_color(theme.SEM.warning)
            else
                status_label:set_text("未挂载")
                status_label:set_color(theme.SEM.danger)
            end
        end
    end

    -- 芯片容量行
    if chip_label then
        if capacity_kb and capacity_kb > 0 then
            local cap_mb = capacity_kb / 1024
            if cap_mb >= 1024 then
                chip_label:set_text(string.format("%.2f GB", cap_mb / 1024))
            else
                chip_label:set_text(string.format("%.0f MB", cap_mb))
            end
            chip_label:set_color(theme.C.t1)
        else
            -- 产测模式未挂载时读不到 lf.getInfo，用「按需读取」而非「未知」（后者易被误判为故障）
            chip_label:set_text(IS_FACTORY_MODE and "按需读取" or "未知")
            chip_label:set_color(theme.C.t2)
        end
    end

    -- 文件系统行
    if fs_label then
        if mounted and total_kb and total_kb > 0 then
            local total_mb = total_kb / 1024
            local used_mb = used_kb / 1024
            local free_mb = total_mb - used_mb
            fs_label:set_text(string.format("可用 %.1f MB %s 共 %.1f MB",
                free_mb, theme.CHAR.sep, total_mb))
            fs_label:set_color(theme.C.t1)
        else
            fs_label:set_text("--")
            fs_label:set_color(theme.C.t2)
        end
    end
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "Flash存储", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- 上下居中：总高 160，内容区 210，顶部留白 25
    local y = ctx.y + math.floor((ctx.h - (ROW_H * 3 + ROW_GAP * 2)) / 2)

    local _, l_status = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 100,
        label = "挂载状态", value = "获取中...", value_color = theme.C.t2 })
    status_label = l_status
    y = y + ROW_H + ROW_GAP

    local _, l_chip = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 100,
        label = "芯片容量", value = "获取中...", value_color = theme.C.t2 })
    chip_label = l_chip
    y = y + ROW_H + ROW_GAP

    local _, l_fs = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 100,
        label = "文件系统", value = "获取中...", value_color = theme.C.t2 })
    fs_label = l_fs
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
