--[[
@module weather_app
@summary 灵境天气 · 随天气而变 — AirUI 完整实现 (V10.4 最终版)
]]

-------------------------------------------------------------------------------
-- 常量与配置
-------------------------------------------------------------------------------
local SCREEN_W, SCREEN_H = 480, 800
local MAX_CITIES = 5
local STORAGE_KEY_CITIES = "weather_my_cities"
local STORAGE_KEY_CURRENT = "weather_current_city"

-- 重试配置
local MAX_RETRY_COUNT = 3      -- 最大重试次数
local RETRY_DELAY_MS = 15000   -- 重试间隔15秒

-- 和风天气API配置
local WEATHER_API_KEY = "6679d599d9b544aaae409427d994b18e"
local API_HOST = "mx6yw28mt4.re.qweatherapi.com"

-- 全国城市库（按字母排序）
local ALL_CITIES = {"北京", "成都", "重庆", "大连", "福州", "广州", "贵阳", "哈尔滨", "海口",
                    "杭州", "合肥", "呼和浩特", "济南", "昆明", "拉萨", "兰州", "南昌", "南京",
                    "南宁", "青岛", "上海", "沈阳", "深圳", "石家庄", "苏州", "天津", "武汉",
                    "西安", "西宁", "厦门", "银川", "长春", "长沙", "郑州", "乌鲁木齐"}

-- 默认城市列表
local DEFAULT_CITIES = {"北京"}

-- 城市信息缓存
local city_info_cache = {}

-- 城市名到拼音的映射
local city_pinyin_map = {
    ["北京"] = "beijing",
    ["成都"] = "chengdu",
    ["重庆"] = "chongqing",
    ["大连"] = "dalian",
    ["福州"] = "fuzhou",
    ["广州"] = "guangzhou",
    ["贵阳"] = "guiyang",
    ["哈尔滨"] = "haerbin",
    ["海口"] = "haikou",
    ["杭州"] = "hangzhou",
    ["合肥"] = "hefei",
    ["呼和浩特"] = "huhehaote",
    ["济南"] = "jinan",
    ["昆明"] = "kunming",
    ["拉萨"] = "lasa",
    ["兰州"] = "lanzhou",
    ["南昌"] = "nanchang",
    ["南京"] = "nanjing",
    ["南宁"] = "nanning",
    ["青岛"] = "qingdao",
    ["上海"] = "shanghai",
    ["沈阳"] = "shenyang",
    ["深圳"] = "shenzhen",
    ["石家庄"] = "shijiazhuang",
    ["苏州"] = "suzhou",
    ["天津"] = "tianjin",
    ["武汉"] = "wuhan",
    ["西安"] = "xian",
    ["西宁"] = "xining",
    ["厦门"] = "xiamen",
    ["银川"] = "yinchuan",
    ["长春"] = "changchun",
    ["长沙"] = "changsha",
    ["郑州"] = "zhengzhou",
    ["乌鲁木齐"] = "wulumuqi"
}

-- 颜色常量
local C = {
    bg_main = 0xE3F2FD,
    bg_sunny = 0xFFE6C7,
    bg_cloudy = 0xD3D9E0,
    bg_overcast = 0xBFC9D2,
    bg_rainy = 0xAAC9D4,
    bg_snowy = 0xE6F0FA,
    card_bg = 0xFFFAFA,
    badge_bg = 0xFFFFFA,
    btn_icon_bg = 0xFFF8DC,
    btn_back_bg = 0xDDEEFF,
    text_primary = 0x1f2e36,
    text_secondary = 0x2b685b,
    temp_color = 0x1f4e44,
    metric_bg = 0xFFFFF0,
    metric_border = 0xFFD796,
    city_panel_bg = 0xFFFCF3,
    city_title = 0x2B6B5E,
    dropdown_bg = 0xFFFFFFFF,
    dropdown_border = 0xE0CFAE,
    dropdown_item_bg = 0xFFFFFF,
    dropdown_item_hover = 0xF5F0E8,
    switch_bg = 0xC6E9E6,
    switch_dis = 0xE0E6E5,
    delete_bg = 0xFFCFAE,
    toast_bg = 0x2F6B5E,
    detail_bg_fixed = 0xE8F4F8,
    popup_bg = 0xFFFFFF,
    popup_btn_ok = 0x2F6B5E,
    popup_btn_cancel = 0xCCCCCC
}

-- 字体大小
local FS = {
    city_name = 18,
    temp_big = 70,
    temp_unit = 32,
    weather_desc = 70,
    feels_badge = 14,
    update_time = 12,
    metric_label = 12,
    metric_value = 18,
    panel_title = 20,
    city_item = 17,
    dropdown_item = 14,
    popup_title = 18,
    popup_text = 14
}

-------------------------------------------------------------------------------
-- 状态变量
-------------------------------------------------------------------------------
local win_id = nil
local current_city = "北京"
local my_cities = {"北京"}

-- UI 组件引用
local root_container = nil
local page_main = nil
local page_city_overlay = nil
local page_add_city = nil
local page_search_detail = nil

-- 主页组件
local lbl_city_name = nil
local lbl_temp_value = nil
local lbl_weather_desc = nil
local lbl_weather_icon = nil
local lbl_feels_like = nil
local lbl_update_time = nil
local lbl_humidity = nil
local lbl_wind_speed = nil
local lbl_precip = nil
local lbl_wind_dir = nil
local lbl_wind_level = nil
local lbl_pressure = nil
local lbl_visibility = nil
local lbl_clouds = nil
local bg_gradient = nil

-- 下拉列表组件
local city_dropdown_list = nil
local city_dropdown_visible = false
local add_dropdown_list = nil
local add_dropdown_visible = false
local dropdown_processing = false

-- 详情页组件
local detail_city_name = nil
local detail_temp_value = nil
local detail_weather_desc = nil
local detail_feels_like = nil
local detail_update_time = nil
local detail_humidity = nil
local detail_wind_speed = nil
local detail_precip = nil
local detail_wind_dir = nil
local detail_wind_level = nil
local detail_pressure = nil
local detail_visibility = nil
local detail_clouds = nil
local detail_bg_gradient = nil

-- 弹窗组件
local delete_confirm_popup = nil
local delete_confirm_bg = nil
local pending_delete_city = nil

-- 城市列表容器
local my_cities_list_cont = nil
local my_cities_label = nil

-- 计时器
local toast_timer = nil
local current_toast = nil

-- 天气数据缓存
local weather_cache = {}

-- 重试相关变量
local retry_timer = nil
local pending_retry_callback = nil
local pending_retry_city = nil
local retry_count = 0

-------------------------------------------------------------------------------
-- Toast 提示函数
-------------------------------------------------------------------------------
local function show_toast(msg)
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end

    if current_toast then
        current_toast:destroy()
        current_toast = nil
    end

    if not root_container then
        return
    end

    current_toast = airui.container({
        parent = root_container,
        x = SCREEN_W / 2 - 130,
        y = SCREEN_H - 65,
        w = 260,
        h = 40,
        color = C.toast_bg,
        radius = 20
    })

    airui.label({
        parent = current_toast,
        x = 0,
        y = 8,
        w = 260,
        h = 24,
        text = msg,
        font_size = 13,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    toast_timer = sys.timerStart(function()
        if current_toast then
            current_toast:destroy()
            current_toast = nil
        end
        toast_timer = nil
    end, 1400)
end

-------------------------------------------------------------------------------
-- 数据持久化
-------------------------------------------------------------------------------
local function save_data()
    if not fskv then
        return
    end
    fskv.set(STORAGE_KEY_CITIES, my_cities)
    fskv.set(STORAGE_KEY_CURRENT, current_city)
end

local function load_data()
    if not fskv then
        return
    end

    local saved_cities = fskv.get(STORAGE_KEY_CITIES)
    if saved_cities and type(saved_cities) == "table" and #saved_cities > 0 then
        my_cities = saved_cities
    else
        my_cities = DEFAULT_CITIES
    end

    local saved_current = fskv.get(STORAGE_KEY_CURRENT)
    if saved_current and type(saved_current) == "string" then
        local found = false
        for _, c in ipairs(my_cities) do
            if c == saved_current then
                found = true
                break
            end
        end
        if found then
            current_city = saved_current
        else
            current_city = my_cities[1] or "北京"
        end
    else
        current_city = my_cities[1] or "北京"
    end
end

-------------------------------------------------------------------------------
-- 工具函数
-------------------------------------------------------------------------------
local function get_weather_icon_text(desc)
    if not desc or desc == "--" then
        return "?"
    end
    return string.sub(desc, 1, 1)
end

local function get_bg_color(desc)
    if not desc or desc == "--" then
        return C.bg_main
    end
    if string.find(desc, "晴") then
        return C.bg_sunny
    elseif string.find(desc, "云") then
        return C.bg_cloudy
    elseif string.find(desc, "阴") then
        return C.bg_overcast
    elseif string.find(desc, "雨") then
        return C.bg_rainy
    elseif string.find(desc, "雪") then
        return C.bg_snowy
    else
        return C.bg_main
    end
end

local function set_weather_to_placeholder()
    if lbl_temp_value then
        lbl_temp_value:set_text("--")
    end
    if lbl_weather_desc then
        lbl_weather_desc:set_text("--")
    end
    if lbl_weather_icon then
        lbl_weather_icon:set_text("?")
    end
    if lbl_feels_like then
        lbl_feels_like:set_text("体感温度 --°")
    end
    if lbl_update_time then
        lbl_update_time:set_text("--:--")
    end
    if lbl_humidity then
        lbl_humidity:set_text("--%")
    end
    if lbl_wind_speed then
        lbl_wind_speed:set_text("-- km/h")
    end
    if lbl_precip then
        lbl_precip:set_text("-- mm")
    end
    if lbl_wind_dir then
        lbl_wind_dir:set_text("--")
    end
    if lbl_wind_level then
        lbl_wind_level:set_text("--")
    end
    if lbl_pressure then
        lbl_pressure:set_text("-- hPa")
    end
    if lbl_visibility then
        lbl_visibility:set_text("-- km")
    end
    if lbl_clouds then
        lbl_clouds:set_text("--%")
    end
    if bg_gradient then
        bg_gradient:set_color(C.bg_main)
    end
end

-- 停止重试定时器
local function stop_retry_timer()
    if retry_timer then
        sys.timerStop(retry_timer)
        retry_timer = nil
    end
end

-------------------------------------------------------------------------------
-- HTTP API 请求函数
-------------------------------------------------------------------------------
-- 获取城市信息
local function get_city_info(city_name)
    -- 检查缓存
    if city_info_cache[city_name] and city_info_cache[city_name].id then
        return city_info_cache[city_name]
    end

    local pinyin_name = city_pinyin_map[city_name] or city_name
    local url = "https://" .. API_HOST .. "/geo/v2/city/lookup?location=" .. pinyin_name .. "&key=" .. WEATHER_API_KEY
    log.info("weather", "请求城市信息: " .. url)

    local code, headers, body = http.request("GET", url).wait(5000)
    if code ~= 200 then
        log.warn("weather", "获取城市信息失败, code: " .. tostring(code))
        return nil
    end

    local re = miniz.uncompress(body:sub(11), 0)
    if not re then
        log.warn("weather", "解压失败")
        return nil
    end

    local jdata = json.decode(re)
    if not jdata or not jdata.location or #jdata.location == 0 then
        log.warn("weather", "未找到城市信息: " .. city_name)
        return nil
    end

    -- 如果有多个匹配结果，打印日志并使用第一个
    if #jdata.location > 1 then
        log.info("weather", "城市 " .. city_name .. " 返回 " .. #jdata.location .. " 个匹配结果，使用第一个")
        for i, loc in ipairs(jdata.location) do
            log.info("weather", "  匹配项 " .. i .. ": " .. loc.name .. " (ID:" .. loc.id .. ", 类型:" .. (loc.type or "未知") .. ")")
        end
    end

    -- 使用第一个匹配结果
    local first_match = jdata.location[1]
    local info = {
        id = first_match.id,
        lat = first_match.lat,
        lon = first_match.lon,
        name = first_match.name,
        adm1 = first_match.adm1 or "",
        adm2 = first_match.adm2 or "",
        country = first_match.country or ""
    }
    city_info_cache[city_name] = info
    log.info("weather", "获取城市信息成功: " .. city_name .. " -> " .. info.name .. " (ID:" .. info.id .. ")")
    return info
end

-- 执行实际的天气数据请求
local function do_weather_request(city_name, callback)
    local city_info = get_city_info(city_name)
    if not city_info or not city_info.id then
        if callback then
            callback(nil)
        end
        return
    end

    local url = "https://" .. API_HOST .. "/v7/weather/now?location=" .. city_info.id .. "&key=" .. WEATHER_API_KEY
    log.info("weather", "请求实时天气: " .. url)

    local code, headers, body = http.request("GET", url).wait(5000)
    if code ~= 200 then
        log.warn("weather", "获取天气失败, code: " .. tostring(code))
        if callback then
            callback(nil)
        end
        return
    end

    local re = miniz.uncompress(body:sub(11), 0)
    if not re then
        log.warn("weather", "解压失败")
        if callback then
            callback(nil)
        end
        return
    end

    local jdata = json.decode(re)
    if not jdata or jdata.code ~= "200" or not jdata.now then
        log.warn("weather", "天气数据无效, code: " .. tostring(jdata and jdata.code))
        if callback then
            callback(nil)
        end
        return
    end

    local now = jdata.now
    log.info("weather", "实时天气获取成功 - 温度: " .. now.temp .. "°C, 天气: " .. now.text)

    local weather_data = {
        city = city_name,
        temp = tonumber(now.temp) or 0,
        desc = now.text or "--",
        feels_like = tonumber(now.feelsLike) or tonumber(now.temp) or 0,
        humidity = tonumber(now.humidity) or 0,
        wind_kph = tonumber(now.windSpeed) or 0,
        precip = tonumber(now.precip) or 0,
        wind_dir = now.windDir or "北风",
        wind_level = (tonumber(now.windScale) or 1) .. "级",
        pressure = tonumber(now.pressure) or 0,
        visibility = tonumber(now.vis) or 0,
        clouds = tonumber(now.cloud) or 0,
        time_str = os.date("%H:%M", os.time()),
        success = true
    }

    if callback then
        callback(weather_data)
    end
end

-- 带重试机制的天气数据获取
local function get_weather_async_with_retry(city_name, callback, retry_num)
    local retry = retry_num or 0
    
    sys.taskInit(function()
        do_weather_request(city_name, function(data)
            if data and data.success then
                -- 成功，清除重试状态
                stop_retry_timer()
                retry_count = 0
                pending_retry_city = nil
                pending_retry_callback = nil
                if callback then
                    callback(data)
                end
            else
                -- 失败，判断是否需要重试
                if retry < MAX_RETRY_COUNT then
                    log.info("weather", "获取天气失败，第" .. (retry + 1) .. "次重试，15秒后重试")
                    show_toast("获取天气失败，" .. (MAX_RETRY_COUNT - retry) .. "秒后重试...")
                    
                    -- 保存回调信息用于重试
                    pending_retry_city = city_name
                    pending_retry_callback = callback
                    retry_count = retry + 1
                    
                    -- 设置重制定时器
                    stop_retry_timer()
                    retry_timer = sys.timerStart(function()
                        get_weather_async_with_retry(pending_retry_city, pending_retry_callback, retry_count)
                    end, RETRY_DELAY_MS)
                else
                    log.warn("weather", "重试" .. MAX_RETRY_COUNT .. "次后仍然失败")
                    show_toast("天气获取失败，请稍后重试")
                    if callback then
                        callback(nil)
                    end
                    stop_retry_timer()
                    retry_count = 0
                    pending_retry_city = nil
                    pending_retry_callback = nil
                end
            end
        end)
    end)
end

-- 获取天气数据
local function fetch_weather(city_name, on_success)
    local cached = weather_cache[city_name]
    local cache_time = weather_cache[city_name .. "_time"] or 0
    if cached and cached.success and (os.time() - cache_time) < 300 then
        if on_success then
            on_success(cached)
        end
        return
    end

    get_weather_async_with_retry(city_name, function(data)
        if data and data.success then
            -- 缓存数据
            weather_cache[city_name] = data
            weather_cache[city_name .. "_time"] = os.time()
            if on_success then
                on_success(data)
            end
        else
            if cached and cached.success then
                if on_success then
                    on_success(cached)
                end
            else
                if on_success then
                    on_success(nil)
                end
            end
        end
    end, 0)
end

-------------------------------------------------------------------------------
-- 天气数据渲染
-------------------------------------------------------------------------------
local function load_main_weather()
    set_weather_to_placeholder()
    if lbl_city_name then
        lbl_city_name:set_text(current_city)
    end

    fetch_weather(current_city, function(w)
        if not w then
            return
        end

        if lbl_temp_value then
            lbl_temp_value:set_text(tostring(w.temp))
        end
        if lbl_weather_desc then
            lbl_weather_desc:set_text(w.desc)
        end
        if lbl_weather_icon then
            lbl_weather_icon:set_text(get_weather_icon_text(w.desc))
        end
        if lbl_feels_like then
            lbl_feels_like:set_text(string.format("体感温度 %d°", w.feels_like))
        end
        if lbl_update_time then
            lbl_update_time:set_text(w.time_str)
        end
        if lbl_humidity then
            lbl_humidity:set_text(string.format("%d%%", w.humidity))
        end
        if lbl_wind_speed then
            lbl_wind_speed:set_text(string.format("%d km/h", w.wind_kph))
        end
        if lbl_precip then
            lbl_precip:set_text(string.format("%.1f mm", w.precip))
        end
        if lbl_wind_dir then
            lbl_wind_dir:set_text(w.wind_dir)
        end
        if lbl_wind_level then
            lbl_wind_level:set_text(w.wind_level)
        end
        if lbl_pressure then
            lbl_pressure:set_text(string.format("%d hPa", w.pressure))
        end
        if lbl_visibility then
            lbl_visibility:set_text(string.format("%d km", w.visibility))
        end
        if lbl_clouds then
            lbl_clouds:set_text(string.format("%d%%", w.clouds))
        end
        if bg_gradient then
            bg_gradient:set_color(get_bg_color(w.desc))
        end
    end)
end

local function set_detail_placeholder()
    if detail_city_name then
        detail_city_name:set_text("--")
    end
    if detail_temp_value then
        detail_temp_value:set_text("--")
    end
    if detail_weather_desc then
        detail_weather_desc:set_text("--")
    end
    if detail_feels_like then
        detail_feels_like:set_text("体感温度 --°")
    end
    if detail_update_time then
        detail_update_time:set_text("--:--")
    end
    if detail_humidity then
        detail_humidity:set_text("--%")
    end
    if detail_wind_speed then
        detail_wind_speed:set_text("-- km/h")
    end
    if detail_precip then
        detail_precip:set_text("-- mm")
    end
    if detail_wind_dir then
        detail_wind_dir:set_text("--")
    end
    if detail_wind_level then
        detail_wind_level:set_text("--")
    end
    if detail_pressure then
        detail_pressure:set_text("-- hPa")
    end
    if detail_visibility then
        detail_visibility:set_text("-- km")
    end
    if detail_clouds then
        detail_clouds:set_text("--%")
    end
    if detail_bg_gradient then
        detail_bg_gradient:set_color(C.detail_bg_fixed)
    end
end

local function load_detail_and_show(city)
    set_detail_placeholder()
    if detail_city_name then
        detail_city_name:set_text(city)
    end

    fetch_weather(city, function(w)
        if not w then
            if page_city_overlay then
                page_city_overlay:set_hidden(true)
            end
            if page_search_detail then
                page_search_detail:set_hidden(false)
            end
            return
        end

        if detail_city_name then
            detail_city_name:set_text(w.city)
        end
        if detail_temp_value then
            detail_temp_value:set_text(tostring(w.temp))
        end
        if detail_weather_desc then
            detail_weather_desc:set_text(w.desc)
        end
        if detail_feels_like then
            detail_feels_like:set_text(string.format("体感温度 %d°", w.feels_like))
        end
        if detail_update_time then
            detail_update_time:set_text(w.time_str)
        end
        if detail_humidity then
            detail_humidity:set_text(string.format("%d%%", w.humidity))
        end
        if detail_wind_speed then
            detail_wind_speed:set_text(string.format("%d km/h", w.wind_kph))
        end
        if detail_precip then
            detail_precip:set_text(string.format("%.1f mm", w.precip))
        end
        if detail_wind_dir then
            detail_wind_dir:set_text(w.wind_dir)
        end
        if detail_wind_level then
            detail_wind_level:set_text(w.wind_level)
        end
        if detail_pressure then
            detail_pressure:set_text(string.format("%d hPa", w.pressure))
        end
        if detail_visibility then
            detail_visibility:set_text(string.format("%d km", w.visibility))
        end
        if detail_clouds then
            detail_clouds:set_text(string.format("%d%%", w.clouds))
        end

        if detail_bg_gradient then
            detail_bg_gradient:set_color(C.detail_bg_fixed)
        end

        if page_city_overlay then
            page_city_overlay:set_hidden(true)
        end
        if page_search_detail then
            page_search_detail:set_hidden(false)
        end
    end)
end

local function force_refresh()
    -- 清除缓存强制重新获取
    weather_cache[current_city] = nil
    weather_cache[current_city .. "_time"] = nil
    -- 清除重试状态
    stop_retry_timer()
    retry_count = 0
    load_main_weather()
    show_toast("正在刷新天气...")
end

-------------------------------------------------------------------------------
-- 删除确认弹窗函数
-------------------------------------------------------------------------------
local function show_delete_confirm_popup(city)
    pending_delete_city = city

    if delete_confirm_popup then
        delete_confirm_popup:destroy()
        delete_confirm_popup = nil
    end
    if delete_confirm_bg then
        delete_confirm_bg:destroy()
        delete_confirm_bg = nil
    end

    delete_confirm_bg = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x80000000
    })

    delete_confirm_popup = airui.container({
        parent = delete_confirm_bg,
        x = SCREEN_W / 2 - 140,
        y = SCREEN_H / 2 - 80,
        w = 280,
        h = 160,
        color = C.popup_bg,
        radius = 16
    })

    airui.label({
        parent = delete_confirm_popup,
        x = 0,
        y = 20,
        w = 280,
        h = 28,
        text = "确认删除",
        font_size = FS.popup_title,
        color = C.city_title,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = delete_confirm_popup,
        x = 0,
        y = 58,
        w = 280,
        h = 24,
        text = "确定要删除城市 " .. city .. " 吗？",
        font_size = FS.popup_text,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.button({
        parent = delete_confirm_popup,
        x = 20,
        y = 110,
        w = 110,
        h = 36,
        text = "确定",
        font_size = 14,
        style = {
            bg_color = C.popup_btn_ok,
            text_color = 0xFFFFFF,
            radius = 8,
            border_width = 0,
            pad = 0
        },
        on_click = function()
            if pending_delete_city then
                local new_list = {}
                for _, c in ipairs(my_cities) do
                    if c ~= pending_delete_city then
                        table.insert(new_list, c)
                    end
                end
                my_cities = new_list
                render_my_cities_list()
                save_data()
                show_toast("已删除 " .. pending_delete_city)
                pending_delete_city = nil
            end
            if delete_confirm_bg then
                delete_confirm_bg:destroy();
                delete_confirm_bg = nil
            end
            if delete_confirm_popup then
                delete_confirm_popup:destroy();
                delete_confirm_popup = nil
            end
        end
    })

    airui.button({
        parent = delete_confirm_popup,
        x = 150,
        y = 110,
        w = 110,
        h = 36,
        text = "取消",
        font_size = 14,
        style = {
            bg_color = C.popup_btn_cancel,
            text_color = 0x333333,
            radius = 8,
            border_width = 0,
            pad = 0
        },
        on_click = function()
            pending_delete_city = nil
            if delete_confirm_bg then
                delete_confirm_bg:destroy();
                delete_confirm_bg = nil
            end
            if delete_confirm_popup then
                delete_confirm_popup:destroy();
                delete_confirm_popup = nil
            end
        end
    })
end

local function show_limit_popup()
    local mb = airui.msgbox({
        title = "城市数量已达上限",
        text = "最多只能保存 5 个城市哦",
        buttons = {"确定"},
        on_action = function(self, label)
            self:hide();
            self:destroy()
        end
    })
    mb:show()
end

-------------------------------------------------------------------------------
-- 下拉列表功能
-------------------------------------------------------------------------------
-- 创建城市下拉列表
local function create_city_dropdown()
    if city_dropdown_list then
        city_dropdown_list:destroy()
        city_dropdown_list = nil
    end

    local dropdown_w = SCREEN_W - 100
    local dropdown_x = 50
    local dropdown_height = math.min(#ALL_CITIES * 36, 300)
    local item_h = 36

    city_dropdown_list = airui.container({
        parent = page_city_overlay,
        x = dropdown_x,
        y = 146,
        w = dropdown_w,
        h = dropdown_height,
        color = C.dropdown_bg,
        radius = 12,
        border_width = 1,
        border_color = C.dropdown_border,
        scrollable = true,
        scroll_y = true
    })

    for i, city in ipairs(ALL_CITIES) do
        local item_y = (i - 1) * item_h
        airui.button({
            parent = city_dropdown_list,
            x = 0,
            y = item_y,
            w = dropdown_w,
            h = item_h,
            text = city,
            font_size = FS.dropdown_item,
            style = {
                bg_color = C.dropdown_item_bg,
                text_color = C.city_title,
                radius = 0,
                border_width = 0,
                pad = 0
            },
            on_click = function()
                sys.timerStart(function()
                    load_detail_and_show(city)
                    if city_dropdown_visible then
                        if city_dropdown_list then
                            city_dropdown_list:destroy()
                            city_dropdown_list = nil
                        end
                        city_dropdown_visible = false
                        dropdown_processing = false
                    end
                end, 50)
            end
        })
    end
end

-- 创建添加城市下拉列表
local function create_add_dropdown()
    if add_dropdown_list then
        add_dropdown_list:destroy()
        add_dropdown_list = nil
    end

    local dropdown_w = SCREEN_W - 100
    local dropdown_x = 50
    local dropdown_height = math.min(#ALL_CITIES * 36, 300)
    local item_h = 36

    add_dropdown_list = airui.container({
        parent = page_add_city,
        x = dropdown_x,
        y = 146,
        w = dropdown_w,
        h = dropdown_height,
        color = C.dropdown_bg,
        radius = 12,
        border_width = 1,
        border_color = C.dropdown_border,
        scrollable = true,
        scroll_y = true
    })

    for i, city in ipairs(ALL_CITIES) do
        local item_y = (i - 1) * item_h
        airui.button({
            parent = add_dropdown_list,
            x = 0,
            y = item_y,
            w = dropdown_w,
            h = item_h,
            text = city,
            font_size = FS.dropdown_item,
            style = {
                bg_color = C.dropdown_item_bg,
                text_color = C.city_title,
                radius = 0,
                border_width = 0,
                pad = 0
            },
            on_click = function()
                sys.timerStart(function()
                    if #my_cities >= MAX_CITIES then
                        show_limit_popup()
                        if add_dropdown_visible then
                            if add_dropdown_list then
                                add_dropdown_list:destroy()
                                add_dropdown_list = nil
                            end
                            add_dropdown_visible = false
                        end
                        dropdown_processing = false
                        return
                    end
                    local exists = false
                    for _, c in ipairs(my_cities) do
                        if c == city then
                            exists = true
                            break
                        end
                    end
                    if not exists then
                        table.insert(my_cities, city)
                        render_my_cities_list()
                        open_city_page()
                        save_data()
                        show_toast("已添加 " .. city)
                    else
                        show_toast(city .. " 已在列表中")
                    end
                    if add_dropdown_visible then
                        if add_dropdown_list then
                            add_dropdown_list:destroy()
                            add_dropdown_list = nil
                        end
                        add_dropdown_visible = false
                    end
                    dropdown_processing = false
                end, 50)
            end
        })
    end
end

-- 城市下拉框切换函数（带防抖）
local function toggle_city_dropdown()
    if dropdown_processing then
        return
    end
    dropdown_processing = true
    
    if city_dropdown_visible then
        if city_dropdown_list then
            city_dropdown_list:destroy()
            city_dropdown_list = nil
        end
        city_dropdown_visible = false
        dropdown_processing = false
    else
        if add_dropdown_visible then
            if add_dropdown_list then
                add_dropdown_list:destroy()
                add_dropdown_list = nil
            end
            add_dropdown_visible = false
        end
        create_city_dropdown()
        city_dropdown_visible = true
        sys.timerStart(function()
            dropdown_processing = false
        end, 200)
    end
end

-- 添加城市下拉框切换函数
local function toggle_add_dropdown()
    if dropdown_processing then
        return
    end
    dropdown_processing = true
    
    if add_dropdown_visible then
        if add_dropdown_list then
            add_dropdown_list:destroy()
            add_dropdown_list = nil
        end
        add_dropdown_visible = false
        dropdown_processing = false
    else
        if city_dropdown_visible then
            if city_dropdown_list then
                city_dropdown_list:destroy()
                city_dropdown_list = nil
            end
            city_dropdown_visible = false
        end
        create_add_dropdown()
        add_dropdown_visible = true
        sys.timerStart(function()
            dropdown_processing = false
        end, 200)
    end
end

-------------------------------------------------------------------------------
-- 城市列表渲染
-------------------------------------------------------------------------------
function render_my_cities_list()
    if my_cities_list_cont then
        my_cities_list_cont:destroy()
        my_cities_list_cont = nil
    end

    if my_cities_label then
        my_cities_label:destroy()
        my_cities_label = nil
    end

    if not page_city_overlay then
        return
    end

    my_cities_label = airui.label({
        parent = page_city_overlay,
        x = 28,
        y = 350,
        w = 250,
        h = 24,
        text = "我的常用城市 (" .. #my_cities .. "/" .. MAX_CITIES .. ")",
        font_size = 16,
        color = C.city_title
    })

    my_cities_list_cont = airui.container({
        parent = page_city_overlay,
        x = 22,
        y = 380,
        w = SCREEN_W - 44,
        h = SCREEN_H - 420,
        color = C.city_panel_bg
    })

    local item_y = 0
    for idx, city in ipairs(my_cities) do
        local is_current = (city == current_city)
        local switch_txt = is_current and "正在使用" or "切换"

        local row = airui.container({
            parent = my_cities_list_cont,
            x = 0,
            y = item_y,
            w = SCREEN_W - 44,
            h = 52,
            color = 0xFFFFFFFF,
            radius = 24,
            border_width = 1,
            border_color = 0xF5E2BE
        })

        airui.label({
            parent = row,
            x = 20,
            y = 14,
            w = 150,
            h = 24,
            text = city,
            font_size = FS.city_item,
            color = 0x2F6B5E
        })

        local btn_x = SCREEN_W - 180
        local sw_color = is_current and C.switch_dis or C.switch_bg
        local sw_tcolor = is_current and 0x999999 or 0x20554A

        airui.button({
            parent = row,
            x = btn_x,
            y = 11,
            w = 68,
            h = 30,
            text = switch_txt,
            font_size = 12,
            style = {
                bg_color = sw_color,
                text_color = sw_tcolor,
                radius = 30,
                border_width = 0,
                pad = 0
            },
            on_click = function()
                if is_current then
                    return
                end
                current_city = city
                load_main_weather()
                render_my_cities_list()
                close_all_pages()
                save_data()
                show_toast("已切换至 " .. city)
            end
        })

        airui.button({
            parent = row,
            x = btn_x + 76,
            y = 11,
            w = 56,
            h = 30,
            text = "删除",
            font_size = 13,
            style = {
                bg_color = C.delete_bg,
                text_color = 0x7A4024,
                radius = 30,
                border_width = 0,
                pad = 0
            },
            on_click = function()
                if city == current_city then
                    show_toast("当前使用的城市不能删除")
                    return
                end
                show_delete_confirm_popup(city)
            end
        })
        item_y = item_y + 62
    end
end

-------------------------------------------------------------------------------
-- 页面导航
-------------------------------------------------------------------------------
function close_all_pages()
    if city_dropdown_list then
        city_dropdown_list:destroy()
        city_dropdown_list = nil
        city_dropdown_visible = false
    end
    if add_dropdown_list then
        add_dropdown_list:destroy()
        add_dropdown_list = nil
        add_dropdown_visible = false
    end
    dropdown_processing = false
    if page_main then
        page_main:set_hidden(false)
    end
    if page_city_overlay then
        page_city_overlay:set_hidden(true)
    end
    if page_add_city then
        page_add_city:set_hidden(true)
    end
    if page_search_detail then
        page_search_detail:set_hidden(true)
    end
end

function open_city_page()
    if city_dropdown_list then
        city_dropdown_list:destroy()
        city_dropdown_list = nil
        city_dropdown_visible = false
    end
    if add_dropdown_list then
        add_dropdown_list:destroy()
        add_dropdown_list = nil
        add_dropdown_visible = false
    end
    dropdown_processing = false

    if page_main then
        page_main:set_hidden(true)
    end
    if page_city_overlay then
        page_city_overlay:set_hidden(false)
    end
    if page_add_city then
        page_add_city:set_hidden(true)
    end
    if page_search_detail then
        page_search_detail:set_hidden(true)
    end

    render_my_cities_list()
end

function open_add_page()
    if city_dropdown_list then
        city_dropdown_list:destroy()
        city_dropdown_list = nil
        city_dropdown_visible = false
    end
    if add_dropdown_list then
        add_dropdown_list:destroy()
        add_dropdown_list = nil
        add_dropdown_visible = false
    end
    dropdown_processing = false

    if page_city_overlay then
        page_city_overlay:set_hidden(true)
    end
    if page_add_city then
        page_add_city:set_hidden(false)
    end
end

function back_to_city_from_detail()
    if city_dropdown_list then
        city_dropdown_list:destroy()
        city_dropdown_list = nil
        city_dropdown_visible = false
    end
    if add_dropdown_list then
        add_dropdown_list:destroy()
        add_dropdown_list = nil
        add_dropdown_visible = false
    end
    dropdown_processing = false
    if page_search_detail then
        page_search_detail:set_hidden(true)
    end
    if page_city_overlay then
        page_city_overlay:set_hidden(false)
    end
    render_my_cities_list()
end

-------------------------------------------------------------------------------
-- UI 构建
-------------------------------------------------------------------------------
local function create_ui()
    root_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.bg_main,
        radius = 44
    })

    bg_gradient = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.bg_main,
        radius = 44
    })

    -----------------------------------------------------------------------
    -- 1. 主页
    -----------------------------------------------------------------------
    page_main = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.bg_main
    })

    airui.button({
        parent = page_main,
        x = 10,
        y = 18,
        w = 70,
        h = 40,
        text = "返回",
        font_size = 15,
        style = {
            bg_color = C.btn_back_bg,
            text_color = C.city_title,
            radius = 20,
            border_width = 1,
            border_color = 0xBBDDF0,
            pad = 4
        },
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end
    })

    local city_badge = airui.container({
        parent = page_main,
        x = (SCREEN_W - 160) / 2,
        y = 26,
        w = 160,
        h = 34,
        color = C.badge_bg,
        radius = 30
    })
    lbl_city_name = airui.label({
        parent = city_badge,
        x = 0,
        y = 6,
        w = 160,
        h = 22,
        text = current_city,
        font_size = FS.city_name,
        color = 0x2C5A4C,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.button({
        parent = page_main,
        x = SCREEN_W - 100,
        y = 18,
        w = 44,
        h = 40,
        text = "刷新",
        font_size = 14,
        style = {
            bg_color = C.btn_icon_bg,
            text_color = 0x2F6B5C,
            radius = 22,
            border_width = 0,
            pad = 2
        },
        on_click = function()
            force_refresh()
        end
    })
    airui.button({
        parent = page_main,
        x = SCREEN_W - 52,
        y = 18,
        w = 44,
        h = 40,
        text = "城市",
        font_size = 14,
        style = {
            bg_color = C.btn_icon_bg,
            text_color = 0x2F6B5C,
            radius = 22,
            border_width = 0,
            pad = 2
        },
        on_click = function()
            open_city_page()
        end
    })

    local card_w = SCREEN_W - 40
    local main_card = airui.container({
        parent = page_main,
        x = 20,
        y = 88,
        w = card_w,
        h = 180,
        color = C.card_bg,
        radius = 48
    })

    -- 温度显示
    lbl_temp_value = airui.label({
        parent = main_card,
        x = 240,
        y = 30,
        w = card_w - 240,
        h = 70,
        text = "--",
        font_size = FS.temp_big,
        color = C.temp_color
    })
    airui.label({
        parent = main_card,
        x = card_w - 90,
        y = 40,
        w = 70,
        h = 32,
        text = "°C",
        font_size = FS.temp_unit,
        color = C.temp_color
    })

    -- 天气描述
    lbl_weather_desc = airui.label({
        parent = main_card,
        x = 30,
        y = 30,
        w = 200,
        h = 70,
        text = "--",
        font_size = FS.weather_desc,
        color = C.text_secondary
    })

    -- 体感温度
    lbl_feels_like = airui.label({
        parent = main_card,
        x = 30,
        y = 110,
        w = 200,
        h = 24,
        text = "体感温度 --°C",
        font_size = FS.feels_badge
    })

    -- 更新时间
    airui.label({
        parent = main_card,
        x = 30,
        y = 150,
        w = 150,
        h = 18,
        text = "最近更新",
        font_size = FS.update_time,
        color = 0x888888
    })
    lbl_update_time = airui.label({
        parent = main_card,
        x = card_w - 100,
        y = 150,
        w = 78,
        h = 18,
        text = "--:--",
        font_size = FS.update_time,
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 指标网格
    local grid_x, grid_y = 20, 288
    local tile_w = (SCREEN_W - 40 - 14) / 2
    local tile_h = 72
    local gap = 14
    local metrics = {
        {"湿度", "lbl_humidity", "%"},
        {"风速", "lbl_wind_speed", "km/h"},
        {"降水量", "lbl_precip", "mm"},
        {"风向", "lbl_wind_dir", ""},
        {"风力等级", "lbl_wind_level", ""},
        {"气压", "lbl_pressure", "hPa"},
        {"能见度", "lbl_visibility", "km"},
        {"云量", "lbl_clouds", "%"}
    }
    local metric_refs = {}
    for i, m in ipairs(metrics) do
        local col = (i - 1) % 2
        local tx = grid_x + col * (tile_w + gap)
        local ty = grid_y + math.floor((i - 1) / 2) * (tile_h + gap)
        local tile = airui.container({
            parent = page_main,
            x = tx,
            y = ty,
            w = tile_w,
            h = tile_h,
            color = C.metric_bg,
            radius = 28,
            border_width = 1,
            border_color = C.metric_border
        })
        airui.label({
            parent = tile,
            x = 12,
            y = 8,
            w = tile_w - 24,
            h = 18,
            text = m[1],
            font_size = FS.metric_label,
            color = 0x666666
        })
        local val_lbl = airui.label({
            parent = tile,
            x = 12,
            y = 32,
            w = tile_w - 24,
            h = 28,
            text = "-- " .. m[3],
            font_size = FS.metric_value,
            color = C.text_secondary
        })
        metric_refs[m[2]] = val_lbl
    end
    lbl_humidity = metric_refs.lbl_humidity
    lbl_wind_speed = metric_refs.lbl_wind_speed
    lbl_precip = metric_refs.lbl_precip
    lbl_wind_dir = metric_refs.lbl_wind_dir
    lbl_wind_level = metric_refs.lbl_wind_level
    lbl_pressure = metric_refs.lbl_pressure
    lbl_visibility = metric_refs.lbl_visibility
    lbl_clouds = metric_refs.lbl_clouds

    -----------------------------------------------------------------------
    -- 2. 城市库页面
    -----------------------------------------------------------------------
    page_city_overlay = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.city_panel_bg
    })
    page_city_overlay:set_hidden(true)

    airui.button({
        parent = page_city_overlay,
        x = 22,
        y = 40,
        w = 80,
        h = 40,
        text = "返回",
        font_size = 16,
        style = {
            bg_color = C.city_panel_bg,
            text_color = C.city_title,
            radius = 20,
            border_width = 0,
            pad = 0
        },
        on_click = function()
            close_all_pages()
        end
    })
    airui.label({
        parent = page_city_overlay,
        x = 170,
        y = 45,
        w = 140,
        h = 30,
        text = "我的城市库",
        font_size = FS.panel_title,
        color = C.city_title,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.button({
        parent = page_city_overlay,
        x = SCREEN_W - 66,
        y = 38,
        w = 44,
        h = 44,
        text = "+",
        font_size = 28,
        style = {
            bg_color = 0xC6F0E9,
            text_color = C.city_title,
            radius = 22,
            border_width = 0,
            pad = 0
        },
        on_click = function()
            open_add_page()
        end
    })

    airui.button({
        parent = page_city_overlay,
        x = 50,
        y = 100,
        w = SCREEN_W - 100,
        h = 46,
        text = "选择城市",
        font_size = 16,
        style = {
            bg_color = C.dropdown_bg,
            text_color = C.city_title,
            radius = 30,
            border_width = 1,
            border_color = C.dropdown_border,
            pad = 12
        },
        on_click = function()
            toggle_city_dropdown()
        end
    })

    -----------------------------------------------------------------------
    -- 3. 添加城市页面
    -----------------------------------------------------------------------
    page_add_city = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.city_panel_bg
    })
    page_add_city:set_hidden(true)

    airui.button({
        parent = page_add_city,
        x = 22,
        y = 40,
        w = 80,
        h = 40,
        text = "返回",
        font_size = 16,
        style = {
            bg_color = C.city_panel_bg,
            text_color = C.city_title,
            radius = 20,
            border_width = 0,
            pad = 0
        },
        on_click = function()
            open_city_page()
        end
    })
    airui.label({
        parent = page_add_city,
        x = 190,
        y = 45,
        w = 100,
        h = 30,
        text = "添加城市",
        font_size = 20,
        color = C.city_title
    })

    airui.button({
        parent = page_add_city,
        x = 50,
        y = 100,
        w = SCREEN_W - 100,
        h = 46,
        text = "选择要添加的城市",
        font_size = 16,
        style = {
            bg_color = C.dropdown_bg,
            text_color = C.city_title,
            radius = 30,
            border_width = 1,
            border_color = C.dropdown_border,
            pad = 12
        },
        on_click = function()
            toggle_add_dropdown()
        end
    })

    -----------------------------------------------------------------------
    -- 4. 城市天气详情页
    -----------------------------------------------------------------------
    page_search_detail = airui.container({
        parent = root_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.city_panel_bg
    })
    page_search_detail:set_hidden(true)

    detail_bg_gradient = airui.container({
        parent = page_search_detail,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = C.detail_bg_fixed
    })

    airui.button({
        parent = page_search_detail,
        x = 10,
        y = 18,
        w = 70,
        h = 40,
        text = "返回",
        font_size = 15,
        style = {
            bg_color = C.btn_back_bg,
            text_color = C.city_title,
            radius = 20,
            border_width = 1,
            border_color = 0xBBDDF0,
            pad = 4
        },
        on_click = function()
            back_to_city_from_detail()
        end
    })

    local detail_badge = airui.container({
        parent = page_search_detail,
        x = (SCREEN_W - 160) / 2,
        y = 26,
        w = 160,
        h = 34,
        color = C.badge_bg,
        radius = 30
    })
    detail_city_name = airui.label({
        parent = detail_badge,
        x = 0,
        y = 6,
        w = 160,
        h = 22,
        text = "--",
        font_size = FS.city_name,
        color = 0x2C5A4C,
        align = airui.TEXT_ALIGN_CENTER
    })

    local detail_card = airui.container({
        parent = page_search_detail,
        x = 20,
        y = 88,
        w = card_w,
        h = 180,
        color = C.card_bg,
        radius = 48
    })

    detail_temp_value = airui.label({
        parent = detail_card,
        x = 240,
        y = 30,
        w = card_w - 240,
        h = 70,
        text = "--",
        font_size = FS.temp_big,
        color = C.temp_color
    })
    airui.label({
        parent = detail_card,
        x = card_w - 90,
        y = 40,
        w = 70,
        h = 32,
        text = "°C",
        font_size = FS.temp_unit,
        color = C.temp_color
    })

    detail_weather_desc = airui.label({
        parent = detail_card,
        x = 30,
        y = 30,
        w = 200,
        h = 70,
        text = "--",
        font_size = FS.weather_desc,
        color = C.text_secondary
    })

    detail_feels_like = airui.label({
        parent = detail_card,
        x = 30,
        y = 110,
        w = 200,
        h = 24,
        text = "体感温度 --°C",
        font_size = FS.feels_badge
    })

    airui.label({
        parent = detail_card,
        x = 30,
        y = 150,
        w = 150,
        h = 18,
        text = "最近更新",
        font_size = FS.update_time,
        color = 0x888888
    })
    detail_update_time = airui.label({
        parent = detail_card,
        x = card_w - 100,
        y = 150,
        w = 78,
        h = 18,
        text = "--:--",
        font_size = FS.update_time,
        color = 0x888888,
        align = airui.TEXT_ALIGN_RIGHT
    })

    local detail_metrics = {
        {"湿度", "detail_humidity", "%"},
        {"风速", "detail_wind_speed", "km/h"},
        {"降水量", "detail_precip", "mm"},
        {"风向", "detail_wind_dir", ""},
        {"风力等级", "detail_wind_level", ""},
        {"气压", "detail_pressure", "hPa"},
        {"能见度", "detail_visibility", "km"},
        {"云量", "detail_clouds", "%"}
    }
    for i, m in ipairs(detail_metrics) do
        local col = (i - 1) % 2
        local tx = grid_x + col * (tile_w + gap)
        local ty = grid_y + math.floor((i - 1) / 2) * (tile_h + gap)
        local tile = airui.container({
            parent = page_search_detail,
            x = tx,
            y = ty,
            w = tile_w,
            h = tile_h,
            color = C.metric_bg,
            radius = 28,
            border_width = 1,
            border_color = C.metric_border
        })
        airui.label({
            parent = tile,
            x = 12,
            y = 8,
            w = tile_w - 24,
            h = 18,
            text = m[1],
            font_size = FS.metric_label,
            color = 0x666666
        })
        local val_lbl = airui.label({
            parent = tile,
            x = 12,
            y = 32,
            w = tile_w - 24,
            h = 28,
            text = "-- " .. m[3],
            font_size = FS.metric_value,
            color = C.text_secondary
        })
        if m[2] == "detail_humidity" then
            detail_humidity = val_lbl
        elseif m[2] == "detail_wind_speed" then
            detail_wind_speed = val_lbl
        elseif m[2] == "detail_precip" then
            detail_precip = val_lbl
        elseif m[2] == "detail_wind_dir" then
            detail_wind_dir = val_lbl
        elseif m[2] == "detail_wind_level" then
            detail_wind_level = val_lbl
        elseif m[2] == "detail_pressure" then
            detail_pressure = val_lbl
        elseif m[2] == "detail_visibility" then
            detail_visibility = val_lbl
        elseif m[2] == "detail_clouds" then
            detail_clouds = val_lbl
        end
    end

    load_main_weather()
    render_my_cities_list()
end

-------------------------------------------------------------------------------
-- 窗口生命周期
-------------------------------------------------------------------------------
local function on_create()
    load_data()
    create_ui()
    sys.timerStart(function()
        load_main_weather()
    end, 100)
end

local function on_destroy()
    stop_retry_timer()
    save_data()
    win_id = nil
    if root_container then
        root_container:destroy();
        root_container = nil
    end
    if toast_timer then
        sys.timerStop(toast_timer);
        toast_timer = nil
    end
    if current_toast then
        current_toast:destroy();
        current_toast = nil
    end
    if delete_confirm_popup then
        delete_confirm_popup:destroy();
        delete_confirm_popup = nil
    end
    if delete_confirm_bg then
        delete_confirm_bg:destroy();
        delete_confirm_bg = nil
    end
    if city_dropdown_list then
        city_dropdown_list:destroy();
        city_dropdown_list = nil
    end
    if add_dropdown_list then
        add_dropdown_list:destroy();
        add_dropdown_list = nil
    end
end

local function on_get_focus()
end
local function on_lose_focus()
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus
    })
end

sys.subscribe("OPEN_WEATHER_WIN", open_handler)
