--[[
@module  geo
@summary 地理计算纯函数：距离、方位、墨卡托每像素米数、比例尺、格式
@version 1.0
@date    2026.10.28
@usage
全部为无副作用纯函数，输入角度均为十进制度（与地图 input_crs 一致，WGS84）。
]]

local M = {}

M.EARTH_R = 6371008.8 -- 平均地球半径（米），WGS84 等积常用值
M.MAX_LAT = 85.05112878 -- Web 墨卡托有效纬度上限

local function rad(d)
    return d * math.pi / 180
end

local function deg(r)
    return r * 180 / math.pi
end

-- 纬度收敛到墨卡托有效范围
function M.clamp_lat(lat)
    if lat > M.MAX_LAT then return M.MAX_LAT end
    if lat < -M.MAX_LAT then return -M.MAX_LAT end
    return lat
end

--[[
两点大圆距离（Haversine）
@param lon1 number 经度1
@param lat1 number 纬度1
@param lon2 number 经度2
@param lat2 number 纬度2
@return number 距离（米）
]]
function M.distance(lon1, lat1, lon2, lat2)
    local phi1, phi2 = rad(lat1), rad(lat2)
    local dphi = rad(lat2 - lat1)
    local dlam = rad(lon2 - lon1)
    local a = math.sin(dphi / 2) ^ 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ^ 2
    -- 浮点误差可能让 a 略大于 1，钳住避免 sqrt 越界
    if a > 1 then a = 1 elseif a < 0 then a = 0 end
    return 2 * M.EARTH_R * math.asin(math.sqrt(a))
end

--[[
从点1到点2的初始方位角（正北 0，顺时针 0~360）
@return number 方位角（度）
]]
function M.bearing(lon1, lat1, lon2, lat2)
    local phi1, phi2 = rad(lat1), rad(lat2)
    local dlam = rad(lon2 - lon1)
    local y = math.sin(dlam) * math.cos(phi2)
    local x = math.cos(phi1) * math.sin(phi2)
        - math.sin(phi1) * math.cos(phi2) * math.cos(dlam)
    return (deg(math.atan(y, x)) + 360) % 360
end

--[[
Web 墨卡托指定纬度、缩放层级下，屏幕一像素对应的地面米数
瓦片 256px，z 层级世界宽度 = 256*2^z
@param lat number 中心纬度
@param zoom number 缩放层级
@return number 每像素米数
]]
function M.meters_per_pixel(lat, zoom)
    lat = M.clamp_lat(lat)
    return math.cos(rad(lat)) * 2 * math.pi * M.EARTH_R / (256 * 2 ^ zoom)
end

--[[
挑一个"漂亮"的比例尺长度，使屏幕像素长度落在 40~140px
@param meters_per_pixel number 当前每像素米数
@return number bar_meters 比例尺代表的米数
@return number bar_px 比例尺屏幕像素长度
@return string  label 显示文本（米/千米）
]]
function M.nice_scale(meters_per_pixel)
    -- 目标取屏幕约 100px 对应的米数
    local target = meters_per_pixel * 100
    if target <= 0 then
        return 0, 0, "0 m"
    end
    local decade = 10 ^ math.floor(math.log(target, 10))
    local n = target / decade
    local pick
    if n < 1.5 then
        pick = 1
    elseif n < 3 then
        pick = 2
    elseif n < 7 then
        pick = 5
    else
        pick = 10
    end
    local bar_meters = pick * decade
    local bar_px = bar_meters / meters_per_pixel
    local label
    if bar_meters >= 1000 then
        label = string.format("%g km", bar_meters / 1000)
    else
        label = string.format("%g m", bar_meters)
    end
    return bar_meters, bar_px, label
end

--[[
把米数格式化成易读字符串
@param m number 米
@return string
]]
function M.fmt_distance(m)
    if m >= 1000 then
        return string.format("%.2f km", m / 1000)
    end
    return string.format("%.0f m", m)
end

--[[
把速度（米/秒）格式化成 km/h
@param mps number
@return string
]]
function M.fmt_speed(mps)
    return string.format("%.1f km/h", mps * 3.6)
end

--[[
方位角转 8 方位中文
@param brg number 0~360
@return string 如 "东北"
]]
function M.compass(brg)
    local dirs = { "北", "东北", "东", "东南", "南", "西南", "西", "西北" }
    local i = math.floor((brg / 45) + 0.5) % 8 + 1
    return dirs[i]
end

--[[
把秒数格式化成 h:mm:ss
@param sec number
@return string
]]
function M.fmt_duration(sec)
    sec = math.floor(sec + 0.5)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    return string.format("%d:%02d:%02d", h, m, s)
end

return M
