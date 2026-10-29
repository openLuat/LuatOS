--[[
@module  poi
@summary 多点标注收藏夹：图标随地图移动，点击命中、增删改、SD JSON 持久化
@version 1.0
@date    2026.10.28
@usage
POI 文件：/sd/map/pois.json，结构
{
  "points": [
    {"name": "市政府", "lon": 114.31, "lat": 34.79, "kind": 0}
  ]
}
kind 决定颜色，便于分类（家/公司/客户/服务点）。
首次没有文件时使用内置开封示例点，保存后生成文件。
]]

local store = require "store"
local geo = require "geo"
local M = {}

M.FILE = "/sd/map/pois.json"

-- 分类配色：索引 -> 颜色
M.KIND_COLORS = {
    [0] = 0xE0322E, -- 红：重点/目的地
    [1] = 0x1E7BE8, -- 蓝：公司/工作
    [2] = 0x2BA84A, -- 绿：家
    [3] = 0xF59E0B, -- 橙：客户
    [4] = 0x7C5CD6, -- 紫：服务点
}
M.KIND_NAMES = {
    [0] = "重点",
    [1] = "公司",
    [2] = "家",
    [3] = "客户",
    [4] = "服务点",
}

-- 内置示例（开封市区，WGS84），无文件时使用
local function builtin_points()
    return {
        { name = "皇宋大观", lon = 114.325362, lat = 34.797252, kind = 0 },
        { name = "鼎立国际城E区", lon = 114.315058, lat = 34.816085, kind = 0 },
        { name = "开封市政府", lon = 114.314000, lat = 34.797000, kind = 0 },
        { name = "开封北站",   lon = 114.306800, lat = 34.845000, kind = 1 },
        { name = "包公祠",     lon = 114.332000, lat = 34.793000, kind = 4 },
        { name = "清明上河园", lon = 114.340000, lat = 34.816000, kind = 4 },
        { name = "鼓楼广场",   lon = 114.348000, lat = 34.795000, kind = 3 },
    }
end

function M.create()
    local self = setmetatable({}, { __index = M })
    self.points = {}
    self.active_name = nil
    self:load()
    return self
end

-- 从文件加载；失败用内置示例
function M.load(self)
    local data = store.load(M.FILE)
    if data and type(data.points) == "table" and #data.points > 0 then
        self.points = data.points
    else
        self.points = builtin_points()
    end
    log.info("poi", "已加载收藏点", #self.points)
end

-- 写回文件
function M.save(self)
    store.mkdir("/sd/map")
    local ok = store.save(M.FILE, { points = self.points }, false)
    log.info("poi", "保存收藏点", #self.points, tostring(ok))
    return ok
end

function M.count(self)
    return #self.points
end

function M.color_of(kind)
    return M.KIND_COLORS[kind] or M.KIND_COLORS[0]
end

--[[
在覆盖层上画所有 POI
@param ovl overlay 覆盖层
@param map userdata
]]
function M.draw(self, ovl)
    for _, p in ipairs(self.points) do
        local x, y = ovl:to_screen(p.lon, p.lat)
        local active = (p.name == self.active_name)
        ovl:add_pin(x, y, M.color_of(p.kind), active)
    end
end

--[[
命中测试：屏幕局部像素是否落在某个 POI 上
@param ovl overlay
@param x number 控件局部 x
@param y number 局部 y
@return table|nil 命中的 POI
]]
function M.hit_test(self, ovl, x, y)
    local radius = 16
    local best, best_d
    for _, p in ipairs(self.points) do
        local px, py = ovl:to_screen(p.lon, p.lat)
        local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
        if d <= radius and (not best_d or d < best_d) then
            best, best_d = p, d
        end
    end
    return best
end

function M.set_active(self, point)
    self.active_name = point and point.name or nil
end

--[[
新增一个收藏点
@param name string
@param lon number
@param lat number
@param kind number|nil
]]
function M.add(self, name, lon, lat, kind)
    self.points[#self.points + 1] = {
        name = name,
        lon = lon,
        lat = lat,
        kind = kind or 0,
    }
    self:save()
end

-- 按引用删除
function M.remove(self, point)
    for i, p in ipairs(self.points) do
        if p == point then
            table.remove(self.points, i)
            if self.active_name == point.name then
                self.active_name = nil
            end
            self:save()
            return true
        end
    end
    return false
end

--[[
生成当前选中 POI 的描述文字
@param point table
@param map userdata 可选，用于附加与地图中心的距离
]]
function M.describe(self, point, map)
    if not point then
        return nil
    end
    local text = string.format("%s（%s） %.6f, %.6f",
        point.name, M.KIND_NAMES[point.kind] or "重点", point.lon, point.lat)
    if map then
        local clon, clat = map:get_center()
        if type(clon) == "table" then
            clon, clat = clon.lon, clon.lat
        end
        local d = geo.distance(clon, clat, point.lon, point.lat)
        text = text .. "  距中心 " .. geo.fmt_distance(d)
    end
    return text
end

return M
