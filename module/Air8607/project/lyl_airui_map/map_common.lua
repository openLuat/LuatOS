--[[
@module  map_common
@summary Air8607 真机地图：SD 瓦片路径、视口和坐标读取
@version 1.0
@date    2026.10.28
@usage
交互和自检共用。瓦片目录与下载脚本一致：/sd/tiles/{z}/{x}/{y}.jpg。
输入坐标是 WGS84，瓦片是 GCJ02。中心点是开封市区 114.312376,34.801142（WGS84），
对应 map_tiles/tiles 里的高德矢量瓦片（z14–z17，JPEG，8804 张）。
]]

local M = {}

-- 瓦片几何中心反算 GCJ02=114.318237,34.800272，转 WGS84 后作为回家点
M.home = { lon = 114.312376, lat = 34.801142 }
M.tiles_root = "/sd/tiles"
-- z15 下该几何中心落在这张瓦片上，用来确认卡里的目录结构
M.probe = "/sd/tiles/15/26789/13001.jpg"
M.sidebar_w = 208   -- 右侧功能键栏宽（两列按钮）
M.status_h = 56

function M.layout()
    local w = _G.screen_w or 1024
    local h = _G.screen_h or 600
    local mw = w - M.sidebar_w  -- 地图区宽度（右侧留竖栏）
    return {
        w = w,
        h = h,
        sidebar_w = M.sidebar_w,
        map = {
            x = 0,
            y = 0,
            w = mw,
            h = h - M.status_h,
        },
        -- 右侧竖栏（与地图同高，底部状态栏横通）
        sidebar = {
            x = mw,
            y = 0,
            w = M.sidebar_w,
            h = h - M.status_h,
        },
        status_y = h - M.status_h + 4,
        note_y = h - 26,
    }
end

function M.source()
    return {
        root = M.tiles_root,
        format = "jpg",
        crs = "gcj02",
    }
end

function M.config(extra)
    local rect = M.layout().map
    local config = {
        x = rect.x, y = rect.y, w = rect.w, h = rect.h,
        center = { lon = M.home.lon, lat = M.home.lat },
        zoom = 15, min_zoom = 14, max_zoom = 17,
        input_crs = "wgs84",
        source = M.source(),
        follow = false,
        draggable = true,
        prefetch = 0,
        -- 一张瓦片按 256*256*4 预留。1024x480 大约 15 张可见瓦片
        cache_bytes = 6 * 1024 * 1024,
        max_tiles = 32,
    }
    for key, value in pairs(extra or {}) do
        config[key] = value
    end
    return config
end

function M.center(map)
    local lon, lat = map:get_center()
    if type(lon) == "table" then
        return lon.lon, lon.lat
    end
    return lon, lat
end

function M.screen(map, lon, lat)
    local x, y = map:geo_to_screen(lon, lat)
    if type(x) == "table" then
        return x.x, x.y
    end
    return x, y
end

function M.geo(map, x, y)
    local lon, lat = map:screen_to_geo(x, y)
    if type(lon) == "table" then
        return lon.lon, lon.lat
    end
    return lon, lat
end

-- 等加载队列清空。真机解 JPEG 比 PC 慢，默认等 30 秒
function M.wait_idle(map, timeout_ms)
    local elapsed = 0
    local limit = timeout_ms or 30000
    while elapsed < limit do
        local stats = map:get_stats()
        if stats.pending == 0 then
            sys.wait(80)
            stats = map:get_stats()
            if stats.pending == 0 then
                return stats
            end
        end
        sys.wait(25)
        elapsed = elapsed + 25
    end
    error("瓦片加载未完成")
end

return M
