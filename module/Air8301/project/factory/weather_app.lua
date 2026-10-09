--[[
@module  weather_app
@summary 天气与位置数据应用（Open-Meteo 免费接口，8301出厂固件）
@version 1.0
@date    2026.10.09
@author  江访

@usage
本文件为业务模式「主页」首页（idle_win）的「时间 + 天气」界面提供数据源。
产测模式不加载本模块（见 main.lua 的模式分流），故产测首页不受影响。

数据链路：
  定位经纬度 ← 订阅 airlbs_app 发布的 Airlbs_LOCATION_UPDATE(lat, lng)
  城市名称   ← 订阅 airlbs_app 发布的 AIRLBS_ADDRESS_UPDATE(address)
  天气实况   ← Open-Meteo 免费接口（无需注册 Key，按经纬度查询）
  解析结果   → sys.publish("WEATHER_UPDATE", state) 通知 UI 刷新

刷新策略：
  1) 任务启动后等待默认网卡就绪（IP_READY）；
  2) 每轮先回推一次缓存（UI 打开页面时能立刻看到上次结果），再拉取最新；
  3) 之后每 REQUEST_INTERVAL（15 分钟）拉取一次；
  4) UI 每次打开页面会发布 WEATHER_QUERY，可随时唤醒任务立即刷新。

容错：
  - 未定位 / 请求失败时保留上一次成功结果，不把界面打回 "--"；
  - 请求过程整体 pcall 包裹，单次异常不会终止常驻任务。

本文件没有对外接口，直接在 main.lua 中 require "weather_app" 即可加载运行。
]]

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

-- ==================== 事件名与刷新周期 ====================

local QUERY_EVENT  = "WEATHER_QUERY"     -- 立即刷新请求（UI 打开页面时发布）
local UPDATE_EVENT = "WEATHER_UPDATE"    -- 天气数据更新通知（本模块发布，UI 订阅）

local REQUEST_INTERVAL = 15 * 60 * 1000  -- 常规刷新周期：15 分钟
local REQUEST_TIMEOUT  = 15000           -- 单次 HTTP 请求超时：15 秒

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
  city        string  城市名（来自基站定位的反查地址）
  update_time string  最近一次成功更新时间（HH:MM）
  lat/lng     string  当前定位经纬度
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

--[[按 UTF-8 字符边界安全截断字符串（中文一个字占 3 字节，按字节截断会把汉字切成乱码）

@local
@function utf8_truncate
@param str string 原字符串
@param max_chars number 最大字符数
@return string 截断后的字符串
]]
local function utf8_truncate(str, max_chars)
    local count, pos, len = 0, 1, #str
    while pos <= len and count < max_chars do
        local b = str:byte(pos)
        local step = 1
        if b >= 0xF0 then step = 4
        elseif b >= 0xE0 then step = 3
        elseif b >= 0xC0 then step = 2 end
        pos = pos + step
        count = count + 1
    end
    if pos > len + 1 then pos = len + 1 end
    return str:sub(1, pos - 1)
end

--[[从定位反查地址中提取城市名（只保留城市名，不带省份）
地址可能为字符串（如「广东省深圳市南山区」）或 table（含 city/address 字段）。
处理规则：
  1) table 优先取 city，其次 cityname / district / address；均无则认为无城市信息
     （不再退回 province，避免显示「广东省」这类省份名）；
  2) 先清理空白与 ASCII 标点（部分接口用空格分隔各级行政区，如「广东省 深圳市」）；
  3) 特别行政区先单独处理（「香港特别行政区」→「香港」）；
  4) 剥离「中国」国家前缀与「省 / 自治区」前缀，再截取到「市」为止（天然去掉区县后缀）；
  5) 仍无「市」时按「字符」截断（UTF-8 安全），避免撑破标签。

@local
@function extract_city
@param addr string|table 反查地址
@return string 城市名（提取失败返回空串）
]]
local function extract_city(addr)
    local s
    if type(addr) == "table" then
        -- 兼容不同接口的字段命名
        s = addr.city or addr.cityname or addr.district or addr.address
    else
        s = addr
    end
    if type(s) ~= "string" or s == "" then return "" end

    -- 统一清理：去掉空白与 ASCII 标点（避免「广东省 深圳市」「广东-深圳」这类分隔）
    s = string.gsub(s, "[%s%p]+", "")
    if s == "" then return "" end

    -- 特别行政区：「香港特别行政区」→「香港」
    local sar = string.match(s, "^(.-)特别行政区")
    if sar and sar ~= "" then return sar end

    -- 剥离国家前缀（少数接口会以「中国」开头）
    s = string.match(s, "^中国(.+)$") or s

    -- 剥离省份 / 自治区前缀：「广东省深圳市南山区」→「深圳市南山区」
    local tail = string.match(s, "省(.+)$") or string.match(s, "自治区(.+)$")
    if tail and tail ~= "" then s = tail end

    -- 截取到「市」为止：天然去掉区县 / 街道后缀（「深圳市南山区」→「深圳市」）
    local city = string.match(s, "^([^市]+市)")
    if city and city ~= "市" then return city end

    -- 无「市」时（如仅返回「深圳」）按字符截断，避免撑破标签（UTF-8 安全，不会切坏中文）
    return utf8_truncate(s, 6)
end

-- ==================== 定位与地址订阅 ====================

--[[定位更新回调：缓存经纬度；尚未取到天气时立即唤醒任务拉取

@local
@function on_location_update
@param lat string 纬度
@param lng string 经度
]]
local function on_location_update(lat, lng)
    if lat == nil or lng == nil or lat == "" or lng == "" then return end
    local changed = (state.lat ~= lat) or (state.lng ~= lng)
    state.lat, state.lng = lat, lng
    if changed and not state.ok then
        sys.publish(QUERY_EVENT)
    end
end

--[[地址反查更新回调：缓存城市名并刷新 UI

@local
@function on_address_update
@param addr string|table 反查地址
]]
local function on_address_update(addr)
    -- 打印原始反查结果（类型 + 内容），便于现场核对地址格式与城市提取是否正常
    if type(addr) == "table" then
        log.info("weather_app", "地址反查(原始):", json.encode(addr))
    else
        log.info("weather_app", "地址反查(原始):", tostring(addr))
    end

    local city = extract_city(addr)
    log.info("weather_app", "城市提取结果:", (city ~= "") and city or "(空)")

    if city == "" or city == state.city then return end
    state.city = city
    publish_state()
end

sys.subscribe("Airlbs_LOCATION_UPDATE", on_location_update)
sys.subscribe("AIRLBS_ADDRESS_UPDATE", on_address_update)

-- ==================== 天气请求 ====================

--[[请求 Open-Meteo 天气并解析入库

@local
@function request_weather
@return boolean 是否成功
]]
local function request_weather()
    if state.lat == nil or state.lng == nil then
        log.info("weather_app", "尚未定位，跳过天气请求")
        return false
    end

    local url = "https://api.open-meteo.com/v1/forecast?latitude=" .. state.lat ..
        "&longitude=" .. state.lng ..
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
    log.info("weather_app", "天气更新:", state.text, state.temp, "℃ 湿度", state.humidity, "%")
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

    while true do
        -- 每轮无条件回推一次缓存：即使天气尚未成功（ok=false），也要把已缓存的城市名推给 UI，
        -- 否则主页打开时若天气未就绪，城市会恒显示 "--"
        publish_state()

        -- pcall 包裹：单次请求异常（DNS / TLS / 解析）不影响常驻任务
        if state.lat and state.lng then
            pcall(request_weather)
        else
            log.info("weather_app", "等待定位结果…")
        end

        -- 常规周期等待；期间收到 WEATHER_QUERY 则立即唤醒刷新
        sys.waitUntil(QUERY_EVENT, REQUEST_INTERVAL)
    end
end

sys.taskInit(weather_task)
