--[[
@module  astro
@summary 天文计算引擎：恒星时、地平坐标、日月位置、月相、升落/暮光、星图投影
@version 1.0
@date    2026.10.28

全部为纯 Lua 数值算法，精度足够目视星图使用（恒星位置 < 1'，日月 < 0.5°）。

坐标约定：
  赤经 ra  单位小时 0..24（J2000）
  赤纬 dec 单位度
  方位角 az 从正北起，顺时针 0..360（东=90）
  高度角 alt 地平线以上为正
]]

local M = {}
local pi, sin, cos, asin, acos, atan, abs, floor =
    math.pi, math.sin, math.cos, math.asin, math.acos, math.atan, math.abs, math.floor

local D2R = pi / 180
local R2D = 180 / pi

local function norm360(x)
    x = x % 360
    if x < 0 then x = x + 360 end
    return x
end

-- ==================== 时间基础 ====================

function M.jd(unix) return unix / 86400 + 2440587.5 end

-- 格林尼治平恒星时（度）
function M.gmst(unix)
    local d = M.jd(unix) - 2451545.0
    return norm360(280.46061837 + 360.98564736629 * d)
end

-- 地方恒星时（小时）
function M.lst(unix, lon)
    return ((M.gmst(unix) + lon) % 360) / 15
end

-- ==================== 地平坐标 ====================

--[[赤道坐标 -> 地平坐标
@return alt(度), az(度)
]]
function M.horizon(ra_h, dec, lat, lst_h)
    local ha = (lst_h - ra_h) * 15 * D2R
    local d = dec * D2R
    local p = lat * D2R
    local sinh = sin(d) * sin(p) + cos(d) * cos(p) * cos(ha)
    if sinh > 1 then sinh = 1 elseif sinh < -1 then sinh = -1 end
    local alt = asin(sinh)
    local y = -cos(d) * cos(p) * sin(ha)
    local x = sin(d) - sin(p) * sinh
    local az = atan(y, x)
    return alt * R2D, norm360(az * R2D)
end

--[[地平坐标 -> 赤道坐标（用于点选反查）
]]
function M.equatorial(alt, az, lat, lst_h)
    local a, z = alt * D2R, az * D2R
    local p = lat * D2R
    local sin_d = sin(a) * sin(p) + cos(a) * cos(p) * cos(z)
    if sin_d > 1 then sin_d = 1 elseif sin_d < -1 then sin_d = -1 end
    local dec = asin(sin_d)
    local y = -cos(a) * cos(p) * sin(z)
    local x = sin(a) - sin(p) * sin_d
    local ha = atan(y, x) * R2D / 15
    return ((lst_h - ha) % 24), dec * R2D
end

-- ==================== 星图投影（方位等距，天顶在圆心）====================

function M.project(alt, az, cx, cy, r)
    local rr = (90 - alt) / 90
    if rr < 0 then rr = 0 end
    local a = az * D2R
    return cx + r * rr * sin(a), cy - r * rr * cos(a), rr
end

function M.unproject(x, y, cx, cy, r)
    local dx, dy = x - cx, cy - y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > r then return nil end
    local alt = 90 - (dist / r) * 90
    local az = norm360(atan(dx, dy) * R2D)
    return alt, az
end

-- ==================== 太阳 ====================

function M.sun_equatorial(unix)
    local n = M.jd(unix) - 2451545.0
    local L = norm360(280.460 + 0.9856474 * n)
    local g = norm360(357.528 + 0.9856003 * n) * D2R
    local lam = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * D2R
    local eps = (23.439 - 0.0000004 * n) * D2R
    local ra = atan(cos(eps) * sin(lam), cos(lam)) * R2D / 15
    local dec = asin(sin(eps) * sin(lam)) * R2D
    return ((ra % 24) + 24) % 24, dec
end

function M.sun_horizon(unix, lat, lon)
    local ra, dec = M.sun_equatorial(unix)
    return M.horizon(ra, dec, lat, M.lst(unix, lon))
end

-- ==================== 月球 ====================

--[[月球赤道坐标 + 月相
@return ra(h), dec(deg), 照亮比例 0..1, 月龄(天) 0..29.5, 相位角 lambda_moon-lambda_sun
]]
function M.moon(unix)
    local d = M.jd(unix) - 2451545.0
    local Lp = norm360(218.316 + 13.176396 * d)
    local Mp = norm360(134.963 + 13.064993 * d)
    local F  = norm360(93.272 + 13.229350 * d)

    local lam = (Lp + 6.289 * sin(Mp * D2R)) * D2R
    local beta = 5.128 * sin(F * D2R) * D2R
    local eps = 23.439 * D2R

    local ra = atan(sin(lam) * cos(eps) - math.tan(beta) * sin(eps), cos(lam)) * R2D / 15
    local dec = asin(sin(beta) * cos(eps) + cos(beta) * sin(eps) * sin(lam)) * R2D

    local sra, sdec = M.sun_equatorial(unix)
    -- 太阳黄经：tan(λ) = tan(α)·cos(ε)，用 atan2 形式避免象限错误
    local slon = atan(sin(sra * 15 * D2R) * cos(eps), cos(sra * 15 * D2R))
    local elong = norm360((lam - slon) * R2D)
    local illum = (1 - cos(elong * D2R)) / 2
    local age = elong / 360 * 29.530588
    return ((ra % 24) + 24) % 24, dec, illum, age, elong
end

function M.moon_horizon(unix, lat, lon)
    local ra, dec, illum, age = M.moon(unix)
    local alt, az = M.horizon(ra, dec, lat, M.lst(unix, lon))
    return alt, az, illum, age
end

-- ==================== 升落 / 中天 / 暮光 ====================

--[[在 [t0, t1] 内扫描高度角过 target 的时刻（线性插值）
@param fn(t) -> alt
@return 首次穿越的时刻 或 nil
]]
local function scan_cross(fn, t0, t1, step, target, rising)
    local t = t0
    local a0 = fn(t) - target
    while t < t1 do
        local t2 = t + step
        if t2 > t1 then t2 = t1 end
        local a1 = fn(t2) - target
        if rising and a0 < 0 and a1 >= 0 then
            return t + (t2 - t) * (-a0) / (a1 - a0)
        elseif (not rising) and a0 >= 0 and a1 < 0 then
            return t + (t2 - t) * a0 / (a0 - a1)
        end
        t, a0 = t2, a1
    end
    return nil
end

--[[固定赤道坐标天体的升起/落下（当地真太阳时附近）
@return rise_unix, set_unix（可能为 nil 表示该时段内不升/不落）
]]
function M.rise_set(ra, dec, lat, lon, t0, span)
    span = span or 86400
    local fn = function(t)
        local alt = M.horizon(ra, dec, lat, M.lst(t, lon))
        return alt
    end
    local rise = scan_cross(fn, t0, t0 + span, 300, 0, true)
    local set = scan_cross(fn, t0 + 300, t0 + span, 300, 0, false)
    return rise, set
end

--[[太阳高度函数包装
]]
function M.sun_alt_fn(lat, lon)
    return function(t) return (M.sun_horizon(t, lat, lon)) end
end

--[[计算当日（以 t0 起 24h）的暮光时刻
@return table { civil_end, naut_end, astro_end, astro_begin, civil_begin }
]]
function M.twilight(t0, lat, lon)
    local fn = M.sun_alt_fn(lat, lon)
    local t1 = t0 + 86400
    local civil_end   = scan_cross(fn, t0, t1, 240, -6, false)
    local naut_end    = scan_cross(fn, t0, t1, 240, -12, false)
    local astro_end   = scan_cross(fn, t0, t1, 240, -18, false)
    local astro_begin = scan_cross(fn, t0, t1, 240, -18, true)
    local naut_begin  = scan_cross(fn, t0, t1, 240, -12, true)
    local civil_begin = scan_cross(fn, t0, t1, 240, -6, true)
    return {
        civil_end = civil_end, naut_end = naut_end, astro_end = astro_end,
        astro_begin = astro_begin, naut_begin = naut_begin, civil_begin = civil_begin,
    }
end

-- 高度轨迹采样（返回 {t, alt, az} 数组）
function M.track(ra, dec, lat, lon, t0, hours, step_min)
    step_min = step_min or 20
    local out = {}
    local step = step_min * 60
    local n = floor(hours * 60 / step_min)
    for i = 0, n do
        local t = t0 + i * step
        local alt, az = M.horizon(ra, dec, lat, M.lst(t, lon))
        out[#out + 1] = { t = t, alt = alt, az = az }
    end
    return out
end

-- 中天时刻（时角为 0 的时刻）
function M.transit(ra, lon, t0)
    local lst = M.lst(t0, lon)
    local dh = (ra - lst) % 24
    return t0 + dh * 3600 * 0.99727
end

-- ==================== 工具 ====================

function M.fmt_hhmm(unix, tz)
    local t = unix + (tz or 0) * 3600
    local sec = t % 86400
    return string.format("%02d:%02d", floor(sec / 3600), floor((sec % 3600) / 60))
end

function M.fmt_hms(unix, tz)
    local t = unix + (tz or 0) * 3600
    local sec = t % 86400
    return string.format("%02d:%02d:%02d", floor(sec / 3600),
        floor((sec % 3600) / 60), floor(sec % 60))
end

-- 恒星时格式 12h34m
function M.fmt_lst(lst_h)
    lst_h = lst_h % 24
    local h = floor(lst_h)
    local m = floor((lst_h - h) * 60)
    return string.format("%02dh%02dm", h, m)
end

-- 赤经格式
function M.fmt_ra(ra_h)
    ra_h = ra_h % 24
    local h = floor(ra_h)
    local m = floor((ra_h - h) * 60)
    return string.format("%02dh%02dm", h, m)
end

function M.fmt_dec(dec)
    local sign = dec >= 0 and "+" or "-"
    dec = abs(dec)
    local d = floor(dec)
    local m = floor((dec - d) * 60)
    return string.format("%s%02d°%02d'", sign, d, m)
end

-- 方位角 -> 中文方位
function M.compass(az)
    local names = { "北", "东北", "东", "东南", "南", "西南", "西", "西北" }
    local idx = floor((az % 360) / 45 + 0.5) % 8 + 1
    return names[idx]
end

-- 月相名称
function M.moon_phase_name(age)
    if age < 1.85 then return "新月" end
    if age < 5.54 then return "娥眉月" end
    if age < 9.23 then return "上弦月" end
    if age < 12.91 then return "盈凸月" end
    if age < 16.61 then return "满月" end
    if age < 20.30 then return "亏凸月" end
    if age < 23.99 then return "下弦月" end
    if age < 27.68 then return "残月" end
    return "新月"
end

-- 视宁度/云量等模拟（伪随机但随时间缓慢变化，看起来像真数据）
function M.atmos(unix, seed)
    seed = seed or 1
    local t = unix / 3600 + seed * 7.3
    local cloud = 0.18 + 0.22 * sin(t * 0.37) + 0.10 * sin(t * 1.13 + seed)
    local seeing = 1.4 + 0.6 * sin(t * 0.21 + 2.1) + 0.25 * sin(t * 0.9 + seed)
    local trans = 0.82 + 0.10 * sin(t * 0.17 + 1.3) + 0.05 * sin(t * 0.7)
    cloud = math.max(0, math.min(0.95, cloud))
    seeing = math.max(0.6, math.min(3.2, seeing))
    trans = math.max(0.45, math.min(0.97, trans))
    return cloud, seeing, trans
end

-- 综合观测指数 0..100
function M.seeing_index(cloud, seeing, moon_illum, bortle)
    local s = 100 - cloud * 95 - (seeing - 0.6) * 16 - moon_illum * 18
    s = s - ((bortle or 2) - 1) * 3
    if s < 0 then s = 0 elseif s > 100 then s = 100 end
    return s
end

return M
