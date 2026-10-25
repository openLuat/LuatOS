--[[
@module  weather_app
@summary 天气服务：按当前网络出口 IP 自动定位城市，查询实况与 3 天预报，发布 WEATHER_UPDATED
@version 1.0
@date    2026.09.17

=== 解决的问题 ===
此前 ui/idle_win.lua 的天气卡是写死的占位数据（"上海 / 晴 / 26℃"）。
本模块把它接到真实数据源：**无需用户配置**，开机联网后自动按出口 IP 定位城市并取天气。

=== 核心逻辑 ===
1. 等待网络就绪：先查 socket.localIP()，再 sys.waitUntil("IP_READY")
   （IP_READY 是即时事件，错过就没了；先查当前状态可避免永久等待）
2. 定位：多个免 key 源依次尝试，任一成功即用 —— 单源网络抖动不影响整体可用性

     源                协议   给出的内容                 备注
     ip-api.com        http   中文城市名 + 经纬度        一次到位，首选
     api.vore.top      https  中文城市名（info1）       国内源，无坐标
     ipinfo.io         https  经纬度（城市名英文）       无中文名
     api.ip.sb         https  经纬度（城市名英文）       无中文名

3. 补齐：若上面没给经纬度、或城市名是英文 -> open-meteo geocoding（language=zh）
   它同时返回 **中文城市名 + 经纬度**，一举两得
4. 天气：open-meteo forecast（免 key、按经纬度查、返回结构规整）
5. 映射 WMO weather_code -> 本工程天气卡的 5 类图标语义：晴 / 多云 / 阴 / 雨 / 雪
6. 发布 WEATHER_UPDATED 并写 fskv 缓存；下次开机先把缓存发出去，断网也不会留一张空卡

=== 消息协议（订阅 / 发布）===
订阅: WEATHER_REQUEST        → 应答式：立即把当前数据回发一次
                                ui/idle_win.lua 建窗时调用。天气数据可能在窗口订阅之前
                                就已到达（订阅晚于发布 = 丢首帧），用请求-应答消除该时序竞态。
发布: WEATHER_UPDATED(data)  → 天气整卡刷新
                                data = { city = string, condition = string, temp = number,
                                         daily = { {day=,high=,low=}, ... } }
                                字段契约见 ui/idle_win.lua 的 on_weather_updated

=== 数据源说明 ===
全部免 key、免注册、免证书配置（优先走 http，省掉 TLS 开销）。
换数据源只需改本文件顶部的 IP_SOURCES / GEO_URL / WX_URL 三处常量。
]]

-- fskv 缓存键（小写下划线，与工程既有键名风格一致）
local FSKV_CITY = "weather_city"
local FSKV_DATA = "weather_cache"

-- ==================== 可配置常量（换数据源只改这一段） ====================

--- IP 定位源，按顺序尝试，首个成功即用
local IP_SOURCES = {
    { name = "ip-api", kind = "ipapi",
      url = "http://ip-api.com/json/?lang=zh-CN&fields=status,country,regionName,city,lat,lon" },
    { name = "vore",   kind = "vore",
      url = "https://api.vore.top/api/IPdata" },
    { name = "ipinfo", kind = "ipinfo",
      url = "https://ipinfo.io/json" },
    { name = "ipsb",   kind = "ipsb",
      url = "https://api.ip.sb/geoip" },
}

--- 城市名 -> 经纬度（同时把英文城市名转成中文）
local GEO_URL = "http://geocoding-api.open-meteo.com/v1/search?name=%s&count=1&language=zh&format=json"

--- 天气（按经纬度查实况 + 未来 4 天，取后 3 天做预报）
local WX_URL = table.concat({
    "http://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f",
    "&current=temperature_2m,weather_code",
    "&daily=weather_code,temperature_2m_max,temperature_2m_min",
    "&timezone=auto&forecast_days=4",
})

--- 部分服务对无 UA 的请求会返回空 200，统一带上
local HTTP_HEADERS = { ["User-Agent"] = "LuatOS-Weather/1.0" }

local T_IP_MS      = 8000        -- 定位请求超时
local T_GEO_MS     = 8000        -- geocoding 超时
local T_WX_MS      = 10000       -- 天气请求超时

local REFRESH_OK_MS = 30 * 60 * 1000   -- 成功后刷新间隔：30 分钟
local RETRY_MIN_MS  = 60 * 1000        -- 失败首次退避：1 分钟
local RETRY_MAX_MS  = 10 * 60 * 1000   -- 失败退避上限：10 分钟

-- ==================== 工具函数 ====================

--- UTF-8 百分号编码（按中文城市名查 geocoding 时需要）
--- gsub 的替换函数按**字节**回调，多字节字符会被逐字节编码 —— 正是 URL 编码要的语义
local function url_encode(s)
    return (tostring(s or ""):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

--- 是否含非 ASCII 字符（UTF-8 多字节首字节 >= 0xC2）
--- 用 string.char 拼字节范围，避免依赖各 Lua 版本对 \ddd 转义的解析差异
local function has_multibyte(s)
    if type(s) ~= "string" or s == "" then return false end
    return s:find("[" .. string.char(0xC2) .. "-" .. string.char(0xF4) .. "]") ~= nil
end

--- WMO weather_code -> 本工程 5 类图标语义
--- 对照表：https://open-meteo.com/en/docs （WMO Weather interpretation codes）
local function wmo_to_condition(code)
    code = tonumber(code)
    if not code then return nil end
    if code == 0 then return "晴" end
    if code == 1 or code == 2 then return "多云" end
    if code == 3 then return "阴" end
    if code == 45 or code == 48 then return "阴" end      -- 雾 -> 阴
    if code >= 51 and code <= 57 then return "雨" end      -- 毛毛雨 / 冻雨
    if code >= 61 and code <= 67 then return "雨" end      -- 雨
    if code >= 71 and code <= 77 then return "雪" end      -- 降雪 / 雪粒
    if code >= 80 and code <= 82 then return "雨" end      -- 阵雨
    if code >= 85 and code <= 86 then return "雪" end      -- 阵雪
    if code >= 95 then return "雨" end                     -- 雷暴 / 冰雹
    return "多云"
end

--- 统一的 GET + JSON 解析；失败一律返回 nil（调用方只判空，不再各自处理错误码）
local function http_get_json(url, timeout_ms)
    local ok, code, body = pcall(function()
        local c, _, b = http.request("GET", url, HTTP_HEADERS, nil, { timeout = timeout_ms }).wait()
        return c, b
    end)
    if not ok then
        log.warn("weather", "请求异常:", tostring(code))
        return nil
    end
    if type(code) ~= "number" or code ~= 200 then
        log.warn("weather", "HTTP 状态非 200:", tostring(code))
        return nil
    end
    if type(body) ~= "string" or #body == 0 then
        log.warn("weather", "响应体为空")
        return nil
    end
    local pok, t = pcall(json.decode, body)
    if not pok or type(t) ~= "table" then
        log.warn("weather", "响应不是合法 JSON")
        return nil
    end
    return t
end

-- ==================== 三步取数 ====================

--- ① 各源响应 -> 统一 { city, lat, lon }（缺的字段留 nil，由 geocoding 补）
local function parse_ip_payload(kind, t)
    if kind == "ipapi" then
        if t.status ~= "success" then return nil end
        return { city = t.city or t.regionName, lat = tonumber(t.lat), lon = tonumber(t.lon) }

    elseif kind == "vore" then
        local d = t.ipdata
        if type(d) ~= "table" then return nil end
        -- 实测字段语义：info1 = 城市（"上海市"）、info2 = 区（"浦东区"）、info3 = 空
        return { city = d.info1 or d.info2, lat = nil, lon = nil }

    elseif kind == "ipinfo" then
        local lat, lon
        if type(t.loc) == "string" then
            lat, lon = t.loc:match("^(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*)$")
        end
        return { city = t.city, lat = tonumber(lat), lon = tonumber(lon) }

    elseif kind == "ipsb" then
        return { city = t.city, lat = tonumber(t.latitude), lon = tonumber(t.longitude) }
    end
    return nil
end

--- ② 定位：多源依次尝试
local function locate()
    for _, src in ipairs(IP_SOURCES) do
        local t = http_get_json(src.url, T_IP_MS)
        if t then
            local loc = parse_ip_payload(src.kind, t)
            if loc and (loc.city or (loc.lat and loc.lon)) then
                log.info("weather", "定位成功", src.name, loc.city or "?",
                    loc.lat and string.format("%.3f", loc.lat) or "-",
                    loc.lon and string.format("%.3f", loc.lon) or "-")
                return loc
            end
        end
        log.warn("weather", "定位源失败，继续下一个:", src.name)
    end
    return nil
end

--- ③ 城市名 -> 坐标 / 中文名
local function geocode(name)
    if type(name) ~= "string" or name == "" then return nil end
    local t = http_get_json(string.format(GEO_URL, url_encode(name)), T_GEO_MS)
    if not t or type(t.results) ~= "table" then return nil end
    local r = t.results[1]
    if type(r) ~= "table" then return nil end
    local lat, lon = tonumber(r.latitude), tonumber(r.longitude)
    if not lat or not lon then return nil end
    return { city = r.name, lat = lat, lon = lon }
end

--- ④ 天气：按经纬度取实况 + 未来 3 天预报
local function fetch_weather(lat, lon)
    local t = http_get_json(string.format(WX_URL, lat, lon), T_WX_MS)
    if not t then return nil end

    local cur, daily = t.current, t.daily
    if type(cur) ~= "table" or type(daily) ~= "table" then return nil end

    local temp = tonumber(cur.temperature_2m)
    local cond = wmo_to_condition(cur.weather_code)
    if not temp or not cond then return nil end

    -- daily.time[1] 是今天，[2..4] 依次是明天 / 后天 / 大后天
    local titles = { "明天", "后天", "大后天" }
    local out_daily = {}
    local highs, lows = daily.temperature_2m_max, daily.temperature_2m_min
    for i = 1, 3 do
        local hi = type(highs) == "table" and tonumber(highs[i + 1])
        local lo = type(lows) == "table" and tonumber(lows[i + 1])
        if hi and lo then
            out_daily[#out_daily + 1] = {
                day  = titles[i],
                high = math.floor(hi + 0.5),
                low  = math.floor(lo + 0.5),
            }
        end
    end

    return {
        condition = cond,
        temp = math.floor(temp + 0.5),
        daily = out_daily,
    }
end

-- ==================== 缓存 ====================

local function save_cache(data)
    pcall(fskv.set, FSKV_CITY, data.city or "")
    pcall(fskv.set, FSKV_DATA, json.encode({
        condition = data.condition,
        temp      = data.temp,
        daily     = data.daily,
    }))
end

local function load_cache()
    local ok1, city = pcall(fskv.get, FSKV_CITY)
    local ok2, s = pcall(fskv.get, FSKV_DATA)
    if not ok2 or type(s) ~= "string" or s == "" then return nil end
    local pok, d = pcall(json.decode, s)
    if not pok or type(d) ~= "table" then return nil end
    if ok1 and type(city) == "string" and city ~= "" then d.city = city end
    return d
end

-- ==================== 主流程 ====================

local latest = nil   -- 最近一次可用数据（含缓存），供 WEATHER_REQUEST 应答

local function push(data)
    latest = data
    sys.publish("WEATHER_UPDATED", data)
end

--- 跑一轮完整取数：定位 -> 补坐标 -> 取天气 -> 发布 + 缓存
--- @return boolean 成功与否
local function refresh_once()
    local loc = locate()
    if not loc then
        log.warn("weather", "所有定位源均失败")
        return false
    end

    -- 没坐标、或城市名不是中文 -> 用 geocoding 补齐（顺便把英文名转中文）
    if not loc.lat or not loc.lon or not has_multibyte(loc.city) then
        local g = geocode(loc.city)
        if g then
            if has_multibyte(g.city) then loc.city = g.city end
            loc.lat, loc.lon = g.lat, g.lon
        end
    end
    if not loc.lat or not loc.lon then
        log.warn("weather", "无可用经纬度，跳过本轮")
        return false
    end

    local wx = fetch_weather(loc.lat, loc.lon)
    if not wx then
        log.warn("weather", "天气查询失败")
        return false
    end

    -- 城市名兜底：本轮没拿到就沿用上一次的，避免天气卡城市变空
    wx.city = loc.city or (latest and latest.city) or ""
    if wx.city == "" then
        local c = load_cache()
        wx.city = (c and c.city) or ""
    end

    push(wx)
    save_cache(wx)
    log.info("weather", "更新完成", wx.city, wx.condition, wx.temp .. "℃")
    return true
end

local function weather_task()
    pcall(fskv.init)

    -- 开机先把上次缓存发出去：断网/慢网时天气卡也不会停在写死的占位数据上
    local cached = load_cache()
    if cached then
        push(cached)
        log.info("weather", "已加载缓存", cached.city or "?", cached.condition or "-")
    end

    local retry_wait = RETRY_MIN_MS
    while true do
        -- IP_READY 是即时事件（错过就没有），所以先用 socket.localIP() 判当前状态
        if not socket.localIP() then
            log.info("weather", "等待网络就绪...")
            sys.waitUntil("IP_READY", 60000)
        end

        if socket.localIP() then
            if refresh_once() then
                retry_wait = RETRY_MIN_MS
                sys.wait(REFRESH_OK_MS)
            else
                log.warn("weather", "刷新失败，", math.floor(retry_wait / 1000), "秒后重试")
                sys.wait(retry_wait)
                retry_wait = math.min(retry_wait * 2, RETRY_MAX_MS)
            end
        else
            -- 等待超时仍无网络：按成功间隔再来一轮，避免空转刷日志
            sys.wait(REFRESH_OK_MS)
        end
    end
end

-- 应答式取数：窗口建好后主动来要一次（消除「发布早于订阅」的时序竞态）
sys.subscribe("WEATHER_REQUEST", function()
    if latest then sys.publish("WEATHER_UPDATED", latest) end
end)

sys.taskInit(weather_task)

-- 供调试 / 其他模块读取
local M = {}
function M.current() return latest end
return M
