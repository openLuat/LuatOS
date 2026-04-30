--[[
@module  idle_win
@summary 首页窗口模块，融合主菜单功能，采用选项卡滑动切换
@version 1.4
@date    2026.04.28
]]

local win_id = nil
local main_container = nil
local product_label, big_time_label, date_label, wifi_img, mobile_img, qrcode
local page_label = nil
local tabview = nil
local current_tab_index = 0

local status_cache = {
    time = "08:00",
    date = "1970-01-01",
    weekday = "星期四",
    mobile_level = -1,
    wifi_level = 0
}

local builtin_apps = {
    { name = "设置", win = "SETTINGS", icon = "/luadb/settings.png" },
    { name = "应用市场", win = "APP_STORE", icon = "/luadb/app_store_icon.png" },
    { name = "网络测速", win = "SPEEDTEST", icon = "/luadb/internet_speed.png" },
}

local top_h = 60
local page_indicator_h = 40
local card_w, card_h = 0, 0
local grid_cols = 1
local apps_per_page = 0
local grid_margin = 8
local grid_top_padding = 16

local big_time_font_size = math.floor(100 * _G.density_scale)
local big_time_y = 20
local date_y = 130
local date_font_size = math.floor(20 * _G.density_scale)
local qr_size = math.floor(130 * _G.density_scale)
local qr_y = 190
local builtin_y = 0
local builtin_btn_w = math.floor(80 * _G.density_scale)
local builtin_btn_spacing = math.floor(20 * _G.density_scale)

local time_timer = nil
local external_apps_cache = {}
local page_grids = {}

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_ACCENT         = 0xFF9800
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946

local product_name = "合宙引擎主机"
local ok, model = pcall(hmeta.model)
if ok and model then
    local suffix = tostring(model):gsub("^Air", "")
    product_name = "合宙引擎主机" .. suffix
end

local function calc_layout()
    if is_landscape then
        top_h = math.max(44, math.min(70, math.floor(44 * screen_h / 480)))
        page_indicator_h = math.max(28, math.min(50, math.floor(28 * screen_h / 480)))
    else
        top_h = math.max(44, math.min(70, math.floor(59 * screen_h / 854)))
        page_indicator_h = math.max(28, math.min(50, math.floor(29 * screen_h / 854)))
    end

    local compact_mode = is_landscape and screen_h < 400
    if compact_mode then
        big_time_font_size = 0
        big_time_y = 0
        date_font_size = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h * 0.03 * _G.density_scale)))
        date_y = math.floor(screen_h * 0.01)
        qr_size = math.max(math.floor(45 * _G.density_scale), math.min(math.floor(70 * _G.density_scale), math.floor(screen_h * 0.20 * _G.density_scale)))
        qr_y = date_y + date_font_size + math.floor(4 * _G.density_scale)
        builtin_btn_w = math.max(math.floor(45 * _G.density_scale), math.min(math.floor(65 * _G.density_scale), math.floor(screen_w * 0.055 * _G.density_scale)))
        builtin_btn_spacing = math.max(math.floor(4 * _G.density_scale), math.min(math.floor(10 * _G.density_scale), math.floor(screen_w * 0.01 * _G.density_scale)))
    elseif is_landscape then
        big_time_font_size = math.max(math.floor(40 * _G.density_scale), math.min(math.floor(80 * _G.density_scale), math.floor(screen_h * 0.15 * _G.density_scale)))
        big_time_y = math.floor(screen_h * 0.015)
        date_font_size = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h * 0.03 * _G.density_scale)))
        date_y = big_time_y + big_time_font_size + math.floor(8 * _G.density_scale)
        qr_size = math.max(math.floor(50 * _G.density_scale), math.min(math.floor(110 * _G.density_scale), math.floor(screen_h * 0.20 * _G.density_scale)))
        qr_y = date_y + date_font_size + math.floor(10 * _G.density_scale)
        builtin_btn_w = math.max(math.floor(55 * _G.density_scale), math.min(math.floor(75 * _G.density_scale), math.floor(screen_w * 0.065 * _G.density_scale)))
        builtin_btn_spacing = math.max(math.floor(6 * _G.density_scale), math.min(math.floor(16 * _G.density_scale), math.floor(screen_w * 0.012 * _G.density_scale)))
    else
        big_time_font_size = math.max(math.floor(48 * _G.density_scale), math.min(math.floor(130 * _G.density_scale), math.floor(screen_h * 0.10 * _G.density_scale)))
        big_time_y = math.floor(screen_h * 0.025)
        date_font_size = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(22 * _G.density_scale), math.floor(screen_h * 0.028 * _G.density_scale)))
        date_y = big_time_y + big_time_font_size + math.floor(15 * _G.density_scale)
        qr_size = math.max(math.floor(60 * _G.density_scale), math.min(math.floor(150 * _G.density_scale), math.floor(screen_w * 0.25 * _G.density_scale)))
        qr_y = date_y + date_font_size + math.floor(18 * _G.density_scale)
        builtin_btn_w = math.max(math.floor(60 * _G.density_scale), math.min(math.floor(90 * _G.density_scale), math.floor(screen_w * 0.16 * _G.density_scale)))
        builtin_btn_spacing = math.max(math.floor(8 * _G.density_scale), math.min(math.floor(30 * _G.density_scale), math.floor(screen_w * 0.035 * _G.density_scale)))
    end

    builtin_y = qr_y + qr_size + math.floor(55 * _G.density_scale)

    local icon_size = math.floor(32 * _G.density_scale)
    local base_font = math.floor(screen_h / 32 * _G.density_scale)
    local title_font_size = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), base_font))

    local grid_area_w = screen_w
    local grid_area_h = screen_h - top_h - page_indicator_h

    local min_card_w = is_landscape and 120 or 100
    grid_cols = math.max(1, math.floor(grid_area_w / min_card_w))
    local max_cols = math.floor(grid_area_w / 70)
    if grid_cols > max_cols then grid_cols = max_cols end
    grid_cols = math.min(grid_cols, 8)

    card_w = math.floor((grid_area_w - (grid_cols + 1) * grid_margin) / grid_cols)

    local text_height = title_font_size * 2 + 8
    local padding_vertical = is_landscape and 12 or 16
    card_h = icon_size + text_height + padding_vertical
    if card_h < math.floor(70 * _G.density_scale) then card_h = math.floor(70 * _G.density_scale) end

    local available_height = grid_area_h - grid_top_padding
    local rows_per_page = math.max(1, math.floor(available_height / (card_h + grid_margin)))
    apps_per_page = grid_cols * rows_per_page

    log.info("idle_win", "layout", screen_w, screen_h, "landscape", is_landscape,
        "cols", grid_cols, "card", card_w, card_h, "per_page", apps_per_page)
end

local function update_page_indicator()
    if not tabview or not page_label then return end
    local total = tabview:get_tab_count()
    page_label:set_text(string.format("%d/%d", current_tab_index + 1, total))
end

local function build_home_page(page_container)
    local content = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h - top_h - page_indicator_h,
        color = COLOR_BG
    })

    if big_time_font_size > 0 then
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
    else
        big_time_label = nil
    end

    date_label = airui.label({
        parent = content,
        x = 0,
        y = date_y,
        w = screen_w,
        h = date_font_size + 20,
        text = "1970-01-01 星期四",
        font_size = date_font_size,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local qr_center_x = (screen_w - qr_size) / 2
    qrcode = airui.qrcode({
        parent = content,
        x = qr_center_x,
        y = qr_y,
        size = qr_size,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
            light_color = COLOR_WHITE,
        quiet_zone = true
    })
    airui.label({
        parent = content,
        x = 0,
        y = qr_y + qr_size + math.floor(5 * _G.density_scale),
        w = screen_w,
        h = math.floor(22 * _G.density_scale),
        text = "资料中心",
        font_size = math.floor(14 * _G.density_scale),
        color = COLOR_TEXT,
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
            h = math.floor(100 * _G.density_scale),
            color = COLOR_BG,
            on_click = function() sys.publish("OPEN_" .. app.win .. "_WIN") end
        })
        local builtin_icon_size = math.min(math.floor(40 * _G.density_scale), builtin_btn_w - math.floor(10 * _G.density_scale))
        local builtin_icon_x = (builtin_btn_w - builtin_icon_size) / 2
        airui.image({
            parent = cell,
            x = builtin_icon_x,
            y = math.floor(10 * _G.density_scale),
            w = builtin_icon_size,
            h = builtin_icon_size,
            src = app.icon
        })
        airui.label({
            parent = cell,
            x = 0,
            y = builtin_icon_size + math.floor(18 * _G.density_scale),
            w = builtin_btn_w,
            h = math.floor(30 * _G.density_scale),
            text = app.name,
        font_size = math.floor(14 * _G.density_scale),
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
end

local function build_app_grid_page(page_container, start_idx, apps)
    local grid_container = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h - top_h - page_indicator_h,
        color = COLOR_BG
    })

    local icon_size = math.floor(32 * _G.density_scale)
    local title_font_size = math.max(math.floor(12 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h / 32 * _G.density_scale)))
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
            on_click = function()
                if app.is_builtin then
                    sys.publish("OPEN_" .. app.win .. "_WIN")
                else
                    log.info("idle_win", "open app", app.path)
                    exapp.open(app.path)
                end
            end
        })

        local icon_src = app.icon
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

local function refresh_app_pages()
    if not tabview then return end

    local apps = external_apps_cache
    local total_apps = #apps
    local total_pages = (total_apps == 0) and 0 or math.ceil(total_apps / apps_per_page)

    local current_tab_count = tabview:get_tab_count()
    local expected_tab_count = 1 + total_pages

    for i = current_tab_count - 1, expected_tab_count, -1 do
        if page_grids[i] then
            page_grids[i]:destroy()
            page_grids[i] = nil
        end
        tabview:remove_tab(i)
    end

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

local function update_time_date(time_str, date_str, weekday_str)
    if time_str then status_cache.time = time_str end
    if date_str then status_cache.date = date_str end
    if weekday_str then status_cache.weekday = weekday_str end
    if not date_label then return end
    if big_time_label then
        big_time_label:set_text(status_cache.time)
    end
    date_label:set_text(status_cache.date .. " " .. status_cache.weekday)
end

local function update_wifi_icon(level)
    if level == nil then return end
    status_cache.wifi_level = level
    if not wifi_img then return end
    local img_name = "wifixinhao" .. level .. ".png"
    wifi_img:set_src("/luadb/" .. img_name)
end

local function update_mobile_icon(level)
    if level == nil then return end
    status_cache.mobile_level = level
    if not mobile_img then return end
    local img_index
    if level == -1 then
        img_index = 6
    elseif level == 1 then
        img_index = 5
    else
        img_index = level - 1
    end
    local img_name = "4Gxinhao" .. img_index .. ".png"
    mobile_img:set_src("/luadb/" .. img_name)
end

local function on_status_time_updated(current_time, current_date, current_weekday)
    update_time_date(current_time, current_date, current_weekday)
end

local function on_status_wifi_updated(level)
    update_wifi_icon(level)
end

local function on_status_mobile_updated(level)
    update_mobile_icon(level)
end

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

    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = screen_w,
        h = top_h,
        color = COLOR_PRIMARY
    })
    local status_icon_size = math.floor(32 * _G.density_scale)
    local status_icon_y = math.floor((top_h - status_icon_size) / 2)
    local status_font_size = math.min(math.floor(40 * _G.density_scale), math.floor(top_h * 0.65 * _G.density_scale))
    local product_label_h = status_font_size
    local product_label_y = math.floor((top_h - product_label_h) / 2)
    local icon_start_x = screen_w - status_icon_size - math.floor(12 * _G.density_scale)
    wifi_img = airui.image({
        parent = status_bar,
        x = icon_start_x,
        y = status_icon_y,
        w = status_icon_size,
        h = status_icon_size,
        src = "/luadb/wifixinhao0.png"
    })
    product_label = airui.label({
        parent = status_bar,
        x = 0,
        y = product_label_y,
        w = screen_w - status_icon_size - math.floor(20 * _G.density_scale),
        h = product_label_h,
        text = product_name,
        font_size = math.min(status_font_size, math.floor(20 * _G.density_scale)),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

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
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    tabview:set_on_change(function(self, index)
        current_tab_index = index
        update_page_indicator()
    end)

    load_external_apps()
    update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    update_wifi_icon(status_cache.wifi_level)
    update_mobile_icon(status_cache.mobile_level)

    time_timer = sys.timerLoopStart(function()
        update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    end, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_mobile_updated)
    sys.subscribe("STATUS_WIFI_SIGNAL_UPDATED", on_status_wifi_updated)
    sys.subscribe("APP_STORE_INSTALLED_UPDATED", function()
        load_external_apps()
    end)

    sys.publish("REQUEST_STATUS_REFRESH")
end

local function on_destroy()
    if time_timer then
        sys.timerStop(time_timer)
        time_timer = nil
    end
    sys.unsubscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_status_mobile_updated)
    sys.unsubscribe("STATUS_WIFI_SIGNAL_UPDATED", on_status_wifi_updated)
    sys.unsubscribe("APP_STORE_INSTALLED_UPDATED", load_external_apps)

    if tabview then tabview:destroy() end
    if main_container then main_container:destroy() end
end

local function on_get_focus()
    update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    update_wifi_icon(status_cache.wifi_level)
    update_mobile_icon(status_cache.mobile_level)
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
