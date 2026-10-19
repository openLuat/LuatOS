-- 地图瓦片坐标转换模块
-- 适用于高德地图瓦片服务
-- 作者: 基于标准算法移植
-- 版本: 1.0
-- 注意: 本模块包含三角函数运算，计算复杂度较高，建议缓存结果

local mapTile = {}

-- 常量定义
local PI = 3.14159265358979323846
local EARTH_RADIUS = 6378245.0
local EE = 0.00669342162296594323

-- 辅助函数：角度转弧度
local function rad(d)
    return d * PI / 180.0
end

-- 辅助函数：将经度转换为瓦片X坐标
local function lon2tile(lon, zoom)
    return math.floor((lon + 180.0) / 360.0 * (2 ^ zoom))
end

-- 辅助函数：将纬度转换为瓦片Y坐标
local function lat2tile(lat, zoom)
    local lat_rad = rad(lat)
    local n = 2 ^ zoom
    local y = (1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / PI) / 2.0 * n
    return math.floor(y)
end

-- 转换纬度辅助函数
local function transformLat(x, y)
    local ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(math.abs(x))
    ret = ret + (20.0 * math.sin(6.0 * x * PI) + 20.0 * math.sin(2.0 * x * PI)) * 2.0 / 3.0
    ret = ret + (20.0 * math.sin(y * PI) + 40.0 * math.sin(y / 3.0 * PI)) * 2.0 / 3.0
    ret = ret + (160.0 * math.sin(y / 12.0 * PI) + 320.0 * math.sin(y * PI / 30.0)) * 2.0 / 3.0
    return ret
end

-- 转换经度辅助函数
local function transformLon(x, y)
    local ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(math.abs(x))
    ret = ret + (20.0 * math.sin(6.0 * x * PI) + 20.0 * math.sin(2.0 * x * PI)) * 2.0 / 3.0
    ret = ret + (20.0 * math.sin(x * PI) + 40.0 * math.sin(x / 3.0 * PI)) * 2.0 / 3.0
    ret = ret + (150.0 * math.sin(x / 12.0 * PI) + 300.0 * math.sin(x / 30.0 * PI)) * 2.0 / 3.0
    return ret
end

-- WGS84 转 GCJ02（火星坐标系）
function mapTile.wgs84_to_gcj02(lon, lat)
    if lon < 72.004 or lon > 137.8347 or lat < 0.8293 or lat > 55.8271 then
        return lon, lat
    end
    
    local dLat = transformLat(lon - 105.0, lat - 35.0)
    local dLon = transformLon(lon - 105.0, lat - 35.0)
    
    local radLat = rad(lat)
    local magic = math.sin(radLat)
    magic = 1 - EE * magic * magic
    
    local sqrtMagic = math.sqrt(magic)
    dLat = (dLat * 180.0) / ((EARTH_RADIUS * (1 - EE)) / (magic * sqrtMagic) * PI)
    dLon = (dLon * 180.0) / (EARTH_RADIUS / sqrtMagic * math.cos(radLat) * PI)
    
    local mgLat = lat + dLat
    local mgLon = lon + dLon
    
    return mgLon, mgLat
end

-- GCJ02 转高德瓦片坐标
-- 注意: 高德地图在标准计算基础上，x值通常需要-1的偏移
-- offset_x: 额外的x偏移量（根据实际情况调整，默认为-1）
function mapTile.gcj02_to_gaode_tile(lon, lat, zoom, offset_x)
    offset_x = offset_x or -1  -- 高德地图常见的x偏移
    
    local x = lon2tile(lon, zoom) + offset_x
    local y = lat2tile(lat, zoom)
    
    -- 确保坐标不超出范围
    local max_tile = 2 ^ zoom - 1
    x = math.max(0, math.min(x, max_tile))
    y = math.max(0, math.min(y, max_tile))
    
    return x, y
end

-- 一键转换：WGS84 直接转高德瓦片坐标
function mapTile.wgs84_to_gaode_tile(lon, lat, zoom, offset_x)
    local gcj_lon, gcj_lat = mapTile.wgs84_to_gcj02(lon, lat)
    return mapTile.gcj02_to_gaode_tile(gcj_lon, gcj_lat, zoom, offset_x)
end

-- 生成高德地图瓦片URL
function mapTile.generate_gaode_url(lon, lat, zoom, offset_x)
    local x, y = mapTile.wgs84_to_gaode_tile(lon, lat, zoom, offset_x)
    
    local url = string.format(
        "http://webrd01.is.autonavi.com/appmaptile?x=%d&y=%d&z=%d&lang=zh_cn&size=1&scale=2&style=8",
        x, y, zoom
    )
    
    return url, x, y
end

-- 示例：计算特定坐标的瓦片
function mapTile.example()
    -- 您的坐标
    local wgs84_lon = 114.329065
    local wgs84_lat = 34.795241
    
    -- 测试不同缩放级别
    local zoom_levels = {10, 16, 18}
    
    log.info("mapTile", "=== 坐标转换示例 ===")
    log.info("mapTile", string.format("原始坐标: %.6f, %.6f", wgs84_lon, wgs84_lat))
    
    -- 转换为GCJ02
    local gcj_lon, gcj_lat = mapTile.wgs84_to_gcj02(wgs84_lon, wgs84_lat)
    log.info("mapTile", string.format("GCJ02坐标: %.6f, %.6f", gcj_lon, gcj_lat))
    
    -- 计算各缩放级别的瓦片坐标
    for _, z in ipairs(zoom_levels) do
        local x, y = mapTile.wgs84_to_gaode_tile(wgs84_lon, wgs84_lat, z)
        local url = mapTile.generate_gaode_url(wgs84_lon, wgs84_lat, z)
        
        log.info("mapTile", string.format("z=%d: x=%d, y=%d", z, x, y))
        log.info("mapTile", string.format("URL: %s", url))
    end
    
    -- 特别测试您的调试结果
    log.info("mapTile", "=== 您的调试结果验证 ===")
    local x, y = mapTile.wgs84_to_gaode_tile(wgs84_lon, wgs84_lat, 18, -4)  -- 使用您的偏移量-4
    log.info("mapTile", string.format("z=18 with offset -4: x=%d, y=%d", x, y))
    
    if x == 214327 and y == 104017 then
        log.info("mapTile", "✓ 与您的调试结果匹配！")
    else
        log.info("mapTile", "✗ 与您的调试结果不匹配，请调整偏移量")
    end
end

-- 批量计算多个点的瓦片坐标
function mapTile.batch_calculate(points, zoom)
    local results = {}
    
    for i, point in ipairs(points) do
        local x, y = mapTile.wgs84_to_gaode_tile(point.lon, point.lat, zoom)
        results[i] = {
            index = i,
            lon = point.lon,
            lat = point.lat,
            zoom = zoom,
            x = x,
            y = y,
            url = string.format(
                "http://webrd01.is.autonavi.com/appmaptile?x=%d&y=%d&z=%d&lang=zh_cn&size=1&scale=2&style=8",
                x, y, zoom
            )
        }
    end
    
    return results
end

-- 缓存机制：避免重复计算
local tile_cache = {}
function mapTile.get_cached_tile(lon, lat, zoom, offset_x)
    local key = string.format("%.6f_%.6f_%d_%d", lon, lat, zoom, offset_x or -1)
    
    if tile_cache[key] then
        return tile_cache[key].x, tile_cache[key].y, true  -- 第三个参数表示来自缓存
    end
    
    local x, y = mapTile.wgs84_to_gaode_tile(lon, lat, zoom, offset_x)
    tile_cache[key] = {x = x, y = y}
    
    return x, y, false
end

-- 清理缓存
function mapTile.clear_cache()
    tile_cache = {}
    log.info("mapTile", "瓦片坐标缓存已清空")
end

return mapTile