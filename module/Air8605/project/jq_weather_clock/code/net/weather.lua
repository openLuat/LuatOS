--[[
@module  weather
@summary 天气服务：IP 定位 → 实况 + 未来 7 天预报，发布 WEATHER_UPDATED
@version 1.0
@date    2026.11.08

=== 数据链路（全部免 key）===
1. 定位：ip-api / vore / ipinfo / ip.sb 依次尝试，任一成功即用
2. 补坐标：没经纬度、或城市名是英文 → open-meteo geocoding（language=zh）
3. 天气：open-meteo forecast，一次取「今天 + 未来 7 天」
4. 发布 WEATHER_UPDATED → ui_main 刷 HUD / 预报页 / 天气特效（雨雪）

=== 离线兜底 ===
开机立刻发一份 conf.weather.fallback（西安 / 晴 / 1~10℃），
联网成功后整体替换，断网时界面也不会空着。

=== 消息 ===
订阅 WEATHER_REQUEST       → 立即重发一次当前数据（订阅晚于发布的时序竞态）
发布 WEATHER_UPDATED(data) → { city, condition, temp, temp_min, temp_max, daily[1..7], demo }
                              daily[i] = { wd = "周一", date = "11/09", cond = "晴", high = 10, low = 1 }
]]

local conf = require "conf"

local M = {}

-- ==================== 可配置常量 ====================
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
--[[国内 IP 定位（纯文本接口）
上面几个源对国内 4G 出口 IP 的城市粒度都偏粗（经常只到省会），
ipip.net 在国内的 IP 库上明显更准，所以排在最前面试。]]
local IPIP_URL = "https://myip.ipip.net"

local GEO_URL = "http://geocoding-api.open-meteo.com/v1/search?name=%s&count=1&language=zh&format=json"
local WX_URL = table.concat({
    "http://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f",
    "&current=temperature_2m,weather_code",
    "&daily=weather_code,temperature_2m_max,temperature_2m_min",
    "&timezone=auto&forecast_days=" .. tostring(conf.weather.forecast_days),
})
local HTTP_HEADERS = { ["User-Agent"] = "LuatOS-WeatherClock/1.0" }

local T_IP_MS, T_GEO_MS, T_WX_MS = 8000, 8000, 10000

local WD = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }

-- ==================== 工具 ====================

local function url_encode(s)
    return (tostring(s or ""):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function has_multibyte(s)
    if type(s) ~= "string" or s == "" then return false end
    return s:find("[" .. string.char(0xC2) .. "-" .. string.char(0xF4) .. "]") ~= nil
end

--[[公历星期（0=周日）。不依赖 os.time：设备时钟没校准时 os.time 也是错的，
-- 而 daily.time 是数据源给的绝对日期，直接按日期算最稳。]]
local function weekday_of(y, m, d)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if m < 3 then y = y - 1 end
    return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7
end

local function wmo_to_condition(code)
    code = tonumber(code)
    if not code then return nil end
    if code == 0 then return "晴" end
    if code == 1 or code == 2 then return "多云" end
    if code == 3 then return "阴" end
    if code == 45 or code == 48 then return "阴" end
    if code >= 51 and code <= 67 then return "雨" end
    if code >= 71 and code <= 77 then return "雪" end
    if code >= 80 and code <= 82 then return "雨" end
    if code >= 85 and code <= 86 then return "雪" end
    if code >= 95 then return "雨" end
    return "多云"
end

local function http_get_json(url, timeout_ms)
    local ok, code, body = pcall(function()
        local c, _, b = http.request("GET", url, HTTP_HEADERS, nil, { timeout = timeout_ms }).wait()
        return c, b
    end)
    if not ok or type(code) ~= "number" or code ~= 200 then
        log.warn("weather", "请求失败", tostring(code))
        return nil
    end
    if type(body) ~= "string" or #body == 0 then return nil end
    local pok, t = pcall(json.decode, body)
    if not pok or type(t) ~= "table" then return nil end
    return t
end

-- ==================== 离线兜底数据 ====================
local function build_demo()
    local fb = conf.weather.fallback
    local daily = {}
    local now = os.time()
    local day0 = (os.date("*t", now) or {})
    local valid_clock = (day0.year or 1970) >= 2020

    for i = 1, 7 do
        local src = fb.daily[i] or { cond = "多云", high = 10, low = 2 }
        local d = { cond = src.cond, high = src.high, low = src.low, wd = src.wd, date = src.date }
        if valid_clock then
            local t = os.date("*t", now + i * 86400)
            if t and t.month and t.day then
                d.wd = WD[(t.wday or 1)] or d.wd
                d.date = string.format("%02d/%02d", t.month, t.day)
            end
        end
        daily[i] = d
    end

    return {
        city = fb.city, condition = fb.condition, temp = fb.temp,
        temp_min = fb.temp_min, temp_max = fb.temp_max,
        daily = daily, demo = true,
    }
end

-- ==================== 取数 ====================
local function parse_ip_payload(kind, t)
    if kind == "ipapi" then
        if t.status ~= "success" then return nil end
        return { city = t.city or t.regionName, lat = tonumber(t.lat), lon = tonumber(t.lon) }
    elseif kind == "vore" then
        local d = t.ipdata
        if type(d) ~= "table" then return nil end
        return { city = d.info1 or d.info2 }
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

local function geocode(name)
    if type(name) ~= "string" or name == "" then return nil end
    local t = http_get_json(string.format(GEO_URL, url_encode(name)), T_GEO_MS)
    if not t or type(t.results) ~= "table" or type(t.results[1]) ~= "table" then return nil end
    local r = t.results[1]
    local lat, lon = tonumber(r.latitude), tonumber(r.longitude)
    if not lat or not lon then return nil end
    return { city = r.name, lat = lat, lon = lon }
end

--[[ipip.net 的返回是一行文本：
「当前 IP：1.2.3.4  来自于：中国 陕西 西安  电信」
只给城市名、没有经纬度，坐标交给 geocode 补。末尾可能带运营商名，要先摘掉。]]
local function locate_ipip()
    local ok, code, body = pcall(function()
        local c, _, b = http.request("GET", IPIP_URL, HTTP_HEADERS, nil, { timeout = T_IP_MS }).wait()
        return c, b
    end)
    if not ok or type(code) ~= "number" or code ~= 200 or type(body) ~= "string" then
        return nil
    end
    local area = body:match("来自于[:：]%s*([^\r\n]+)")
    if not area then return nil end

    local words = {}
    for w in area:gmatch("%S+") do words[#words + 1] = w end
    local ISP = { ["电信"] = 1, ["移动"] = 1, ["联通"] = 1, ["铁通"] = 1, ["广电"] = 1, ["教育网"] = 1 }
    while #words > 1 and ISP[words[#words]] do words[#words] = nil end

    local city = words[#words]
    if not city or city == "" or city == "中国" then return nil end
    return city
end

local function locate()
    --[[0. 配置里写死了城市：直接用，完全不看出口 IP
    这是唯一能保证"人在哪就显示哪"的办法 —— IP 定位只能定位到出口机房。]]
    local fixed = conf.weather.city
    if type(fixed) == "string" and fixed ~= "" then
        local g = geocode(fixed)
        if g then
            g.city = fixed
            log.info("weather", "使用配置的城市", fixed, string.format("%.3f,%.3f", g.lat, g.lon))
            return g
        end
        log.warn("weather", "配置的城市查不到坐标，退回 IP 定位:", fixed)
    end

    -- 1. 国内源优先
    local ipip = locate_ipip()
    if ipip then
        log.info("weather", "定位成功 ipip", ipip)
        return { city = ipip }
    end
    log.warn("weather", "定位源失败，继续下一个: ipip")

    -- 2. 其余免 key 源依次尝试
    for _, src in ipairs(IP_SOURCES) do
        local t = http_get_json(src.url, T_IP_MS)
        local loc = t and parse_ip_payload(src.kind, t)
        if loc and (loc.city or (loc.lat and loc.lon)) then
            log.info("weather", "定位成功", src.name, loc.city or "?",
                loc.lat and string.format("%.3f", loc.lat) or "-",
                loc.lon and string.format("%.3f", loc.lon) or "-")
            return loc
        end
        log.warn("weather", "定位源失败，继续下一个:", src.name)
    end
    return nil
end

local function fetch_weather(lat, lon)
    -- 经纬度必须是数字：WX_URL 里的 %.4f 收到 nil 会抛错，
    -- taskInit 里的异常会直接把整个 Lua VM 带崩（日志表现为 reboot in 15000ms）
    lat, lon = tonumber(lat), tonumber(lon)
    if not lat or not lon then
        log.warn("weather", "经纬度无效，跳过天气查询")
        return nil
    end
    local t = http_get_json(string.format(WX_URL, lat, lon), T_WX_MS)
    if not t then return nil end
    local cur, daily = t.current, t.daily
    if type(cur) ~= "table" or type(daily) ~= "table" then return nil end

    local temp, cond = tonumber(cur.temperature_2m), wmo_to_condition(cur.weather_code)
    if not temp or not cond then return nil end

    local highs, lows, codes, times = daily.temperature_2m_max, daily.temperature_2m_min,
        daily.weather_code, daily.time
    local out = {}
    for i = 2, 8 do
        local hi = type(highs) == "table" and tonumber(highs[i])
        local lo = type(lows) == "table" and tonumber(lows[i])
        if hi and lo then
            local d = { high = math.floor(hi + 0.5), low = math.floor(lo + 0.5) }
            d.cond = (type(codes) == "table" and wmo_to_condition(codes[i])) or "多云"
            local iso = type(times) == "table" and times[i]
            -- 三个捕获必须都在才格式化：and 链一旦中途为 false，解构出来的是
            -- (false, nil, nil)，只判 y 不足以保证 m/dd 是数字
            local yy, mm, dd = nil, nil, nil
            if type(iso) == "string" then
                yy, mm, dd = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
            end
            if yy and mm and dd then
                d.date = string.format("%02d/%02d", tonumber(mm), tonumber(dd))
                d.wd = WD[weekday_of(tonumber(yy), tonumber(mm), tonumber(dd)) + 1] or "--"
            else
                d.date, d.wd = "--", "--"
            end
            out[#out + 1] = d
        end
    end

    local hi_today = type(highs) == "table" and tonumber(highs[1])
    local lo_today = type(lows) == "table" and tonumber(lows[1])

    return {
        condition = cond,
        temp = math.floor(temp + 0.5),
        temp_min = lo_today and math.floor(lo_today + 0.5) or nil,
        temp_max = hi_today and math.floor(hi_today + 0.5) or nil,
        daily = out,
        demo = false,
    }
end

-- ==================== 缓存 / 发布 ====================
local FSKV_KEY = "wc_weather"
local latest = nil

local function push(data)
    latest = data
    sys.publish("WEATHER_UPDATED", data)
end

local function save_cache(d)
    pcall(fskv.set, FSKV_KEY, json.encode({
        city = d.city, condition = d.condition, temp = d.temp,
        temp_min = d.temp_min, temp_max = d.temp_max, daily = d.daily,
    }))
end

local function load_cache()
    local ok, s = pcall(fskv.get, FSKV_KEY)
    if not ok or type(s) ~= "string" or s == "" then return nil end
    local pok, d = pcall(json.decode, s)
    if not pok or type(d) ~= "table" or type(d.daily) ~= "table" then return nil end
    d.demo = false
    return d
end

local function refresh_once()
    local loc = locate()
    if not loc then
        log.warn("weather", "所有定位源均失败")
        return false
    end

    if not loc.lat or not loc.lon or not has_multibyte(loc.city) then
        local g = geocode(loc.city)
        if g then
            if has_multibyte(g.city) then loc.city = g.city end
            loc.lat, loc.lon = g.lat, g.lon
        end
    end
    if not loc.lat or not loc.lon then
        log.warn("weather", "无可用经纬度")
        return false
    end

    local wx = fetch_weather(loc.lat, loc.lon)
    if not wx then
        log.warn("weather", "天气查询失败")
        return false
    end

    local old_city = latest and latest.city
    wx.city = loc.city or old_city or conf.weather.fallback.city
    push(wx)
    -- 城市和上次不一样要留痕：定位到别的城市时，日志是唯一能查的线索
    if old_city and old_city ~= wx.city then
        log.warn("weather", "城市已变化", old_city, "->", wx.city)
    end
    save_cache(wx)
    log.info("weather", "更新完成", wx.city, wx.condition, wx.temp .. "C",
        "预报条数", tostring(#wx.daily))
    return true
end

--- 默认网卡是否已拿到可用 IP
--- socket.localIP() 在网卡未就绪时可能返回 "0.0.0.0" 而不是 nil，
--- 只判 nil 会直接进刷新分支，白等 8 秒超时（日志里的 -8 就是这么来的）
local function has_ip()
    local ip = socket.localIP()
    return type(ip) == "string" and ip ~= "" and ip ~= "0.0.0.0"
end

local function weather_task()
    pcall(fskv.init)

    -- 先发离线数据：首屏立刻有内容，联网后再整体替换
    local cached = load_cache()
    if cached then
        push(cached)
    else
        push(build_demo())
    end

    local wait = conf.weather.retry_min_ms
    while true do
        if not has_ip() then
            sys.waitUntil("IP_READY", 60000)
        end

        if has_ip() then
            -- refresh_once 里任何解析异常都会顺着 taskInit 协程把整个 Lua VM 带崩
            -- （日志 Lua VM exit!! reboot in 15000ms），单次刷新失败只该退避重试
            local ok, ret = pcall(refresh_once)
            if not ok then
                log.error("weather", "刷新异常", tostring(ret))
            end
            if ok and ret then
                wait = conf.weather.retry_min_ms
                sys.wait(conf.weather.refresh_ms)
            else
                sys.wait(wait)
                wait = math.min(wait * 2, conf.weather.retry_max_ms)
            end
        else
            sys.wait(conf.weather.refresh_ms)
        end
    end
end

sys.subscribe("WEATHER_REQUEST", function()
    if latest then sys.publish("WEATHER_UPDATED", latest) end
end)

sys.taskInit(weather_task)

--- 最近一次数据（调试用）
function M.current() return latest end

return M
