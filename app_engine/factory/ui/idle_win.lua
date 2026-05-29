--[[
@module  idle_win
@summary 首页窗口模块，融合主菜单功能，采用选项卡滑动切换
@version 1.4
@date    2026.04.28
@author  江访
]]

-- All variable and function names now use full readable names.
-- Layout variables defined in calc_layout().
-- Key containers: main_container, tab_view.
-- Key data: builtin_apps, external_app_cache, status_cache.

local window_id = nil
local main_container = nil
local product_label, big_time_label, date_label, wifi_icon, mobile_icon, qrcode_widget
local battery_container, battery_bar, battery_label
local page_label = nil
local tab_view = nil
local current_tab_index = 0

local status_cache = { time = "08:00", date = "1970-01-01", weekday = "星期四", mobile_level = -1, wifi_level = 0 }

local builtin_apps = {
    { name = "设置", win = "SETTINGS", icon = "/luadb/settings.png" },
    { name = "应用市场", win = "APP_STORE", icon = "/luadb/app_store_icon.png" },
    { name = "网络测速", win = "SPEEDTEST", icon = "/luadb/internet_speed.png" },
}

local top_height = 60
local page_indicator_height = 40
local card_width, card_height = 0, 0
local grid_columns = 1
local apps_per_page = 0
local grid_margin = 8
local grid_top_padding = 16

local density_scale_val = _G.density_scale or 1.0
local big_time_font_size = math.floor(100 * density_scale_val)
local big_time_label_y = 20
local date_label_y = 130
local date_font_size = math.floor(20 * density_scale_val)
local qrcode_size = math.floor(130 * density_scale_val)
local qrcode_y = 190
local buttons_y = 0
local builtin_button_width = math.floor(80 * density_scale_val)
local builtin_button_spacing = math.floor(20 * density_scale_val)

local timer_handler = nil
local external_app_cache = {}
local page_grids = {}
local app_rebuild_pending = false
local app_cache_dirty = false

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
local COLOR_GREEN          = 0x34C759

local product_name = "合宙引擎主机"
local has_4g = _G.project_config and _G.project_config.features and _G.project_config.features.net_4g
local has_wifi = _G.project_config and _G.project_config.features and _G.project_config.features.wifi
local has_battery = _G.project_config and _G.project_config.features and _G.project_config.features.battery
    and _G.project_config and _G.project_config.ui and _G.project_config.ui.show_battery_icon
local chip_name = (_G.project_config and _G.project_config.chip) or ""
local model_suffix = chip_name:gsub("^Air", "")
if model_suffix ~= "" then
    product_name = "合宙引擎主机" .. model_suffix
end

local function calc_layout()
    if is_landscape then
        top_height = math.max(44, math.min(70, math.floor(44 * screen_h / 480)))
        page_indicator_height = math.max(28, math.min(50, math.floor(28 * screen_h / 480)))
    else
        top_height = math.max(44, math.min(70, math.floor(59 * screen_h / 854)))
        page_indicator_height = math.max(28, math.min(50, math.floor(29 * screen_h / 854)))
    end

    local cm = is_landscape and screen_h < 400
    if cm then
        big_time_font_size = 0
        big_time_label_y = 0
        date_font_size = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h * 0.03 * _G.density_scale)))
        date_label_y = math.floor(screen_h * 0.01)
        qrcode_size = math.max(math.floor(45 * _G.density_scale), math.min(math.floor(70 * _G.density_scale), math.floor(screen_h * 0.20 * _G.density_scale)))
        qrcode_y = date_label_y + date_font_size + math.floor(4 * _G.density_scale)
        builtin_button_width = math.max(math.floor(45 * _G.density_scale), math.min(math.floor(65 * _G.density_scale), math.floor(screen_w * 0.055 * _G.density_scale)))
        builtin_button_spacing = math.max(math.floor(4 * _G.density_scale), math.min(math.floor(10 * _G.density_scale), math.floor(screen_w * 0.01 * _G.density_scale)))
    elseif is_landscape then
        big_time_font_size = math.max(math.floor(40 * _G.density_scale), math.min(math.floor(80 * _G.density_scale), math.floor(screen_h * 0.15 * _G.density_scale)))
        big_time_label_y = math.floor(screen_h * 0.015)
        date_font_size = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h * 0.03 * _G.density_scale)))
        date_label_y = big_time_label_y + big_time_font_size + math.floor(8 * _G.density_scale)
        qrcode_size = math.max(math.floor(50 * _G.density_scale), math.min(math.floor(110 * _G.density_scale), math.floor(screen_h * 0.20 * _G.density_scale)))
        qrcode_y = date_label_y + date_font_size + math.floor(10 * _G.density_scale)
        builtin_button_width = math.max(math.floor(55 * _G.density_scale), math.min(math.floor(75 * _G.density_scale), math.floor(screen_w * 0.065 * _G.density_scale)))
        builtin_button_spacing = math.max(math.floor(6 * _G.density_scale), math.min(math.floor(16 * _G.density_scale), math.floor(screen_w * 0.012 * _G.density_scale)))
    else
        big_time_font_size = math.max(math.floor(48 * _G.density_scale), math.min(math.floor(130 * _G.density_scale), math.floor(screen_h * 0.10 * _G.density_scale)))
        big_time_label_y = math.floor(screen_h * 0.025)
        date_font_size = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(22 * _G.density_scale), math.floor(screen_h * 0.028 * _G.density_scale)))
        date_label_y = big_time_label_y + big_time_font_size + math.floor(15 * _G.density_scale)
        qrcode_size = math.max(math.floor(60 * _G.density_scale), math.min(math.floor(150 * _G.density_scale), math.floor(screen_w * 0.25 * _G.density_scale)))
        qrcode_y = date_label_y + date_font_size + math.floor(18 * _G.density_scale)
        builtin_button_width = math.max(math.floor(60 * _G.density_scale), math.min(math.floor(90 * _G.density_scale), math.floor(screen_w * 0.16 * _G.density_scale)))
        builtin_button_spacing = math.max(math.floor(8 * _G.density_scale), math.min(math.floor(30 * _G.density_scale), math.floor(screen_w * 0.035 * _G.density_scale)))
    end

    buttons_y = qrcode_y + qrcode_size + math.floor(55 * _G.density_scale)

    local grid_icon_size = math.floor(32 * _G.density_scale)
    local bf = math.floor(screen_h / 32 * _G.density_scale)
    local grid_text_font_size = math.max(math.floor(14 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), bf))

    local gaw = screen_w
    local gah = screen_h - top_height - page_indicator_height

    local mcw = is_landscape and 120 or 100
    -- 宽屏增大最小卡片宽度，减少列数避免卡片过密
    if screen_w > 480 then
        mcw = math.max(mcw, math.floor(screen_w / 5))
    end
    grid_columns = math.max(1, math.floor(gaw / mcw))
    local mxc = math.floor(gaw / 70)
    if grid_columns > mxc then grid_columns = mxc end
    grid_columns = math.min(grid_columns, 8)

    card_width = math.floor((gaw - (grid_columns + 1) * grid_margin) / grid_columns)

    local txh = grid_text_font_size * 2 + 8
    local pv = is_landscape and 12 or 16
    card_height = grid_icon_size + txh + pv
    if card_height < math.floor(70 * _G.density_scale) then card_height = math.floor(70 * _G.density_scale) end

    local ah = gah - grid_top_padding
    local rpp = math.max(1, math.floor(ah / (card_height + grid_margin)))
    apps_per_page = grid_columns * rpp

    -- 限制每页卡片数量，避免大屏上控件过密导致滑动卡顿
    if not is_landscape and apps_per_page > 24 then
        local total_cards = 0
        local ok, installed_apps = pcall(exapp.list_installed)
        if ok then
            for _ in pairs(installed_apps) do total_cards = total_cards + 1 end
        end
        total_cards = total_cards - #builtin_apps
        if total_cards > 24 + grid_columns then
            apps_per_page = 24
            local target_rows = math.ceil(apps_per_page / grid_columns)
            card_height = math.floor((ah - grid_margin * (target_rows - 1)) / target_rows)
            if card_height < math.floor(70 * _G.density_scale) then
                card_height = math.floor(70 * _G.density_scale)
            end
        end
    end

end

local function update_page_indicator()
    if not tab_view or not page_label then return end
    local total = tab_view:get_tab_count()
    page_label:set_text(string.format("%d/%d", current_tab_index + 1, total))
end

local function build_home_page(page_container)
    local home_container = airui.container({
        parent = page_container,
        x = 0, y = 0, w = screen_w, h = screen_h - top_height - page_indicator_height,
        color = COLOR_BG
    })

    if big_time_font_size > 0 then
        big_time_label = airui.label({
            parent = home_container,
            x = 0, y = big_time_label_y, w = screen_w, h = big_time_font_size + 10,
            text = "08:00", font_size = big_time_font_size, color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })
    else
        big_time_label = nil
    end

    date_label = airui.label({
        parent = home_container,
        x = 0, y = date_label_y, w = screen_w, h = date_font_size + 20,
        text = "1970-01-01 星期四", font_size = date_font_size,
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER
    })

    local qcx = (screen_w - qrcode_size) / 2
    qrcode_widget = airui.qrcode({
        parent = home_container, x = qcx, y = qrcode_y, size = qrcode_size,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000, light_color = COLOR_WHITE, quiet_zone = true
    })
    airui.label({
        parent = home_container,
        x = 0, y = qrcode_y + qrcode_size + math.floor(5 * _G.density_scale),
        w = screen_w, h = math.floor(22 * _G.density_scale),
        text = "资料中心", font_size = math.floor(14 * _G.density_scale),
        color = COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER
    })

    local bsx = (screen_w - (builtin_button_width * #builtin_apps + builtin_button_spacing * (#builtin_apps - 1))) / 2

    for i, app in ipairs(builtin_apps) do
        local x = bsx + (i - 1) * (builtin_button_width + builtin_button_spacing)
        local c = airui.container({
            parent = home_container, x = x, y = buttons_y, w = builtin_button_width,
            h = math.floor(100 * _G.density_scale), color = COLOR_BG,
            on_click = function() sys.publish("OPEN_" .. app.win .. "_WIN") end
        })
        local bis = math.min(math.floor(40 * _G.density_scale), builtin_button_width - math.floor(10 * _G.density_scale))
        local bix = (builtin_button_width - bis) / 2
        airui.image({
            parent = c, x = bix, y = math.floor(10 * _G.density_scale),
            w = bis, h = bis, src = app.icon
        })
        airui.label({
            parent = c, x = 0,
            y = bis + math.floor(18 * _G.density_scale),
            w = builtin_button_width, h = math.floor(30 * _G.density_scale),
            text = app.name, font_size = math.floor(14 * _G.density_scale),
            color = COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER
        })
    end
end

local function build_app_grid_page(page_container, start_idx, apps)
    local grid_container = airui.container({
        parent = page_container,
        x = 0, y = 0, w = screen_w, h = screen_h - top_height - page_indicator_height,
        color = COLOR_BG
    })

    local grid_icon_size = math.floor(32 * _G.density_scale)
    local grid_text_font_size = math.max(math.floor(12 * _G.density_scale), math.min(math.floor(18 * _G.density_scale), math.floor(screen_h / 32 * _G.density_scale)))
    local txh = grid_text_font_size * 2 + 8

    for i = 1, apps_per_page do
        local idx = start_idx + i - 1
        if idx > #apps then break end
        local app = apps[idx]

        local col = (i - 1) % grid_columns
        local row = math.floor((i - 1) / grid_columns)

        local trw = grid_columns * card_width + (grid_columns - 1) * grid_margin
        local sx = math.floor((screen_w - trw) / 2 + 0.5)
        local x = sx + col * (card_width + grid_margin)
        local y = row * (card_height + grid_margin) + grid_top_padding

        local card_widget = airui.container({
            parent = grid_container, x = x, y = y, w = card_width, h = card_height,
            radius = 12, border_width = 1,
            on_click = function()
                if app.is_builtin then
                    sys.publish("OPEN_" .. app.win .. "_WIN")
                else
                    log.info("idle_window", "open app", app.path)
                    exapp.open(app.path)
                end
            end
        })

        local icon_src = app.icon
        local ix = math.floor((card_width - grid_icon_size) / 2 + 0.5)
        airui.image({
            parent = card_widget, x = ix, y = 8, w = grid_icon_size, h = grid_icon_size, src = icon_src
        })

        airui.label({
            parent = card_widget, x = 4, y = grid_icon_size + 10,
            w = card_width - 8, h = txh,
            text = app.name or "未知", font_size = grid_text_font_size,
            color = COLOR_TEXT, align = airui.TEXT_ALIGN_CENTER
        })
    end

    return grid_container
end

local function rebuild_app_pages()
    if not tab_view then return end

    local apps = external_app_cache
    local total_apps = #apps
    local total_page_count = (total_apps == 0) and 0 or math.ceil(total_apps / apps_per_page)

    local current_tab_count = tab_view:get_tab_count()
    local expected_tab_count = 1 + total_page_count

    for i = current_tab_count - 1, expected_tab_count, -1 do
        if page_grids[i] then
            page_grids[i]:destroy()
            page_grids[i] = nil
        end
        tab_view:remove_tab(i)
    end

    for pi = 1, total_page_count do
        local ti = pi
        local page_start_idx = (pi - 1) * apps_per_page + 1

        if ti < current_tab_count then
            local ep = tab_view:get_content(ti)
            if ep then
                if page_grids[ti] then
                    page_grids[ti]:destroy()
                end
                local ng = build_app_grid_page(ep, page_start_idx, apps)
                page_grids[ti] = ng
            end
        else
            local np = tab_view:add_tab("")
            if np then
                local g = build_app_grid_page(np, page_start_idx, apps)
                page_grids[ti] = g
            end
        end
    end

    if current_tab_index >= expected_tab_count then
        current_tab_index = expected_tab_count - 1
        tab_view:set_active(current_tab_index)
    end
    update_page_indicator()
end

local function load_external_apps()
    local external_app_list = {}
    local installed_apps, _ = exapp.list_installed()

    for app_dir, info in pairs(installed_apps) do
        local is_builtin_flag = false
        for _, b in ipairs(builtin_apps) do
            if info.cn_name == b.name then
                is_builtin_flag = true
                break
            end
        end
        if not is_builtin_flag then
            table.insert(external_app_list, {
                name = info.cn_name or app_dir,
                icon = info.icon_path or "/luadb/img.png",
                is_builtin = false,
                path = info.path,
                install_time = info.install_time,
            })
        end
    end

    table.sort(external_app_list, function(a, b)
        local time_a = a.install_time
        local time_b = b.install_time
        if time_a == nil and time_b == nil then
            return a.name < b.name
        elseif time_a == nil then
            return false
        elseif time_b == nil then
            return true
        else
            if time_a == time_b then
                return a.name < b.name
            end
            return time_a < time_b
        end
    end)

    external_app_cache = external_app_list
    rebuild_app_pages()
end

local function on_installed_updated()
    app_cache_dirty = true
    if not app_rebuild_pending then
        app_rebuild_pending = true
        sys.timerStart(function()
            app_rebuild_pending = false
            if app_cache_dirty then
                app_cache_dirty = false
                load_external_apps()
            end
        end, 500)
    end
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
    if not wifi_icon then return end
    local imn = "wifixinhao" .. level .. ".png"
    wifi_icon:set_src("/luadb/" .. imn)
end

local function update_mobile_icon(level)
    if level == nil then return end
    status_cache.mobile_level = level
    if not mobile_icon then return end
    local ii
    if level == -1 then
        ii = 6
    elseif level == 1 then
        ii = 5
    else
        ii = level - 1
    end
    local imn = "4Gxinhao" .. ii .. ".png"
    mobile_icon:set_src("/luadb/" .. imn)
end

local function on_status_time(current_time, current_date, current_weekday)
    update_time_date(current_time, current_date, current_weekday)
end

local function on_status_wifi(level)
    update_wifi_icon(level)
end

local function on_status_mobile(level)
    update_mobile_icon(level)
end

-- 电池充电动画
local charge_anim_timer = nil
local charge_anim_value = 0
local charge_start_level = 0
local charge_anim_active = false  -- 标记动画是否正在运行

local function stop_charge_anim()
    if charge_anim_timer then
        sys.timerStop(charge_anim_timer)
        charge_anim_timer = nil
    end
    charge_anim_active = false
end

local function start_charge_anim(from_level)
    stop_charge_anim()
    charge_start_level = from_level
    charge_anim_value = from_level
    charge_anim_active = true
    charge_anim_timer = sys.timerLoopStart(function()
        if not battery_bar then
            stop_charge_anim()
            return
        end
        charge_anim_value = charge_anim_value + 4
        if charge_anim_value >= 100 then
            charge_anim_value = charge_start_level
        end
        battery_bar:set_value(charge_anim_value)
    end, 100)
end

local function on_status_battery(data)
    if not data or not battery_bar or not battery_label then
        return
    end

    local level = data.level or 0
    local charging = data.charging
    local present = data.present

    if not present then
        stop_charge_anim()
        battery_bar:set_value(0)
        battery_bar:set_indicator_color(0xBBBBBB)
        battery_label:set_text("--")
        return
    end

    battery_label:set_text(level .. "%")

    if charging then
        battery_bar:set_indicator_color(COLOR_GREEN)
        if not charge_anim_active then
            -- 刚进入充电状态：启动动画，从当前电量循环到 100%
            start_charge_anim(level)
        else
            -- 动画已运行中：只更新循环起点的电量值，下一个周期自动用新起点，不打断当前动画
            charge_start_level = level
        end
    else
        stop_charge_anim()
        battery_bar:set_value(level)
        if level < 20 then
            battery_bar:set_indicator_color(COLOR_DANGER)
        elseif level < 50 then
            battery_bar:set_indicator_color(COLOR_ACCENT)
        else
            battery_bar:set_indicator_color(COLOR_GREEN)
        end
    end
end

local function on_create()
    calc_layout()

    main_container = airui.container({
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG, parent = airui.screen
    })

    local sb = airui.container({
        parent = main_container, x = 0, y = 0, w = screen_w, h = top_height,
        color = COLOR_PRIMARY
    })
    local status_icon_size = math.floor(32 * _G.density_scale)
    local siy = math.floor((top_height - status_icon_size) / 2)
    local sfs = math.min(math.floor(40 * _G.density_scale), math.floor(top_height * 0.65 * _G.density_scale))
    local plh = math.min(sfs, math.floor(24 * _G.density_scale))
    local ply = math.floor((top_height - plh) / 2)

    -- 计算可见图标数量（均按配置驱动）
    local icon_wifi = has_wifi
    local icon_4g   = has_4g
    local icon_batt = has_battery
    local icon_spacing = math.floor(8 * _G.density_scale)
    local right_margin = math.floor(12 * _G.density_scale)

    -- 电池组件尺寸
    local batt_w = icon_batt and math.floor(58 * _G.density_scale) or 0
    local batt_h = icon_batt and math.floor(22 * _G.density_scale) or 0
    local batt_y = icon_batt and math.floor((top_height - batt_h) / 2) or 0

    -- 计算右侧区域总宽度
    local total_right_w = 0
    if icon_batt then
        total_right_w = batt_w
    end
    if icon_4g then
        if total_right_w > 0 then
            total_right_w = total_right_w + icon_spacing
        end
        total_right_w = total_right_w + status_icon_size
    end
    if icon_wifi then
        if total_right_w > 0 then
            total_right_w = total_right_w + icon_spacing
        end
        total_right_w = total_right_w + status_icon_size
    end

    local right_base_x = total_right_w > 0 and (screen_w - total_right_w - right_margin) or 0

    -- WiFi 图标（最左侧）
    local next_x = right_base_x
    if icon_wifi then
        wifi_icon = airui.image({
            parent = sb, x = next_x, y = siy,
            w = status_icon_size, h = status_icon_size, src = "/luadb/wifixinhao0.png"
        })
        next_x = next_x + status_icon_size + icon_spacing
    end
    -- 4G 图标
    if icon_4g then
        mobile_icon = airui.image({
            parent = sb, x = next_x, y = siy,
            w = status_icon_size, h = status_icon_size, src = "/luadb/4Gxinhao6.png"
        })
        next_x = next_x + status_icon_size + icon_spacing
    end
    -- 电池进度条组件（最右侧）
    if icon_batt then
        battery_container = airui.container({
            parent = sb, x = next_x, y = batt_y, w = batt_w, h = batt_h,
            color = 0x00000000, radius = 5,
        })
        battery_bar = airui.bar({
            parent = battery_container, x = 0, y = 0, w = batt_w, h = batt_h,
            min = 0, max = 100, value = 0,
            indicator_color = COLOR_GREEN, bg_color = COLOR_DIVIDER, radius = 5,
        })
        battery_label = airui.label({
            parent = battery_container, x = 0, y = math.floor(2 * _G.density_scale), w = batt_w, h = batt_h - math.floor(2 * _G.density_scale),
            text = "--", font_size = math.floor(12 * _G.density_scale),
            color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER,
        })
    end
    -- 产品名标签（宽度自适应图标区）
    local label_w = screen_w - math.floor(20 * _G.density_scale)
    if total_right_w > 0 then
        label_w = screen_w - total_right_w - right_margin - math.floor(20 * _G.density_scale)
    end
    product_label = airui.label({
        parent = sb,
        x = 0, y = ply,
        w = label_w,
        h = plh, text = product_name, font_size = plh, color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    tab_view = airui.tabview({
        parent = main_container,
        x = 0, y = top_height, w = screen_w, h = screen_h - top_height - page_indicator_height,
        tabs = { "" }, switch_mode = "swipe",
        page_style = {
            tabbar_size = 0,
            pad = { method = airui.TABVIEW_PAD_ALL, value = 0 },
            bg_opa = 0
        }
    })

    local hp = tab_view:get_content(0)
    build_home_page(hp)

    local bb = airui.container({
        parent = main_container,
        x = 0, y = screen_h - page_indicator_height, w = screen_w, h = page_indicator_height,
        color = COLOR_BG
    })
    page_label = airui.label({
        parent = bb, x = 0, y = 0, w = screen_w, h = page_indicator_height,
        text = "1/1", font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER
    })

    tab_view:set_on_change(function(self, index)
        current_tab_index = index
        update_page_indicator()
    end)

    load_external_apps()
    update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    update_wifi_icon(status_cache.wifi_level)
    update_mobile_icon(status_cache.mobile_level)

    timer_handler = sys.timerLoopStart(function()
        update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    end, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time)
    if has_4g then
        sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_mobile)
    end
    if has_wifi then
        sys.subscribe("STATUS_WIFI_SIGNAL_UPDATED", on_status_wifi)
    end
    sys.subscribe("APP_STORE_INSTALLED_UPDATED", on_installed_updated)
    if has_battery then
        sys.subscribe("BATTERY_STATUS", on_status_battery)
    end

    sys.publish("REQUEST_STATUS_REFRESH")
end

local function on_destroy()
    if timer_handler then
        sys.timerStop(timer_handler)
        timer_handler = nil
    end
    sys.unsubscribe("STATUS_TIME_UPDATED", on_status_time)
    if has_4g then
        sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_status_mobile)
    end
    if has_wifi then
        sys.unsubscribe("STATUS_WIFI_SIGNAL_UPDATED", on_status_wifi)
    end
    sys.unsubscribe("APP_STORE_INSTALLED_UPDATED", on_installed_updated)
    if has_battery then
        sys.unsubscribe("BATTERY_STATUS", on_status_battery)
        stop_charge_anim()
    end

    if tab_view then tab_view:destroy(); tab_view = nil end
    if main_container then main_container:destroy(); main_container = nil end
    product_label = nil; big_time_label = nil; date_label = nil; wifi_icon = nil; mobile_icon = nil; qrcode_widget = nil
    battery_container = nil; battery_bar = nil; battery_label = nil
    page_label = nil; external_app_cache = {}; page_grids = {}
    current_tab_index = 0
end

local function on_get_focus()
    update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
    update_wifi_icon(status_cache.wifi_level)
    update_mobile_icon(status_cache.mobile_level)
    load_external_apps()
    if not timer_handler then
        timer_handler = sys.timerLoopStart(function()
            update_time_date(status_cache.time, status_cache.date, status_cache.weekday)
        end, 1000)
    end
end

local function on_lose_focus()
    if timer_handler then
        sys.timerStop(timer_handler)
        timer_handler = nil
    end
    stop_charge_anim()
end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_IDLE_WIN", open_handler)
