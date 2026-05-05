--[[
@module  suntime_win
@summary 日出日落时间查询
@version 1.0
@date    2026.04.22
@usage
本模块实现日出日落时间查询功能，包括：
1. 下拉选择城市与切换
2. 实时时间显示
3. 日出日落时间计算与显示
]]

local win_id = nil
local main_container, content

-- UI 组件
local city_label, date_label, time_label
local sunrise_label, sunset_label
local daylight_label, dusk_label, noon_label
local city_dropdown
local dropdown_list_visible = false
local update_timer = nil

-- 城市数据
local cities_db = {
    { name = "北京", lat = 39.9042, lng = 116.4074 },
    { name = "上海", lat = 31.2304, lng = 121.4737 },
    { name = "广州", lat = 23.1291, lng = 113.2644 },
    { name = "深圳", lat = 22.5431, lng = 114.0579 },
    { name = "成都", lat = 30.5728, lng = 104.0668 },
    { name = "杭州", lat = 30.2741, lng = 120.1551 },
    { name = "武汉", lat = 30.5928, lng = 114.3055 },
    { name = "西安", lat = 34.3416, lng = 108.9398 },
    { name = "南京", lat = 32.0603, lng = 118.7969 },
    { name = "重庆", lat = 29.4316, lng = 106.9123 },
}

local city_options = {}
local city_name_to_idx = {}
for idx, city in ipairs(cities_db) do
    table.insert(city_options, city.name)
    city_name_to_idx[city.name] = idx
end

local current_city = cities_db[1]

-- 日出日落计算函数
local function get_sun_times(lat, lng, timestamp)
    local t = timestamp or os.time()
    local date = os.date("*t", t)
    
    local year = date.year
    local month = date.month
    local day = date.day
    
    local N1 = math.floor(275 * month / 9)
    local N2 = math.floor((month + 9) / 12)
    local N3 = (1 + math.floor((year - 4 * math.floor(year / 4) + 2) / 3))
    local N = N1 - (N2 * N3) + day - 30
    
    local lngHour = lng / 15
    local t_rise = N + ((6 - lngHour) / 24)
    local t_set = N + ((18 - lngHour) / 24)
    
    local M_rise = (0.9856 * t_rise) - 3.289
    local M_set = (0.9856 * t_set) - 3.289
    
    local L_rise = M_rise + (1.916 * math.sin(math.rad(M_rise))) + (0.020 * math.sin(math.rad(2 * M_rise))) + 282.634
    L_rise = L_rise - 360 * math.floor(L_rise / 360)
    local L_set = M_set + (1.916 * math.sin(math.rad(M_set))) + (0.020 * math.sin(math.rad(2 * M_set))) + 282.634
    L_set = L_set - 360 * math.floor(L_set / 360)
    
    local RA_rise = math.deg(math.atan(0.91764 * math.tan(math.rad(L_rise))))
    RA_rise = RA_rise + 360 * math.floor(RA_rise / 360)
    local Lquadrant_rise = math.floor(L_rise / 90) * 90
    local RAquadrant_rise = math.floor(RA_rise / 90) * 90
    RA_rise = RA_rise + (Lquadrant_rise - RAquadrant_rise)
    RA_rise = RA_rise / 15
    
    local RA_set = math.deg(math.atan(0.91764 * math.tan(math.rad(L_set))))
    RA_set = RA_set + 360 * math.floor(RA_set / 360)
    local Lquadrant_set = math.floor(L_set / 90) * 90
    local RAquadrant_set = math.floor(RA_set / 90) * 90
    RA_set = RA_set + (Lquadrant_set - RAquadrant_set)
    RA_set = RA_set / 15
    
    local sinDec_rise = 0.39782 * math.sin(math.rad(L_rise))
    local cosDec_rise = math.cos(math.asin(sinDec_rise))
    local sinDec_set = 0.39782 * math.sin(math.rad(L_set))
    local cosDec_set = math.cos(math.asin(sinDec_set))
    
    local cosH_rise = (math.cos(math.rad(90.833)) - sinDec_rise * math.sin(math.rad(lat))) / (cosDec_rise * math.cos(math.rad(lat)))
    local cosH_set = (math.cos(math.rad(90.833)) - sinDec_set * math.sin(math.rad(lat))) / (cosDec_set * math.cos(math.rad(lat)))
    
    local H_rise, H_set
    if cosH_rise > 1 then
        H_rise = 0
    elseif cosH_rise < -1 then
        H_rise = 12
    else
        -- 日出时角为负值（太阳在东方地平线）
        H_rise = -math.deg(math.acos(cosH_rise)) / 15
    end
    
    if cosH_set > 1 then
        H_set = 12
    elseif cosH_set < -1 then
        H_set = 0
    else
        -- 日落时角为正值（太阳在西方地平线）
        H_set = math.deg(math.acos(cosH_set)) / 15
    end
    
    local T_rise = H_rise + RA_rise - 0.06571 * t_rise - 6.622
    local T_set = H_set + RA_set - 0.06571 * t_set - 6.622
    
    local UT_rise = T_rise - lngHour
    local UT_set = T_set - lngHour
    
    local localT_rise = UT_rise + 8
    local localT_set = UT_set + 8
    
    localT_rise = localT_rise - 24 * math.floor(localT_rise / 24)
    localT_set = localT_set - 24 * math.floor(localT_set / 24)
    
    -- 确保日出时间小于日落时间
    if localT_rise > localT_set then
        localT_rise = localT_rise - 24
    end
    
    local function format_time(decimal_hours)
        local hours = math.floor(decimal_hours)
        local minutes = math.floor((decimal_hours - hours) * 60)
        if hours < 0 then hours = 0 end
        if hours > 23 then hours = 23 end
        if minutes < 0 then minutes = 0 end
        if minutes > 59 then minutes = 59 end
        return string.format("%02d:%02d", hours, minutes)
    end
    
    -- 计算正午时间（日出和日落的中间）
    local noon_decimal = (localT_rise + localT_set) / 2
    if noon_decimal > 24 then noon_decimal = noon_decimal - 24 end
    local noon_time = format_time(noon_decimal)
    
    -- 计算白昼时长
    local daylight_hours = localT_set - localT_rise
    if daylight_hours < 0 then daylight_hours = daylight_hours + 24 end
    local daylight_h = math.floor(daylight_hours)
    local daylight_m = math.floor((daylight_hours - daylight_h) * 60)
    local daylight_str = string.format("%dh %dm", daylight_h, daylight_m)
    
    -- 计算黄昏结束时间（日落后30分钟）
    local dusk_decimal = localT_set + 0.5
    if dusk_decimal > 24 then dusk_decimal = dusk_decimal - 24 end
    local dusk_time = format_time(dusk_decimal)
    
    return format_time(localT_rise), format_time(localT_set), daylight_str, dusk_time, noon_time
end

-- 更新UI显示
local function update_suntime_ui()
    if not exwin.is_active(win_id) then return end
    
    local sunrise, sunset, daylight, dusk, noon = get_sun_times(current_city.lat, current_city.lng)
    
    if sunrise_label then
        sunrise_label:set_text(sunrise)
    end
    if sunset_label then
        sunset_label:set_text(sunset)
    end
    
    if daylight_label then
        daylight_label:set_text(daylight)
    end
    if dusk_label then
        dusk_label:set_text(dusk)
    end
    if noon_label then
        noon_label:set_text(noon)
    end
    
    if city_label then
        city_label:set_text(current_city.name)
    end
    
    if date_label then
        local t = os.date("*t")
        date_label:set_text(string.format("%04d-%02d-%02d", t.year, t.month, t.day))
    end
    
    if time_label then
        local t = os.date("*t")
        time_label:set_text(string.format("%02d:%02d:%02d", t.hour, t.min, t.sec))
    end
end

-- 选择城市
local function select_city(city)
    current_city = city
    
    if dropdown_list_visible and city_dropdown and city_dropdown.close then
        city_dropdown:close()
        dropdown_list_visible = false
    end
    
    update_suntime_ui()
end

-- 创建UI
local function create_ui()
    -- 主容器（不可滚动）
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xEEF2FA,
        scrollable = false
    })
    
    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 60,
        color = 0x3F51B5
    })
    
    -- 标题
    airui.label({
        parent = title_bar,
        x = 100,
        y = 12,
        w = 280,
        h = 36,
        text = "日出日落",
        font_size = 26,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 城市选择区域
    local city_selector = airui.container({
        parent = main_container,
        x = 12,
        y = 68,
        w = 456,
        h = 52,
        color = 0xFFFFFF,
        radius = 26,
    })
    
    -- 定位图标
    airui.image({
        parent = city_selector,
        x = 12,
        y = 11,
        w = 30,
        h = 30,
        src = "/luadb/Loc.png"
    })
    
    -- 城市下拉选择器
    city_dropdown = airui.dropdown({
        parent = city_selector,
        x = 52,
        y = 11,
        w = 392,
        h = 30,
        options = city_options,
        default_index = 0,
        dropdown_height = 200,
        on_change = function(self, idx)
            local city = cities_db[idx + 1]
            if city then
                select_city(city)
            end
        end,
        on_dropdown_open = function()
            dropdown_list_visible = true
        end,
        on_dropdown_close = function()
            dropdown_list_visible = false
        end
    })
    
    -- 主卡片
    local main_card = airui.container({
        parent = main_container,
        x = 12,
        y = 130,
        w = 456,
        h = 300,
        color = 0xFFFFFF,
        radius = 32
    })
    
    -- 城市标签
    city_label = airui.label({
        parent = main_card,
        x = 20,
        y = 20,
        w = 200,
        h = 30,
        text = "--",
        font_size = 24,
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 日期标签
    date_label = airui.label({
        parent = main_card,
        x = 20,
        y = 55,
        w = 200,
        h = 24,
        text = "--",
        font_size = 18,
        color = 0x5B6E8C,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 时间标签
    time_label = airui.label({
        parent = main_card,
        x = 220,
        y = 55,
        w = 200,
        h = 24,
        text = "--",
        font_size = 18,
        color = 0x5B6E8C,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 日出卡片（紧凑布局，无边框）
    local sunrise_card = airui.container({
        parent = main_card,
        x = 20,
        y = 90,
        w = 200,
        h = 160,
        color = 0xFFF8DC,
        radius = 24
    })

    -- 日出图片（放大）
    airui.image({
        parent = sunrise_card,
        x = 55,
        y = 12,
        w = 90,
        h = 72,
        src = "/luadb/sunrise.png"
    })

    airui.label({
        parent = sunrise_card,
        x = 0,
        y = 88,
        w = 200,
        h = 18,
        text = "日出时间",
        font_size = 12,
        color = 0x444444,
        align = airui.TEXT_ALIGN_CENTER
    })

    sunrise_label = airui.label({
        parent = sunrise_card,
        x = 0,
        y = 108,
        w = 200,
        h = 36,
        text = "--:--",
        font_size = 32,
        color = 0xFF9800,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 日落卡片（紧凑布局，无边框）
    local sunset_card = airui.container({
        parent = main_card,
        x = 236,
        y = 90,
        w = 200,
        h = 160,
        color = 0xFFF8DC,
        radius = 24
    })

    -- 日落图片（放大）
    airui.image({
        parent = sunset_card,
        x = 55,
        y = 12,
        w = 90,
        h = 72,
        src = "/luadb/sunset.png"
    })

    airui.label({
        parent = sunset_card,
        x = 0,
        y = 88,
        w = 200,
        h = 18,
        text = "日落时间",
        font_size = 12,
        color = 0x444444,
        align = airui.TEXT_ALIGN_CENTER
    })

    sunset_label = airui.label({
        parent = sunset_card,
        x = 0,
        y = 108,
        w = 200,
        h = 36,
        text = "--:--",
        font_size = 32,
        color = 0x2196F3,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 统计区域容器（调整高度适应新布局）
    local stats_container = airui.container({
        parent = main_container,
        x = 12,
        y = 440,
        w = 456,
        h = 105,
        color = 0xFFFFFF,
        radius = 24
    })
    
    -- 白昼时长（左列）
    local daylight_card = airui.container({
        parent = stats_container,
        x = 10,
        y = 10,
        w = 138,
        h = 80,
        color = 0xFFF8DC,
        radius = 20
    })
    airui.label({
        parent = daylight_card,
        x = 0,
        y = 10,
        w = 138,
        h = 20,
        text = "白昼时长",
        font_size = 12,
        color = 0x444444,
        align = airui.TEXT_ALIGN_CENTER
    })
    daylight_label = airui.label({
        parent = daylight_card,
        x = 0,
        y = 35,
        w = 138,
        h = 30,
        text = "--",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 黄昏结束（中列）
    local dusk_card = airui.container({
        parent = stats_container,
        x = 159,
        y = 10,
        w = 138,
        h = 80,
        color = 0xFFE1C3,
        radius = 20
    })
    airui.label({
        parent = dusk_card,
        x = 0,
        y = 10,
        w = 138,
        h = 20,
        text = "黄昏结束",
        font_size = 12,
        color = 0x444444,
        align = airui.TEXT_ALIGN_CENTER
    })
    dusk_label = airui.label({
        parent = dusk_card,
        x = 0,
        y = 35,
        w = 138,
        h = 30,
        text = "--",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 正午参考（右列）
    local noon_card = airui.container({
        parent = stats_container,
        x = 308,
        y = 10,
        w = 138,
        h = 80,
        color = 0xD2E6F0,
        radius = 20
    })
    airui.label({
        parent = noon_card,
        x = 0,
        y = 10,
        w = 138,
        h = 20,
        text = "正午参考",
        font_size = 12,
        color = 0x444444,
        align = airui.TEXT_ALIGN_CENTER
    })
    noon_label = airui.label({
        parent = noon_card,
        x = 0,
        y = 35,
        w = 138,
        h = 30,
        text = "--",
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 科普文案（太阳图标在文字左侧，增加间距）
    -- 太阳图标
    airui.image({
        parent = main_container,
        x = 140,
        y = 575,
        w = 20,
        h = 20,
        src = "/luadb/sun.png"
    })

    -- 文案
    airui.label({
        parent = main_container,
        x = 165,
        y = 575,
        w = 200,
        h = 20,
        text = "日照充足，适合出行",
        font_size = 13,
        color = 0x444444,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 退出应用按钮（页面最底部居中，缩小尺寸，增加与文案间距）
    local exit_btn = airui.container({
        parent = main_container,
        x = 140,
        y = 655,
        w = 200,
        h = 36,
        color = 0x3F51B5,
        radius = 18,
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    airui.label({
        parent = exit_btn,
        x = 0,
        y = 8,
        w = 200,
        h = 20,
        text = "退出应用",
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 初始化数据
    select_city(current_city)
    
    -- 启动定时器每秒更新时间
    update_timer = sys.timerLoopStart(function()
        update_suntime_ui()
    end, 1000)
end

-- 窗口生命周期
local function on_create()
    create_ui()
end

local function on_destroy()
    if update_timer then
        sys.timerStop(update_timer)
        update_timer = nil
    end
    if city_dropdown and city_dropdown.close then
        city_dropdown:close()
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    dropdown_list_visible = false
    win_id = nil
end

local function on_get_focus()
    update_suntime_ui()
end

local function on_lose_focus()
end

-- 打开窗口
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_SUNTIME_WIN", open_handler)

return {
    select_city = select_city
}

