--[[
@module  idle_win
@summary 首页窗口模块，融合主菜单功能，采用选项卡滑动切换
@version 1.4
@date    2026.04.16
@author  江访
@changelog 2026.04.16 修改状态栏信号显示：同时显示WiFi和4G信号图标，尺寸32x32
]]

local win_id = nil
local main_container = nil
local time_label, big_time_label, date_label, wifi_img, mobile_img
local qrcode1, qrcode2, aircloud_qr = nil, nil, nil
local page_label = nil
local tabview = nil
local current_tab_index = 0

local full_path = ""
local StatusProvider = require "status_provider_app"


--[[
    内置应用定义表 builtin_apps
    每个应用包含三个字段：
    - name: 应用显示名称（字符串）
    - win:  窗口标识（字符串），用于拼接发布的事件名
    - icon: 图标路径（字符串）

    使用说明：
    1. 点击应用时，会发布事件 "OPEN_" .. win .. "_WIN"
       例如：点击"应用市场" -> 发布 "OPEN_APP_STORE_WIN"
    2. 目标窗口需订阅对应事件并打开窗口
       例如：sys.subscribe("OPEN_APP_STORE_WIN", open_handler)

    添加新应用示例：
    { name = "新应用", win = "NEW_APP", icon = "/luadb/new_icon.png" }
]]
local builtin_apps = {
    { name = "WiFi", win = "WIFI", icon = "/luadb/wifi.png" },
    { name = "设置", win = "SETTINGS", icon = "/luadb/settings.png" },
    { name = "应用市场", win = "APP_STORE", icon = "/luadb/app_store_icon.png" },
}

-- 布局参数
local screen_w, screen_h = 480, 800
local is_landscape = false
local top_h = 60
local page_indicator_h = 40
local card_w, card_h = 0, 0
local grid_cols = 1
local apps_per_page = 0
local grid_margin = 8
local grid_top_padding = 16

-- 首页动态布局参数
local big_time_font_size = 100
local big_time_y = 20
local date_y = 130
local qr_size = 130
local qr_y = 190
local builtin_y = 0
local builtin_btn_w = 80
local builtin_btn_spacing = 20

local external_apps_cache = {}
local page_grids = {}

local COLOR_PRIMARY = 0x3F51B5
local COLOR_BG = 0xF8F9FA
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_TEXT_SECONDARY = 0x666666

-------------------------------------------------------------------------------
-- 布局计算（支持横竖屏自适应，图标固定32x32，文字两行）
-------------------------------------------------------------------------------
local function calc_layout()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_h, screen_w = phys_w, phys_h
    end
    is_landscape = (screen_w > screen_h)

    -- 首页动态调整
    if is_landscape then
        big_time_font_size = 80
        big_time_y = 10
        date_y = 90
        qr_size = 100
        qr_y = 140
        builtin_btn_w = 70
        builtin_btn_spacing = 15
    else
        big_time_font_size = 100
        big_time_y = 20
        date_y = 130
        qr_size = 130
        qr_y = 190
        builtin_btn_w = 80
        builtin_btn_spacing = 20
    end
    builtin_y = qr_y + qr_size + 25

    -- 应用网格固定图标尺寸 32x32
    local icon_size = 32

    -- 根据屏幕高度计算字体大小（横屏时缩小）
    local base_font = math.floor(screen_h / 32)
    local title_font_size = math.max(12, math.min(18, base_font))

    -- 网格可用区域
    local grid_area_w = screen_w
    local grid_area_h = screen_h - top_h - page_indicator_h

    -- 最小卡片宽度（根据横竖屏调整）
    local min_card_w = is_landscape and 140 or 120
    grid_cols = math.max(1, math.floor(grid_area_w / min_card_w))
    -- 限制最大列数，避免卡片过窄
    local max_cols = math.floor(grid_area_w / 80)
    if grid_cols > max_cols then grid_cols = max_cols end

    -- 计算卡片宽度
    card_w = math.floor((grid_area_w - (grid_cols + 1) * grid_margin) / grid_cols)

    -- 卡片高度计算：图标(32) + 两行文字高度 + 内边距
    local text_height = title_font_size * 2 + 8 -- 保证两行文字显示
    local padding_vertical = is_landscape and 12 or 16
    card_h = icon_size + text_height + padding_vertical
    -- 确保最小高度
    if card_h < 80 then card_h = 80 end

    -- 计算每页行数（扣除顶部内边距）
    local available_height = grid_area_h - grid_top_padding
    local rows_per_page = math.max(1, math.floor(available_height / (card_h + grid_margin)))
    apps_per_page = grid_cols * rows_per_page

    log.info("idle_win", "layout", screen_w, screen_h, "landscape", is_landscape,
        "cols", grid_cols, "card", card_w, card_h, "per_page", apps_per_page)
end

-------------------------------------------------------------------------------
-- 更新页码指示器
-------------------------------------------------------------------------------
local function update_page_indicator()
    if not tabview or not page_label then return end
    local total = tabview:get_tab_count()
    page_label:set_text(string.format("%d/%d", current_tab_index + 1, total))
end

-------------------------------------------------------------------------------
-- 构建首页内容
-------------------------------------------------------------------------------
local function build_home_page(page_container)
    local content = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h - top_h - page_indicator_h,
        color = COLOR_BG
    })

    big_time_label = airui.label({
        parent = content,
        x = 0,
        y = big_time_y,
        w = screen_w,
        h = big_time_font_size + 10,
        text = "08:00",
        font_size = big_time_font_size,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })

    date_label = airui.label({
        parent = content,
        x = 0,
        y = date_y,
        w = screen_w,
        h = 40,
        text = "1970-01-01 星期四",
        font_size = 20,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local spacing = 20
    local total_width = qr_size * 2 + spacing
    local start_x = (screen_w - total_width) / 2

    qrcode1 = airui.qrcode({
        parent = content,
        x = start_x,
        y = qr_y,
        size = qr_size,
        data = aircloud_qr or "",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })
    airui.label({
        parent = content,
        x = start_x,
        y = qr_y + qr_size + 5,
        w = qr_size,
        h = 30,
        text = "设备云端数据",
        font_size = 16,
        color = 0x3d3d3d,
        align = airui.TEXT_ALIGN_CENTER
    })

    qrcode2 = airui.qrcode({
        parent = content,
        x = start_x + qr_size + spacing,
        y = qr_y,
        size = qr_size,
        data = "https://docs.openluat.com/air8101/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })
    airui.label({
        parent = content,
        x = start_x + qr_size + spacing,
        y = qr_y + qr_size + 5,
        w = qr_size,
        h = 30,
        text = "使用说明",
        font_size = 16,
        color = 0x3d3d3d,
        align = airui.TEXT_ALIGN_CENTER
    })

    local builtin_start_x = (screen_w - (builtin_btn_w * #builtin_apps + builtin_btn_spacing * (#builtin_apps - 1))) / 2

    for i, app in ipairs(builtin_apps) do
        local x = builtin_start_x + (i - 1) * (builtin_btn_w + builtin_btn_spacing)
        local cell = airui.container({
            parent = content,
            x = x,
            y = builtin_y,
            w = builtin_btn_w,
            h = 100,
            color = COLOR_BG,
            on_click = function() sys.publish("OPEN_" .. app.win .. "_WIN") end
        })
        airui.image({
            parent = cell,
            x = (builtin_btn_w - 40) / 2,
            y = 10,
            w = 40,
            h = 40,
            src = app.icon
        })
        airui.label({
            parent = cell,
            x = 0,
            y = 60,
            w = builtin_btn_w,
            h = 30,
            text = app.name,
            font_size = 16,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
end

-------------------------------------------------------------------------------
-- 构建应用网格页（图标固定32x32）
-------------------------------------------------------------------------------
local function build_app_grid_page(page_container, start_idx, apps)
    local grid_container = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h - top_h - page_indicator_h,
        color = COLOR_BG
    })

    local icon_size = 32
    local title_font_size = math.max(12, math.min(18, math.floor(screen_h / 32)))
    local text_height = title_font_size * 2 + 8

    for i = 1, apps_per_page do
        local idx = start_idx + i - 1
        if idx > #apps then break end
        local app = apps[idx]

        local col = (i - 1) % grid_cols
        local row = math.floor((i - 1) / grid_cols)

        local total_row_width = grid_cols * card_w + (grid_cols - 1) * grid_margin
        local start_x = math.floor((screen_w - total_row_width) / 2 + 0.5)
        local x = start_x + col * (card_w + grid_margin)
        local y = row * (card_h + grid_margin) + grid_top_padding

        local card = airui.container({
            parent = grid_container,
            x = x,
            y = y,
            w = card_w,
            h = card_h,
            radius = 12,
            border_width = 1,
            -- color = COLOR_CARD,  -- 容器边框和颜色
            -- border_color = 0xE0E0E0,
            on_click = function()
                if app.is_builtin then
                    sys.publish("OPEN_" .. app.win .. "_WIN")
                else
                    log.info("idle_win", "open app", app.path)
                    exapp.open(app.path)
                end
            end
        })

        local icon_src = app.icon or "/luadb/img.png"
        local icon_x = math.floor((card_w - icon_size) / 2 + 0.5)
        airui.image({
            parent = card,
            x = icon_x,
            y = 8,
            w = icon_size,
            h = icon_size,
            src = icon_src
        })

        airui.label({
            parent = card,
            x = 4,
            y = icon_size + 10,
            w = card_w - 8,
            h = text_height,
            text = app.name or "未知",
            font_size = title_font_size,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    return grid_container
end

-------------------------------------------------------------------------------
-- 刷新应用网格页
-------------------------------------------------------------------------------
local function refresh_app_pages()
    if not tabview then return end

    local apps = external_apps_cache
    local total_apps = #apps
    local total_pages = (total_apps == 0) and 0 or math.ceil(total_apps / apps_per_page)

    local current_tab_count = tabview:get_tab_count()
    local expected_tab_count = 1 + total_pages
    
    -- 删除多余的应用页
    for i = current_tab_count - 1, expected_tab_count, -1 do
        if page_grids[i] then
            page_grids[i]:destroy()
            page_grids[i] = nil
        end
        tabview:remove_tab(i)
    end

    -- 添加/更新应用页
    for page_idx = 1, total_pages do
        local tab_index = page_idx
        local start_idx = (page_idx - 1) * apps_per_page + 1

        if tab_index < current_tab_count then
            local existing_page = tabview:get_content(tab_index)
            if existing_page then
                if page_grids[tab_index] then
                    page_grids[tab_index]:destroy()
                end
                local new_grid = build_app_grid_page(existing_page, start_idx, apps)
                page_grids[tab_index] = new_grid
            end
        else
            local new_page = tabview:add_tab("")
            if new_page then
                local grid = build_app_grid_page(new_page, start_idx, apps)
                page_grids[tab_index] = grid
            end
        end
    end

    if current_tab_index >= expected_tab_count then
        current_tab_index = expected_tab_count - 1
        tabview:set_active(current_tab_index)
    end
    update_page_indicator()
end

-------------------------------------------------------------------------------
-- 加载外部应用列表（按安装时间升序）
-------------------------------------------------------------------------------
local function load_external_apps()
    local list = {}
    local installed, _ = exapp.list_installed()

    for app_dir, info in pairs(installed) do
        local is_builtin_dup = false
        for _, b in ipairs(builtin_apps) do
            if info.cn_name == b.name then
                is_builtin_dup = true
                break
            end
        end
        if not is_builtin_dup then
            table.insert(list, {
                name = info.cn_name or app_dir,
                icon = info.icon_path or "/luadb/img.png",
                is_builtin = false,
                path = info.path,
                install_time = info.install_time,
            })
        end
    end

    -- 按 install_time 升序排序，无时间戳的排在最后
    table.sort(list, function(a, b)
        local ta = a.install_time
        local tb = b.install_time
        if ta == nil and tb == nil then
            return a.name < b.name
        elseif ta == nil then
            return false
        elseif tb == nil then
            return true
        else
            if ta == tb then
                return a.name < b.name
            end
            return ta < tb
        end
    end)

    external_apps_cache = list
    refresh_app_pages()
end

-------------------------------------------------------------------------------
-- 信号图标更新函数
-------------------------------------------------------------------------------
-- local function update_wifi_icon()
--     if not wifi_img then return end
--     local level = StatusProvider.get_wifi_signal_level() or 0
--     -- level: 0-4, 0表示未连接 -> wifixinhao0.png, 1-4对应1-4.png
--     local img_name = string.format("wifixinhao%d.png", level)
--     wifi_img:set_src("/luadb/" .. img_name)
--     log.info("idle_win", "update wifi icon", img_name, "level", level)
-- end



local function update_time_date()
    if not time_label or not big_time_label or not date_label then return end
    local time_str = StatusProvider.get_time()
    local date_str = StatusProvider.get_date()
    local weekday_str = StatusProvider.get_weekday()
    time_label:set_text(time_str)
    big_time_label:set_text(time_str)
    date_label:set_text(date_str .. " " .. weekday_str)
end

-------------------------------------------------------------------------------
-- 事件回调
-------------------------------------------------------------------------------
local function on_status_time_updated()
    update_time_date()
end

-- local function on_status_wifi_signal_updated()
--     update_wifi_icon()
-- end


local function aircloud_qr_update(qr)
    aircloud_qr = qr
    if exwin.is_active(win_id) and qrcode1 then
        qrcode1:set_data(aircloud_qr)
    end
end

-------------------------------------------------------------------------------
-- 窗口生命周期
-------------------------------------------------------------------------------
local function on_create()
    calc_layout()

    main_container = airui.container({
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = COLOR_BG,
        parent = airui.screen
    })

    -- 顶部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = screen_w,
        h = top_h,
        color = COLOR_PRIMARY
    })

    -- 右上角信号图标（WiFi 和 4G 并排，间距8px，尺寸32x32）
    local icon_size = 32
    local icon_spacing = 8
    local start_x = screen_w - (icon_size * 2 + icon_spacing) - 12  -- 右侧留白12px

    -- -- WiFi 图标（左侧）
    -- wifi_img = airui.image({
    --     parent = status_bar,
    --     x = start_x,
    --     y = (top_h - icon_size) / 2,
    --     w = icon_size,
    --     h = icon_size,
    --     src = "/luadb/wifixinhao0.png"  -- 占位
    -- })
    -- -- 4G 图标（右侧）
    -- mobile_img = airui.image({
    --     parent = status_bar,
    --     x = start_x + icon_size + icon_spacing,
    --     y = (top_h - icon_size) / 2,
    --     w = icon_size,
    --     h = icon_size,
    --     src = "/luadb/4Gxinhao6.png"    -- 占位
    -- })

    -- 时间标签居中
    time_label = airui.label({
        parent = status_bar,
        x = (screen_w - 200) / 2,
        y = (top_h - 48) / 2,
        w = 200,
        h = 48,
        text = "08:00",
        font_size = 40,
        color = 0xfefefe,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 选项卡
    tabview = airui.tabview({
        parent = main_container,
        x = 0,
        y = top_h,
        w = screen_w,
        h = screen_h - top_h - page_indicator_h,
        tabs = { "" },
        switch_mode = "swipe",
        page_style = {
            tabbar_size = 0,
            pad = { method = airui.TABVIEW_PAD_ALL, value = 0 },
            bg_opa = 0
        }
    })

    local home_page = tabview:get_content(0)
    build_home_page(home_page)

    -- 底部页码
    local bottom_bar = airui.container({
        parent = main_container,
        x = 0,
        y = screen_h - page_indicator_h,
        w = screen_w,
        h = page_indicator_h,
        color = COLOR_BG
    })
    page_label = airui.label({
        parent = bottom_bar,
        x = 0,
        y = 0,
        w = screen_w,
        h = page_indicator_h,
        text = "1/1",
        font_size = 18,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    tabview:set_on_change(function(self, index)
        current_tab_index = index
        update_page_indicator()
    end)

    load_external_apps()
    update_time_date()
    -- update_wifi_icon()

    sys.timerLoopStart(update_time_date, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    -- sys.subscribe("STATUS_WIFI_SIGNAL_UPDATED", on_status_wifi_signal_updated)
    sys.subscribe("AIRCLOUD_QRINFO", aircloud_qr_update)
    sys.subscribe("APP_STORE_INSTALLED_UPDATED", function()
        load_external_apps()
    end)
end

local function on_destroy()
    sys.timerStop(update_time_date)
    sys.unsubscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    -- sys.unsubscribe("STATUS_WIFI_SIGNAL_UPDATED", on_status_wifi_signal_updated)
    -- sys.unsubscribe("STATUS_MOBILE_SIGNAL_UPDATED", on_status_mobile_signal_updated)
    sys.unsubscribe("AIRCLOUD_QRINFO", aircloud_qr_update)
    sys.unsubscribe("APP_STORE_INSTALLED_UPDATED", load_external_apps)

    if tabview then tabview:destroy() end
    if main_container then main_container:destroy() end
end

local function on_get_focus()
    update_time_date()
    -- update_wifi_icon()
    -- update_mobile_icon()
    if aircloud_qr and qrcode1 then qrcode1:set_data(aircloud_qr) end
    load_external_apps()
end

local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_IDLE_WIN", open_handler)