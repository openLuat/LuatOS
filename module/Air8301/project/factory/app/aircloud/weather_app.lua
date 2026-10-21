--[[
@module  weather_app
@summary 天气数据应用（内置城市表 + fskv 持久化，与基站定位解耦，8301出厂固件）
@version 2.0
@date    2026.10.10
@author  江访

@usage
本文件为业务模式「主页」首页（idle_win）的「天气」卡片提供数据源。
产测模式不加载本模块（见 main.lua 的模式分流），故产测首页不受影响。

数据链路（v2.0 起与基站定位彻底解耦）：
  城市 / 经纬度 ← 本模块内置城市表（CITIES）+ fskv 持久化（键 WEATHER_CITY），默认深圳
  天气实况      ← Open-Meteo 免费接口（无需注册 Key，按经纬度查询）
  解析结果      → sys.publish("WEATHER_UPDATE", state) 通知 UI 刷新

  与 v1.0 的差异：v1.0 的经纬度来自 airlbs_app 基站定位（Airlbs_LOCATION_UPDATE）
  并经地址反查得到城市名；v2.0 起改由本地配置提供，定位链路（airlbs_app）保持独立运行，
  仅用于 aircloud_data 的经纬度上报，不再影响天气。

刷新策略：
  1) 任务启动后等待默认网卡就绪（IP_READY）；
  2) 每轮先回推一次缓存（UI 打开页面时能立刻看到上次结果），再拉取最新；
  3) 之后每 REQUEST_INTERVAL（5 分钟）拉取一次；
  4) UI 每次打开页面会发布 WEATHER_QUERY，可随时唤醒任务立即刷新；
  5) 城市变更（WEATHER_CITY_SET）立即刷新。

容错：
  - 请求失败时保留上一次成功结果，不把界面打回 "--"；
  - 请求过程整体 pcall 包裹，单次异常不会终止常驻任务。

对外接口：
  M.get_city()    → string 当前城市名（供 weather_set_win 展示）
  M.get_cities()  → table  内置城市表（{{名称, 纬度, 经度}, ...}，供 weather_set_win 展示）

消息接口：
  WEATHER_QUERY        无参          立即刷新请求（UI 打开页面时发布）
  WEATHER_CITY_SET     name string   设置城市（保存到 fskv 并立即刷新）
  WEATHER_UPDATE       state table   天气数据更新通知（本模块发布，UI 订阅）
]]

local M = {}

-- ==================== 内置城市表（名称 + 经纬度） ====================
-- 说明：与基站定位解耦后，天气按本表选定的城市查询，不再依赖网络定位服务。
-- 经纬度为城市中心坐标（保留两位小数），供 Open-Meteo 接口按经纬度查询使用。
local CITIES = {
    { "深圳", 22.55, 114.06 },
    { "广州", 23.13, 113.26 },
    { "北京", 39.90, 116.41 },
    { "上海", 31.23, 121.47 },
    { "天津", 39.13, 117.20 },
    { "重庆", 29.56, 106.55 },
    { "成都", 30.57, 104.07 },
    { "杭州", 30.27, 120.15 },
    { "武汉", 30.59, 114.31 },
    { "西安", 34.34, 108.94 },
    { "南京", 32.06, 118.80 },
    { "苏州", 31.30, 120.58 },
    { "郑州", 34.75, 113.63 },
    { "长沙", 28.23, 112.94 },
    { "东莞", 23.02, 113.75 },
    { "青岛", 36.07, 120.38 },
    { "沈阳", 41.80, 123.43 },
    { "宁波", 29.87, 121.55 },
    { "昆明", 25.05, 102.71 },
    { "合肥", 31.82, 117.23 },
    { "佛山", 23.02, 113.12 },
    { "无锡", 31.49, 120.31 },
    { "厦门", 24.48, 118.09 },
    { "福州", 26.07, 119.30 },
    { "济南", 36.65, 117.12 },
    { "大连", 38.91, 121.61 },
    { "哈尔滨", 45.80, 126.53 },
    { "长春", 43.82, 125.32 },
    { "石家庄", 38.04, 114.51 },
    { "南宁", 22.82, 108.37 },
}

-- 出厂默认城市（首次开机 / 配置非法时使用）
local DEFAULT_CITY = "深圳"

-- ==================== 天气代码映射（WMO Weather interpretation codes） ====================

local WMO_TEXT = {
    [0]  = "晴",
    [1]  = "晴间多云",
    [2]  = "局部多云",
    [3]  = "阴",
    [45] = "有雾",
    [48] = "雾凇",
    [51] = "毛毛雨",
    [53] = "小雨",
    [55] = "中雨",
    [56] = "冻毛毛雨",
    [57] = "冻雨",
    [61] = "小雨",
    [63] = "中雨",
    [65] = "大雨",
    [66] = "冻雨",
    [67] = "强冻雨",
    [71] = "小雪",
    [73] = "中雪",
    [75] = "大雪",
    [77] = "雪粒",
    [80] = "阵雨",
    [81] = "强阵雨",
    [82] = "暴雨",
    [85] = "阵雪",
    [86] = "强阵雪",
    [95] = "雷阵雨",
    [96] = "雷阵雨伴冰雹",
    [99] = "强雷暴伴冰雹",
}

-- 风向方位（顺时针，从正北起）
local WIND_DIRS = { "北", "东北", "东", "东南", "南", "西南", "西", "西北" }

-- 蒲福风级上限（km/h）：风速小于该值即为对应等级（1 级 1~5、2 级 6~11 ……）
local BEAUFORT_MAX = { 1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118 }

-- ==================== 事件名、存储键与刷新周期 ====================

local QUERY_EVENT  = "WEATHER_QUERY"      -- 立即刷新请求（UI 打开页面时发布）
local CITY_EVENT   = "WEATHER_CITY_SET"   -- 城市设置（weather_set_win 发布）
local UPDATE_EVENT = "WEATHER_UPDATE"     -- 天气数据更新通知（本模块发布，UI 订阅）
local CITY_KEY     = "WEATHER_CITY"       -- fskv 存储键：当前城市名

local REQUEST_INTERVAL = 5 * 60 * 1000    -- 常规刷新周期：5 分钟
local REQUEST_TIMEOUT  = 15000            -- 单次 HTTP 请求超时：15 秒

-- ==================== 数据缓存 ====================

--[[天气状态表（发布给 UI 的结构，字段含义见各注释）
  ok          boolean 是否已成功获取过至少一次
  text        string  天气现象中文描述
  temp        number  当前温度（℃）
  feels       number  体感温度（℃）
  humidity    number  相对湿度（%）
  wind_dir    string  风向中文（如「东南」）
  wind_level  number  风力等级（0~12）
  wind_speed  number  风速（km/h）
  tmax/tmin   number  今日最高 / 最低温度（℃）
  city        string  城市名（来自本地配置）
  update_time string  最近一次成功更新时间（HH:MM）
  lat/lng     number  当前城市经纬度
]]
local state = {
    ok = false,
    text = "--",
    temp = nil, feels = nil, humidity = nil,
    wind_dir = "", wind_level = nil, wind_speed = nil,
    tmax = nil, tmin = nil,
    city = "",
    update_time = "",
    lat = nil, lng = nil,
}

--[[把当前天气状态发布给 UI

@local
@function publish_state
]]
local function publish_state()
    sys.publish(UPDATE_EVENT, state)
end

-- ==================== 数值格式化辅助 ====================

--[[风速（km/h）→ 蒲福风级

@local
@function wind_level_of
@param kmh number 风速（km/h）
@return number 风级（0~12），非法输入返回 nil
]]
local function wind_level_of(kmh)
    if type(kmh) ~= "number" then return nil end
    for i = 1, #BEAUFORT_MAX do
        if kmh < BEAUFORT_MAX[i] then return i - 1 end
    end
    return 12
end

--[[风向角度 → 中文方位

@local
@function wind_dir_of
@param deg number 风向角度（0~360，正北为 0）
@return string 中文方位（如「东南」），非法输入返回空串
]]
local function wind_dir_of(deg)
    if type(deg) ~= "number" then return "" end
    local i = math.floor(((deg % 360) + 22.5) / 45) % 8 + 1
    return WIND_DIRS[i]
end

-- ==================== 城市配置 ====================

--[[按城市名查内置城市表

@local
@function find_city
@param name string 城市名（如「深圳」）
@return number|nil 纬度
@return number|nil 经度
]]
local function find_city(name)
    if type(name) ~= "string" or name == "" then return nil, nil end
    for i = 1, #CITIES do
        if CITIES[i][1] == name then return CITIES[i][2], CITIES[i][3] end
    end
    return nil, nil
end

--[[应用城市：查表并写入 state；非法城市名回退默认城市

@local
@function apply_city_name
@param name string 城市名
@return string 实际生效的城市名
]]
local function apply_city_name(name)
    local lat, lng = find_city(name)
    if not lat then
        name = DEFAULT_CITY
        lat, lng = find_city(name)
    end
    state.city = name
    state.lat, state.lng = lat, lng
    return name
end

--[[从 fskv 加载城市配置（无保存则使用默认城市）

@local
@function load_city
]]
local function load_city()
    fskv.init()
    local name = fskv.get(CITY_KEY)
    local city = apply_city_name((type(name) == "string" and name ~= "") and name or DEFAULT_CITY)
    log.info("weather_app", "城市配置:", city, state.lat, state.lng)
end

--[[城市设置回调（WEATHER_CITY_SET）：保存到 fskv 并立即刷新天气

@local
@function on_city_set
@param name string 城市名
]]
local function on_city_set(name)
    if type(name) ~= "string" or name == "" then return end
    local old = state.city
    local city = apply_city_name(name)
    fskv.set(CITY_KEY, city)
    log.info("weather_app", "城市已设置:", city, state.lat, state.lng)
    if city ~= old then
        sys.publish(QUERY_EVENT)
    end
    publish_state()
end

sys.subscribe(CITY_EVENT, on_city_set)

-- ==================== 天气请求 ====================

--[[请求 Open-Meteo 天气并解析入库

@local
@function request_weather
@return boolean 是否成功
]]
local function request_weather()
    if state.lat == nil or state.lng == nil then
        log.info("weather_app", "未选择城市，跳过天气请求")
        return false
    end

    local url = "https://api.open-meteo.com/v1/forecast?latitude=" .. string.format("%.2f", state.lat) ..
        "&longitude=" .. string.format("%.2f", state.lng) ..
        "&current=temperature_2m,relative_humidity_2m,apparent_temperature," ..
        "weather_code,wind_speed_10m,wind_direction_10m" ..
        "&daily=temperature_2m_max,temperature_2m_min" ..
        "&forecast_days=1&timezone=Asia%2FShanghai"

    log.info("weather_app", "请求天气", url)

    local code, _, body = http.request("GET", url, nil, nil, { timeout = REQUEST_TIMEOUT }).wait()
    if code ~= 200 or type(body) ~= "string" or #body == 0 then
        log.warn("weather_app", "天气请求失败, code:", code)
        return false
    end

    -- 服务器若以 gzip 应答（魔数 1F 8B）则先解压：gzip 头 10 字节需跳过，余下为裸 deflate
    if #body > 2 and body:byte(1) == 0x1F and body:byte(2) == 0x8B then
        if miniz and miniz.uncompress then
            local ok, un = pcall(miniz.uncompress, body:sub(11, -1), 0)
            if ok and type(un) == "string" and #un > 0 then
                body = un
            else
                log.warn("weather_app", "天气应答 gzip 解压失败，按原文解析")
            end
        else
            log.warn("weather_app", "应答为 gzip 但本固件无 miniz，按原文解析")
        end
    end

    local d = json.decode(body)
    if type(d) ~= "table" or type(d.current) ~= "table" then
        log.warn("weather_app", "天气应答解析失败")
        return false
    end

    local c = d.current
    state.temp       = c.temperature_2m
    state.feels      = c.apparent_temperature
    state.humidity   = c.relative_humidity_2m
    state.wind_speed = c.wind_speed_10m
    state.wind_dir   = wind_dir_of(c.wind_direction_10m)
    state.wind_level = wind_level_of(c.wind_speed_10m)
    state.text       = WMO_TEXT[c.weather_code] or ("未知")

    if type(d.daily) == "table" then
        state.tmax = d.daily.temperature_2m_max and d.daily.temperature_2m_max[1]
        state.tmin = d.daily.temperature_2m_min and d.daily.temperature_2m_min[1]
    end

    state.ok = true
    state.update_time = os.date("%H:%M")
    log.info("weather_app", "天气更新:", state.city, state.text, state.temp, "℃ 湿度", state.humidity, "%")
    publish_state()
    return true
end

-- ==================== 常驻任务 ====================

--[[天气刷新常驻任务

@local
@function weather_task
]]
local function weather_task()
    -- 等待默认网卡就绪（与 time_sync / airlbs_app 保持一致的等待范式）
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 5000)
    end

    -- 加载本地城市配置（内置城市表 + fskv，无需等待网络定位）
    load_city()

    while true do
        -- 每轮无条件回推一次缓存：即使天气尚未成功（ok=false），也要把已配置的城市名推给 UI，
        -- 否则主页打开时若天气未就绪，城市会恒显示 "--"
        publish_state()

        -- pcall 包裹：单次请求异常（DNS / TLS / 解析）不影响常驻任务
        pcall(request_weather)

        -- 常规周期等待；期间收到 WEATHER_QUERY 则立即唤醒刷新
        sys.waitUntil(QUERY_EVENT, REQUEST_INTERVAL)
    end
end

sys.taskInit(weather_task)

-- ==================== 对外接口 ====================

--[[取当前城市名

@return string 当前城市名
]]
function M.get_city()
    return state.city
end

--[[取内置城市表（只读，供城市设置页展示）

@return table {{名称, 纬度, 经度}, ...}
]]
function M.get_cities()
    return CITIES
end

return M
