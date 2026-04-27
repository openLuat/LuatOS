

--[[
@module  air_quality_win
@summary 全国空气质量监测窗口 - 城市AQI查询与显示
@version 1.0
@date    2026.04.09
@author  xulu
@usage
本模块实现空气质量监测功能，包括：
1. 下拉选择城市与切换
2. 热门城市快捷选择（最多5个，支持编辑删除）
3. 热门城市添加功能
4. AQI指数显示与等级颜色（优/良/轻度污染/中度污染/重度污染/严重污染）
5. PM2.5/PM10/O₃/NO₂/SO₂/CO 六项污染物数据显示
6. 污染物进度条可视化
7. 健康建议（根据AQI等级动态显示）
8. 实时数据刷新（支持请求频率控制）
9. 网络请求失败状态提示（显示在状态栏，不弹窗）
10. 数据加载状态显示（数据获取中...）
]]

local win_id = nil
local main_container, content

-- UI 组件
local aqi_card, aqi_value_label
local aqi_status_label
local health_advice_label
local aqi_level_label
local city_label, date_label
local pm25_label, pm10_label, o3_label, no2_label, so2_label, co_label
local pm25_bar, pm10_bar, o3_bar, no2_bar, so2_bar, co_bar
local update_time_label
local refresh_btn
local refresh_btn_color_timer
local city_dropdown
local city_selector_container
local dropdown_list_visible = false
local hot_bar
local edit_btn

-- 城市数据数据库
local cities_db = {
    -- A
    { name = "澳门", initial = "A" },
    { name = "安康", initial = "A"},
    -- B
    { name = "北京", initial = "B"},
    { name = "保定", initial = "B"},
    { name = "包头", initial = "B"},
    { name = "宝鸡", initial = "B"},
    -- C
    { name = "长沙", initial = "C"},
    { name = "成都", initial = "C"},
    { name = "重庆", initial = "C"},
    { name = "沧州", initial = "C"},
    { name = "常德", initial = "C"},
    -- D
    { name = "大理", initial = "D"},
    { name = "大连", initial = "D"},
    { name = "大庆", initial = "D"},
    { name = "东莞", initial = "D"},
    -- E
    { name = "鄂尔多斯", initial = "E"},
    { name = "恩施", initial = "E"},
    -- F
    { name = "福州", initial = "F"},
    { name = "佛山", initial = "F"},
    { name = "抚顺", initial = "F"},
    -- G
    { name = "广州", initial = "G"},
    { name = "贵阳", initial = "G"},
    { name = "桂林", initial = "G"},
    { name = "赣州", initial = "G"},
    -- H
    { name = "哈尔滨", initial = "H"},
    { name = "海口", initial = "H"},
    { name = "杭州", initial = "H"},
    { name = "合肥", initial = "H"},
    { name = "呼和浩特", initial = "H"},
    { name = "湖州", initial = "H"},
    { name = "汉中", initial = "H"},
    -- J
    { name = "吉林", initial = "J"},
    { name = "济南", initial = "J"},
    { name = "嘉兴", initial = "J"},
    { name = "九江", initial = "J"},
    -- K
    { name = "昆明", initial = "K"},
    { name = "开封", initial = "K"},
    -- L
    { name = "兰州", initial = "L"},
    { name = "拉萨", initial = "L"},
    { name = "柳州", initial = "L"},
    { name = "洛阳", initial = "L"},
    { name = "临沂", initial = "L"},
    -- M
    { name = "绵阳", initial = "M"},
    { name = "茂名", initial = "M"},
    -- N
    { name = "南昌", initial = "N"},
    { name = "南京", initial = "N"},
    { name = "南宁", initial = "N"},
    { name = "南通", initial = "N"},
    -- P
    { name = "莆田", initial = "P"},
    { name = "盘锦", initial = "P"},
    -- Q
    { name = "青岛", initial = "Q"},
    { name = "泉州", initial = "Q"},
    { name = "秦皇岛", initial = "Q"},
    -- R
    { name = "日照", initial = "R"},
    { name = "瑞安", initial = "R"},
    -- S
    { name = "三亚", initial = "S"},
    { name = "厦门", initial = "S"},
    { name = "上海", initial = "S"},
    { name = "深圳", initial = "S"},
    { name = "沈阳", initial = "S"},
    { name = "石家庄", initial = "S"},
    { name = "苏州", initial = "S"},
    -- T
    { name = "台州", initial = "T"},
    { name = "天津", initial = "T"},
    { name = "太原", initial = "T"},
    { name = "唐山", initial = "T"},
    -- W
    { name = "潍坊", initial = "W"},
    { name = "威海", initial = "W"},
    { name = "温州", initial = "W"},
    { name = "武汉", initial = "W"},
    { name = "无锡", initial = "W"},
    { name = "乌鲁木齐", initial = "W"},
    -- X
    { name = "西安", initial = "X"},
    { name = "徐州", initial = "X"},
    { name = "西宁", initial = "X"},
    { name = "襄阳", initial = "X"},
    -- Y
    { name = "烟台", initial = "Y"},
    { name = "延安", initial = "Y"},
    { name = "宜昌", initial = "Y"},
    { name = "银川", initial = "Y"},
    { name = "岳阳", initial = "Y"},
    -- Z
    { name = "枣庄", initial = "Z"},
    { name = "张家界", initial = "Z"},
    { name = "漳州", initial = "Z"},
    { name = "郑州", initial = "Z"},
    { name = "中山", initial = "Z"},
    { name = "珠海", initial = "Z"},
    { name = "遵义", initial = "Z"},
}

-- 生成城市名数组（用于下拉选择器）
local city_options = {}
local city_name_to_idx = {}  -- 城市名到索引的映射
for idx, city in ipairs(cities_db) do
    table.insert(city_options, city.name)
    city_name_to_idx[city.name] = idx
end

-- 热门城市（常用城市，最多5个）
local hot_cities = {
    "北京", "上海", "广州", "深圳", "成都"
}
local hot_edit_mode = false  -- 热门城市编辑模式

-- 当前选中的城市
local current_city = cities_db[1]
local current_selected_city = current_city.name  -- 当前选中的城市名（用于添加按钮）
local current_air_data = nil
local last_request_time = 0  -- 上次请求时间，用于控制请求频率
local REQUEST_INTERVAL = 1000  -- 请求间隔最低1秒

local city_location_cache = {}

-- AQI等级颜色映射（按等级1-6）
local AQI_LEVEL_COLORS = {
    [1] = { color = 0x16A34A, bg = 0xEEF9F0 },       -- 优
    [2] = { color = 0xE98A1E, bg = 0xFFF7ED },       -- 良/普通
    [3] = { color = 0xDC6B1F, bg = 0xFFF0E8 },       -- 轻度污染
    [4] = { color = 0xDC2626, bg = 0xFFE8E8 },       -- 中度污染
    [5] = { color = 0x9B1D3F, bg = 0xF8EDFF },       -- 重度污染
    [6] = { color = 0x7F1A4D, bg = 0xFFE6F0 },       -- 严重污染
}

-- AQI等级默认健康建议（按等级1-6）
local AQI_LEVEL_ADVICE = {
    [1] = "空气清新，适宜各类人群进行户外活动和锻炼。",
    [2] = "空气质量可接受，某些污染物对极少数敏感人群可能有轻微影响。",
    [3] = "儿童、老年人及心脏、呼吸系统疾病患者应减少长时间户外活动。",
    [4] = "儿童、老年人及心脏、呼吸系统疾病患者应避免长时间高强度户外活动。",
    [5] = "儿童、老年人及心脏、呼吸系统疾病患者应留在室内并避免体力消耗。",
    [6] = "儿童、老年人及心脏、呼吸系统疾病患者应避免所有户外活动，其他人也应减少户外活动。",
}

-- 根据等级获取颜色
local function get_level_color(level)
    local level_num = tonumber(level) or 1
    local info = AQI_LEVEL_COLORS[level_num]
    return info and info.color or 0x16A34A,
           info and info.bg or 0xEEF9F0
end

-- 根据AQI获取等级（兼容旧API）
local function get_level_by_aqi(aqi)
    if aqi <= 50 then return 1
    elseif aqi <= 100 then return 2
    elseif aqi <= 150 then return 3
    elseif aqi <= 200 then return 4
    elseif aqi <= 300 then return 5
    else return 6 end
end

-- 根据污染物浓度获取进度条颜色
local function get_bar_color(value)
    if value <= 50 then return 0x4CAF50
    elseif value <= 100 then return 0xFFEB3B
    elseif value <= 150 then return 0xFF9800
    elseif value <= 200 then return 0xF44336
    elseif value <= 300 then return 0x9C27B0
    else return 0x795548 end
end

-- URL编码函数
local function url_encode(str)
    if not str then return "" end
    local s = string.gsub(str, "([^%w%s%-_.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    s = string.gsub(s, " ", "%%20")
    return s
end

-- API域名和KEY配置（域名与KEY绑定）
local API_CONFIG = {
    { domain = "m34d94ahvg.re.qweatherapi.com", key = "f284f44a58474ff6a743b6788ad8c54e" },
    { domain = "nf6hevw9fe.re.qweatherapi.com", key = "4c9391c033b341ad80a0591fc261f80f" }
}

-- 更新状态标签（不同情况显示不同内容）
local function update_status_label(status, city_name, time_str)
    if not update_time_label then return end
    if status == "loading" then
        update_time_label:set_text("数据获取中...")
    elseif status == "success" then
        update_time_label:set_text(string.format("检测城市为：%s 数据更新于：%s", city_name or "--", time_str or "--"))
    elseif status == "error" then
        update_time_label:set_text("数据获取失败，请求过于频繁，请稍后重试")
    else
        update_time_label:set_text("--")
    end
end

-- 获取城市经纬度（带重试）
local function get_city_location(city_name)
    if city_location_cache[city_name] then
        return city_location_cache[city_name].lat, city_location_cache[city_name].lon
    end
    
    -- URL编码城市名
    local encoded_city = url_encode(city_name)
    log.info("[airquality] 编码后城市名:", encoded_city)
    
    -- 尝试不同的API配置
    for idx, cfg in ipairs(API_CONFIG) do
        if idx > 1 then
            log.info("[airquality] 切换API配置:", cfg.domain)
            sys.wait(500)
        end
        
        -- 每个配置重试3次
        for attempt = 1, 3 do
            if attempt > 1 then
                log.info("[airquality] 重试第" .. attempt .. "次")
                sys.wait(500)
            end
            
            local url = "https://" .. cfg.domain .. "/geo/v2/city/lookup?location=" .. encoded_city .. "&key=" .. cfg.key
            log.info("[airquality] 请求经纬度API:", cfg.domain, "尝试", attempt)
            
            local code, headers, body = http.request("GET", url).wait(8000)
            log.info("[airquality] 经纬度响应:", code)
            
            if code == 200 then
                local re = miniz.uncompress(body:sub(11), 0)
                if re then
                    local jdata = json.decode(re)
                    if jdata and jdata.location and #jdata.location > 0 then
                        log.info("[airquality] 搜索结果数量:", #jdata.location)
                        
                        local best_match = nil
                        
                        -- 1. 精确匹配城市名
                        for idx, loc in ipairs(jdata.location) do
                            log.info("[airquality] 候选" .. idx .. ":", loc.name, "adm2=" .. (loc.adm2 or "nil"), "lat=" .. loc.lat, "lon=" .. loc.lon)
                            if loc.name == city_name then
                                best_match = loc
                                log.info("[airquality] 精确匹配城市名:", loc.name)
                                break
                            end
                        end
                        
                        -- 2. 如果没匹配，直接使用第一个结果
                        if not best_match and jdata.location[1] then
                            best_match = jdata.location[1]
                            log.info("[airquality] 使用第一个结果:", best_match.name)
                        end
                        
                        if best_match then
                            city_location_cache[city_name] = { lat = best_match.lat, lon = best_match.lon }
                            return best_match.lat, best_match.lon
                        end
                    end
                end
            else
                log.info("[airquality] 经纬度请求失败:", code)
            end
        end
    end
    
    log.info("[airquality] 所有域名尝试失败:", city_name)
    return nil, nil
end

-- 异步获取空气质量数据
local function get_air_quality_async(city_name, callback)
    log.info("[airquality] 刷新请求城市:", city_name)
    sys.taskInit(function()
        -- 显示加载中状态
        update_status_label("loading")
        
        -- 请求频率控制：确保与上次请求间隔至少1秒
        local now = os.time()*1000
        if now - last_request_time < REQUEST_INTERVAL then
            local wait_time = REQUEST_INTERVAL - (now - last_request_time)
            log.info("[airquality] 请求过于频繁，等待" .. wait_time .. "ms")
            sys.wait(wait_time)
        end
        last_request_time = os.time() * 1000
        
        local lat, lon = get_city_location(city_name)
        if not lat or not lon then
            log.info("[airquality] 获取经纬度失败:", city_name)
            -- 显示失败状态
            update_status_label("error")
            callback(nil)
            return
        end
        
        -- 格式化经纬度为小数点后两位
        local formatted_lat = string.format("%.2f", tonumber(lat))
        local formatted_lon = string.format("%.2f", tonumber(lon))
        log.info("[airquality] 格式化后经纬度:", formatted_lat, formatted_lon)
        
        -- 尝试不同的API配置
        for idx, cfg in ipairs(API_CONFIG) do
            if idx > 1 then
                log.info("[airquality] 切换API配置:", cfg.domain)
                sys.wait(500)
            end
            
            -- 每个配置重试3次
            for attempt = 1, 3 do
                if attempt > 1 then
                    log.info("[airquality] 空气质量请求重试第" .. attempt .. "次")
                    sys.wait(500)
                end
                
                local url = "https://" .. cfg.domain .. "/airquality/v1/current/" .. formatted_lat .. "/" .. formatted_lon .. "?key=" .. cfg.key
                log.info("[airquality] 请求API:", cfg.domain, "尝试", attempt)
                
                local code, headers, body = http.request("GET", url).wait(8000)
                log.info("[airquality] API响应:", code)
                
                if code == 200 then
                    local re = miniz.uncompress(body:sub(11), 0)
                    if not re then
                        log.info("[airquality] 解压失败")
                    else
                        log.info("[airquality] 原始数据:", re)
                        local jdata = json.decode(re)
                        
                        -- 解析数据
                        local data = {
                            city = city_name,
                            aqi = 50,
                            pm25 = 0,
                            pm10 = 0,
                            o3 = 0,
                            no2 = 0,
                            so2 = 0,
                            co = 0,
                            category = "良",
                            effect = "空气质量可接受，但某些污染物可能对极少数异常敏感人群健康有较弱影响。",
                            level = 1,
                            timestamp = os.time()
                        }
                        
                        if jdata and jdata.pollutants then
                            for _, p in ipairs(jdata.pollutants) do
                                local code_p = p.code
                                local value = p.concentration and p.concentration.value or 0
                                if code_p == "pm2.5" or code_p == "PM2.5" or code_p == "pm25" or code_p == "pm2p5" then
                                    data.pm25 = tonumber(value) or 0
                                elseif code_p == "pm10" or code_p == "PM10" then
                                    data.pm10 = tonumber(value) or 0
                                elseif code_p == "o3" or code_p == "O3" then
                                    data.o3 = tonumber(value) or 0
                                elseif code_p == "no2" or code_p == "NO2" then
                                    data.no2 = tonumber(value) or 0
                                elseif code_p == "so2" or code_p == "SO2" then
                                    data.so2 = tonumber(value) or 0
                                elseif code_p == "co" or code_p == "CO" then
                                    data.co = tonumber(value) or 0
                                end
                            end
                            if jdata.indexes and jdata.indexes[1] then
                                data.aqi = tonumber(jdata.indexes[1].aqi) or 50
                                data.category = jdata.indexes[1].category or "良"
                                data.level = tonumber(jdata.indexes[1].level) or 1
                                local effect_val = jdata.indexes[1].health and jdata.indexes[1].health.effect
                                if effect_val and type(effect_val) == "string" and effect_val ~= "" then
                                    data.effect = effect_val
                                else
                                    data.effect = jdata.indexes[1].healthRecommendations or ""
                                end
                            end
                            if jdata.now then
                                data.aqi = data.aqi or tonumber(jdata.now.aqi) or 50
                                data.category = data.category or jdata.now.category or "良"
                                if not data.effect or data.effect == "" then
                                    data.effect = jdata.now.effect or "空气质量可接受"
                                end
                            end
                            current_air_data = data
                            callback(data)
                            return
                        elseif jdata and jdata.now then
                            -- 旧API格式兼容
                            data.aqi = tonumber(jdata.now.aqi) or 50
                            data.category = jdata.now.category or "良"
                            data.pm25 = tonumber(jdata.now.pm2p5) or 0
                            data.pm10 = tonumber(jdata.now.pm10) or 0
                            data.o3 = tonumber(jdata.now.o3) or 0
                            data.no2 = tonumber(jdata.now.no2) or 0
                            data.so2 = tonumber(jdata.now.so2) or 0
                            data.co = tonumber(jdata.now.co) or 0
                            data.effect = jdata.now.effect or "空气质量可接受"
                            data.level = get_level_by_aqi(data.aqi)
                            current_air_data = data
                            callback(data)
                            return
                        end
                    end
                else
                    log.info("[airquality] API请求失败:", code)
                end
            end
        end
        
        log.info("[airquality] 所有域名尝试失败")
        
        -- 显示失败状态
        update_status_label("error")
        
        callback(nil)
    end)
end

-- 刷新UI显示
local function refresh_ui_display()
    if not exwin.is_active(win_id) then return end
    if not current_air_data then return end
    
    local level_color, level_bg = get_level_color(current_air_data.level)

    if aqi_value_label then
        aqi_value_label:set_text(tostring(current_air_data.aqi))
        aqi_value_label:set_color(level_color)
    end
    
    if aqi_status_label then
        aqi_status_label:set_text(current_air_data.category)
        aqi_status_label:set_color(level_color)
    end
    
    
    -- 更新健康建议：优先使用API数据，空时使用预设值
    if health_advice_label then
        local effect = tostring(current_air_data.effect)
        local full_text = (effect and effect ~= "" and effect ~= "nil") and effect or AQI_LEVEL_ADVICE[current_air_data.level]
        health_advice_label:set_text(full_text)
    end
    
    if aqi_level_label then
        aqi_level_label:set_text("level:" .. tostring(current_air_data.level or 1))
        aqi_level_label:set_color(level_color)
    end
    
    if aqi_card then
        aqi_card:set_color(level_bg)
    end
    
    -- 更新城市和日期
    if city_label and current_city then
        city_label:set_text(current_city.name)
    end
    if date_label then
        local t = os.date("*t")
        date_label:set_text(string.format("%02d-%02d", t.month, t.day))
    end
    
    if pm25_label then
        local v = current_air_data.pm25
        pm25_label:set_text(v < 1 and string.format("%.1f", v) or string.format("%.0f", v))
    end
    if pm10_label then
        local v = current_air_data.pm10
        pm10_label:set_text(v < 1 and string.format("%.1f", v) or string.format("%.0f", v))
    end
    if o3_label then
        local v = current_air_data.o3
        o3_label:set_text(v < 1 and string.format("%.1f", v) or string.format("%.0f", v))
    end
    if no2_label then
        local v = current_air_data.no2
        no2_label:set_text(v < 1 and string.format("%.1f", v) or string.format("%.0f", v))
    end
    if so2_label then
        local v = current_air_data.so2
        so2_label:set_text(v < 1 and string.format("%.1f", v) or string.format("%.0f", v))
    end
    if co_label then
        local v = current_air_data.co
        co_label:set_text(v < 1 and string.format("%.1f", v) or string.format("%.0f", v))
    end
    
    -- 更新进度条
    local function update_bar(bar, value)
        if bar then
            local display_value = math.floor(math.min(value, 200))
            if display_value < 0 then display_value = 0 end
            
            pcall(function()
                bar:set_value(display_value)
                bar:set_indicator_color(get_bar_color(value))
            end)
        end
    end
    
    update_bar(pm25_bar, current_air_data.pm25)
    update_bar(pm10_bar, current_air_data.pm10)
    update_bar(o3_bar, current_air_data.o3)
    update_bar(no2_bar, current_air_data.no2)
    update_bar(so2_bar, current_air_data.so2)
    update_bar(co_bar, current_air_data.co)

    -- 更新状态标签为成功
    local time_str = os.date("%H:%M:%S", current_air_data.timestamp)
    update_status_label("success", current_air_data.city, time_str)
end

-- 选择城市
local function select_city(city)
    current_city = city
    current_selected_city = city.name  -- 同步更新当前选中的城市名（用于添加按钮）
    
    current_air_data = nil
    
    if dropdown_list_visible and city_dropdown and city_dropdown.close then
        city_dropdown:close()
        dropdown_list_visible = false
    end
    
    get_air_quality_async(city.name, function(data)
        if data then
            current_air_data = data
        end
        refresh_ui_display()
    end)
end

-- 刷新数据
local function refresh_data()
    -- 先停止之前的定时器，避免多次刷新导致定时器堆积
    if refresh_btn_color_timer then
        sys.timerStop(refresh_btn_color_timer)
        refresh_btn_color_timer = nil
    end
    
    if current_city then
        get_air_quality_async(current_city.name, function(data)
            if data then
                current_air_data = data
                log.info("[airquality] 刷新成功，时间戳:", current_air_data.timestamp)
                refresh_ui_display()
            else
                log.info("[airquality] 刷新失败，数据未更新")
            end
        end)
    end
    
    if refresh_btn then
        refresh_btn:set_color(0x1976D2)
        refresh_btn_color_timer = sys.timerStart(function()
            if refresh_btn then
                refresh_btn:set_color(0x2195F6)
            end
        end, 200)
    end
end

-- 弹窗提示函数
local function show_toast(msg)
    local dialog = airui.container({
        parent = main_container,
        x = 60,
        y = 220,
        w = 360,
        h = 160,
        color = 0xFFFFFF,
        radius = 16
    })
    
    airui.label({
        parent = dialog,
        x = 20,
        y = 20,
        w = 320,
        h = 24,
        text = "提示",
        font_size = 18,
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = dialog,
        x = 20,
        y = 50,
        w = 320,
        h = 60,
        text = msg,
        font_size = 14,
        color = 0x5B6E8C,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.button({
        parent = dialog,
        x = 130,
        y = 110,
        w = 100,
        h = 36,
        text = "确定",
        font_size = 14,
        color = 0x4CAF50,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = function()
            if dialog and dialog.destroy then dialog:destroy() end
        end
    })
end

-- 刷新热门城市栏
local function refresh_hot_cities_bar()
    if hot_bar then
        hot_bar:destroy()
        hot_bar = nil
    end

    hot_bar = airui.container({
        parent = main_container,
        x = 12,
        y = 128,
        w = 456,
        h = 45,
        color = 0xFFFFFF,
        radius = 17
    })
    
    airui.label({
        parent = hot_bar,
        x = 12,
        y = 15,
        w = 40,
        h = 20,
        text = "热门",
        font_size = 12,
        color = 0x8B9AB5,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local hot_btn_w = 66
    local count = math.min(#hot_cities, 5)
    local edit_btn_w = 36
    local total_content_w = 40 + 8 + count * hot_btn_w + (count - 1) * 4 + 8 + edit_btn_w
    local offset_x = (456 - total_content_w) / 2
    
    for i = 1, count do
        local city_name = hot_cities[i]
        local btn_x = 52 + offset_x + (i - 1) * (hot_btn_w + 4)
        
        local hot_btn = airui.container({
            parent = hot_bar,
            x = btn_x,
            y = 10,
            w = hot_btn_w,
            h = 26,
            color = hot_edit_mode and 0xFFE0E0 or 0xF0F4FA,
            radius = 13,
            on_click = function()
                if hot_edit_mode then
                    table.remove(hot_cities, i)
                    hot_edit_mode = false
                    if edit_btn then edit_btn:set_text("编辑") end
                    refresh_hot_cities_bar()
                else
                    local idx = city_name_to_idx[city_name]
                    if idx then
                        select_city(cities_db[idx])
                        if city_dropdown then
                            city_dropdown:set_selected(idx - 1)
                        end
                    end
                end
            end
        })
        
        airui.label({
            parent = hot_btn,
            x = 0,
            y = 3,
            w = hot_btn_w,
            h = 20,
            text = city_name,
            font_size = 11,
            color = hot_edit_mode and 0xF44336 or 0x1E293B,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        if hot_edit_mode then
            airui.label({
                parent = hot_btn,
                x = hot_btn_w - 18,
                y = 2,
                w = 16,
                h = 22,
                text = "×",
                font_size = 18,
                color = 0xF44336,
                align = airui.TEXT_ALIGN_CENTER
            })
        end
    end
    
    edit_btn = airui.button({
        parent = hot_bar,
        x = 52 + offset_x + count * (hot_btn_w + 4) + 8,
        y = 10,
        w = 36,
        h = 26,
        text = "编辑",
        font_size = 11,
        color = hot_edit_mode and 0xF44336 or 0x2196F3,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = function()
            hot_edit_mode = not hot_edit_mode
            refresh_hot_cities_bar()
        end
    })
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
    
    -- 返回按钮
    local back_btn = airui.container({
        parent = title_bar,
        x = 390,
        y = 10,
        w = 80,
        h = 40,
        color = 0x2195F6,
        radius = 20,
        on_click = function()
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    airui.label({
        parent = back_btn,
        x = 10,
        y = 8,
        w = 60,
        h = 24,
        text = "返回",
        font_size = 20,
        color = 0xfefefe,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 刷新按钮
    refresh_btn = airui.container({
        parent = title_bar,
        x = 10,
        y = 10,
        w = 80,
        h = 40,
        color = 0x2195F6,
        radius = 20,
        on_click = refresh_data
    })
    airui.label({
        parent = refresh_btn,
        x = 10,
        y = 8,
        w = 60,
        h = 24,
        text = "刷新",
        font_size = 20,
        color = 0xfefefe,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 标题
    airui.label({
        parent = title_bar,
        x = 100,
        y = 12,
        w = 280,
        h = 36,
        text = "全国空气质量",
        font_size = 26,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- ========== 固定区域（不滚动）==========
    
    -- 城市选择区域
    city_selector_container = airui.container({
        parent = main_container,
        x = 12,
        y = 68,
        w = 456,
        h = 52,
        color = 0xFFFFFF,
        radius = 26,
    })
    
    -- 城市下拉选择器
    city_dropdown = airui.dropdown({
        parent = city_selector_container,
        x = 12,
        y = 11,
        w = 370,
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
    
    -- 添加按钮
    local add_btn = airui.button({
        parent = city_selector_container,
        x = 390,
        y = 11,
        w = 56,
        h = 30,
        text = "添加",
        font_size = 13,
        color = 0x4CAF50,
        align = airui.TEXT_ALIGN_CENTER,
        on_click = function()
            if #hot_cities >= 5 then
                show_toast("最多只能添加5个城市")
                return
            end
            for _, c in ipairs(hot_cities) do
                if c == current_selected_city then
                    show_toast("该城市已在热门列表中")
                    return
                end
            end
            table.insert(hot_cities, current_selected_city)
            show_toast("添加成功: " .. current_selected_city)
            refresh_hot_cities_bar()
        end
    })
    
    -- 热门城市栏（刷新函数会创建）
    refresh_hot_cities_bar()
    
    -- AQI卡片（固定不滚动）
    aqi_card = airui.container({
        parent = main_container,
        x = 12,
        y = 180,
        w = 456,
        h = 170,
        color = 0xEEF9F0,
        radius = 32,
        scrollable = false
    })
    
    -- 城市名称标签
    city_label = airui.label({
        parent = aqi_card,
        x = 20,
        y = 4,
        w = 150,
        h = 20,
        text = "--",
        font_size = 18,
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 日期标签
    date_label = airui.label({
        parent = aqi_card,
        x = 280,
        y = 4,
        w = 156,
        h = 20,
        text = "--",
        font_size = 18,
        color = 0x1E293B,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    airui.label({
        parent = aqi_card,
        x = 20,
        y = 22,
        w = 200,
        h = 18,
        text = "空气质量指数 (AQI)",
        font_size = 18,
        color = 0x1E293B,
        letter_spacing = 1
    })
    
    aqi_value_label = airui.label({
        parent = aqi_card,
        x = 20,
        y = 45,
        w = 160,
        h = 52,
        text = "--",
        font_size = 52,
        color = 0x16A34A,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    aqi_status_label = airui.label({
        parent = aqi_card,
        x = 300,
        y = 48,
        w = 140,
        h = 28,
        text = "--",
        font_size = 20,
        color = 0x16A34A,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    aqi_level_label = airui.label({
        parent = aqi_card,
        x = 300,
        y = 72,
        w = 140,
        h = 18,
        text = "level: --",
        font_size = 12,
        color = 0x5B6E8C,
        align = airui.TEXT_ALIGN_CENTER
    })

    
    airui.label({
        parent = aqi_card,
        x = 20,
        y = 110,
        w = 80,
        h = 18,
        text = "健康建议：",
        font_size = 16,
        color = 0x2196F3,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    health_advice_label = airui.label({
        parent = aqi_card,
        x = 4,
        y = 132,
        w = 450,
        h = 32,
        text = "--",
        font_size = 11,
        color = 0x2196F3,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- ========== 滚动区域（污染物部分）==========
    -- 向上移动10像素：y从370改为360
    content = airui.container({
        parent = main_container,
        x = 0,
        y = 360,  -- 修改这里：370 -> 360
        w = 480,
        h = 430,
        color = 0xEEF2FA,
        scrollable = true,
        scroll_y = true
    })
    
    -- 污染物网格（一行一个）
    local pollutants = {
        { name = "PM2.5", id = "pm25", unit = "μg/m³" },
        { name = "PM10", id = "pm10", unit = "μg/m³" },
        { name = "O₃", id = "o3", unit = "μg/m³" },
        { name = "NO₂", id = "no2", unit = "μg/m³" },
        { name = "SO₂", id = "so2", unit = "μg/m³" },
        { name = "CO", id = "co", unit = "mg/m³" }
    }

    local card_w = 456
    local card_h = 60
    local gap_y = 8
    local start_x = 12
    local start_y = -2

    for i, p in ipairs(pollutants) do
        local x = start_x
        local y = start_y + (i - 1) * (card_h + gap_y)
        
        local card = airui.container({
            parent = content,
            x = x,
            y = y,
            w = card_w,
            h = card_h,
            color = 0xFFFFFF,
            radius = 20,
        })
        
        -- 污染物名称（左侧）
        if p.name == "O₃" then
            airui.label({ parent = card, x = 12, y = 8, w = 16, h = 16, text = "O", font_size = 13, color = 0x6F7D98 })
            airui.label({ parent = card, x = 24, y = 11, w = 12, h = 12, text = "3", font_size = 9, color = 0x6F7D98 })
        elseif p.name == "NO₂" then
            airui.label({ parent = card, x = 12, y = 8, w = 22, h = 16, text = "NO", font_size = 13, color = 0x6F7D98 })
            airui.label({ parent = card, x = 32, y = 11, w = 12, h = 12, text = "2", font_size = 9, color = 0x6F7D98 })
        elseif p.name == "SO₂" then
            airui.label({ parent = card, x = 12, y = 8, w = 22, h = 16, text = "SO", font_size = 13, color = 0x6F7D98 })
            airui.label({ parent = card, x = 32, y = 11, w = 12, h = 12, text = "2", font_size = 9, color = 0x6F7D98 })
        elseif p.name == "PM2.5" then
            airui.label({ parent = card, x = 12, y = 8, w = 26, h = 16, text = "PM", font_size = 13, color = 0x6F7D98 })
            airui.label({ parent = card, x = 34, y = 11, w = 20, h = 12, text = "2.5", font_size = 9, color = 0x6F7D98 })
        elseif p.name == "PM10" then
            airui.label({ parent = card, x = 12, y = 8, w = 26, h = 16, text = "PM", font_size = 13, color = 0x6F7D98 })
            airui.label({ parent = card, x = 34, y = 11, w = 16, h = 12, text = "10", font_size = 9, color = 0x6F7D98 })
        else
            airui.label({ parent = card, x = 12, y = 8, w = 40, h = 16, text = p.name, font_size = 13, color = 0x6F7D98 })
        end
        
        -- 数值（单位前面）
        local value_label = airui.label({
            parent = card,
            x = 280,
            y = 12,
            w = 60,
            h = 28,
            text = "--",
            font_size = 14,
            color = 0x1E293B,
            align = airui.TEXT_ALIGN_RIGHT
        })
        
        -- 单位显示（数值后面，m³用上标3）
        if p.unit == "μg/m³" then
            airui.label({
                parent = card,
                x = 342,
                y = 14,
                w = 20,
                h = 16,
                text = "μg/m",
                font_size = 10,
                color = 0x8A98B5,
                align = airui.TEXT_ALIGN_LEFT
            })
            airui.label({
                parent = card,
                x = 360,
                y = 8,
                w = 10,
                h = 12,
                text = "3",
                font_size = 8,
                color = 0x8A98B5,
                align = airui.TEXT_ALIGN_LEFT
            })
        else
            airui.label({
                parent = card,
                x = 342,
                y = 14,
                w = 16,
                h = 16,
                text = "mg/m",
                font_size = 10,
                color = 0x8A98B5,
                align = airui.TEXT_ALIGN_LEFT
            })
            airui.label({
                parent = card,
                x = 356,
                y = 8,
                w = 10,
                h = 12,
                text = "3",
                font_size = 8,
                color = 0x8A98B5,
                align = airui.TEXT_ALIGN_LEFT
            })
        end
        
        -- 进度条
        local bar = airui.bar({
            parent = card,
            x = 12,
            y = 38,
            w = 432,
            h = 8,
            min = 0,
            max = 200,
            value = 0,
            radius = 4,
            indicator_color = 0x4CAF50,
            bg_color = 0xE8EDF5,
            show_progress_text = false
        })
        
        if p.id == "pm25" then pm25_label = value_label; pm25_bar = bar
        elseif p.id == "pm10" then pm10_label = value_label; pm10_bar = bar
        elseif p.id == "o3" then o3_label = value_label; o3_bar = bar
        elseif p.id == "no2" then no2_label = value_label; no2_bar = bar
        elseif p.id == "so2" then so2_label = value_label; so2_bar = bar
        elseif p.id == "co" then co_label = value_label; co_bar = bar end
    end

-- 更新时间容器（蓝色背景）
local update_time_container = airui.container({
    parent = content,
    x = 12,
    y = 402,
    w = 456,
    h = 23,
    color = 0x2196F3,
    radius = 16,
})

-- 更新时间（在蓝色容器上显示）
update_time_label = airui.label({
    parent = update_time_container,
    x = 0,
    y = 6,
    w = 456,
    h = 20,
    text = "--",
    font_size = 12,
    color = 0xFFFFFF,
    align = airui.TEXT_ALIGN_CENTER
})
 
    -- 设置滚动区域内容高度
    content:set_content_height(450)
    
    -- 初始化数据
    select_city(current_city)
end

-- 窗口生命周期
local function on_create()
    create_ui()
end

local function on_destroy()
    if refresh_btn_color_timer then
        sys.timerStop(refresh_btn_color_timer)
        refresh_btn_color_timer = nil
    end
    if city_dropdown and city_dropdown.close then
        city_dropdown:close()
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    dropdown_list_visible = false
    hot_bar = nil
    win_id = nil
end

local function on_get_focus()
    if current_air_data then
        refresh_ui_display()
    end
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

sys.subscribe("OPEN_AIR_QUALITY_WIN", open_handler)

return {
    refresh_data = refresh_data,
    select_city = select_city
}