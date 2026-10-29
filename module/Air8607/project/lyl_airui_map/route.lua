--[[
@module  route
@summary 离线路线引导：加载 PC 预生成路线，沿线进度、剩余里程、偏航距离、到点提醒
@version 1.0
@date    2026.10.28
@usage
路线文件：/sd/map/routes/<名字>.json（由电脑端工具排好途经点生成），结构
{
  "name": "开封北站->市政府",
  "points": [
    {"lon":114.30,"lat":34.84,"name":"开封北站"},
    {"lon":114.31,"lat":34.80,"name":""},
    {"lon":114.314,"lat":34.797,"name":"市政府"}
  ]
}
线段总里程、进度在设备端计算（Haversine 累加，不依赖路网规划）。
当前位置投影到最近线段：已走里程、剩余里程、偏航距离、下一途经点。
]]

local store = require "store"
local geo = require "geo"
local M = {}

M.DIR = "/sd/map/routes"
M.WAYPOINT_RADIUS = 60   -- 途经点到达半径（米）
M.OFFROAD_LIMIT = 80     -- 偏航超过 80 米提示

local ROUTE_COLOR = 0x2BA84A -- 绿：整条路线
local REM_COLOR = 0xE0322E   -- 红：前方剩余路线
local WP_COLOR = 0xF59E0B    -- 橙：途经点

function M.create()
    local self = setmetatable({}, { __index = M })
    self.points = nil
    self.name = nil
    self.seg_len = {}       -- 每段长度
    self.total = 0          -- 路线总长（米）
    self.progress = 0       -- 已走里程（米）
    self.remaining = nil
    self.crosstrack = nil   -- 距路线垂直距离（米）
    self.seg_index = nil    -- 当前所在线段序号
    self.next_wp = nil      -- 下一途经点（table）
    self.passed = {}        -- 已通过的途经点索引
    self.on_waypoint = nil  -- function(route, point)
    self.on_finish = nil    -- function(route)
    self.finished = false
    return self
end

function M.loaded(self)
    return self.points ~= nil
end

--[[
从文件加载路线
@param path string
@return boolean
]]
function M.load(self, path)
    local data = store.load(path)
    if not data or type(data.points) ~= "table" or #data.points < 2 then
        log.error("route", "路线文件无效", tostring(path))
        return false
    end
    self.points = data.points
    self.name = data.name or "路线"
    self:rebuild()
    log.info("route", "已加载", self.name, "点", #self.points, "总长", self.total)
    return true
end

-- 直接用一组点构造（测试/业务层内存生成）
function M.set_points(self, points, name)
    if not points or #points < 2 then
        return false
    end
    self.points = points
    self.name = name or "路线"
    self:rebuild()
    return true
end

-- 重新计算分段长度与总长，重置引导状态
function M.rebuild(self)
    self.seg_len = {}
    self.total = 0
    for i = 1, #self.points - 1 do
        local d = geo.distance(
            self.points[i].lon, self.points[i].lat,
            self.points[i + 1].lon, self.points[i + 1].lat)
        self.seg_len[i] = d
        self.total = self.total + d
    end
    self.progress = 0
    self.remaining = self.total
    self.crosstrack = nil
    self.seg_index = 1
    self.passed = {}
    self.finished = false
    self.next_wp = self:named_wp(2) or self.points[#self.points]
end

function M.clear(self)
    self.points = nil
    self.name = nil
    self.seg_len = {}
    self.total = 0
    self.progress = 0
    self.remaining = nil
    self.crosstrack = nil
    self.seg_index = nil
    self.next_wp = nil
    self.passed = {}
    self.finished = false
end

-- 某点是否为带名途经点
function M.named_wp(self, i)
    local p = self.points[i]
    return p and p.name and p.name ~= "" and p or nil
end

--[[
点到线段的最近点（局部平面近似，单位米）
@return number 在线段上的投影比例 t (0~1)
@return number 垂直距离（米）
]]
local function project_to_segment(lon, lat, p1, p2)
    -- 以 p1 为原点，等距圆柱局部坐标（米）
    local kx = 111320.0 * math.cos(math.rad((lat + p1.lat + p2.lat) / 3))
    local ky = 110540.0
    local ax, ay = (lon - p1.lon) * kx, (lat - p1.lat) * ky
    local bx, by = (p2.lon - p1.lon) * kx, (p2.lat - p1.lat) * ky
    local len2 = bx * bx + by * by
    local t = 0
    if len2 > 0.0001 then
        t = (ax * bx + ay * by) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local px, py = bx * t, by * t
    local dx, dy = ax - px, ay - py
    return t, math.sqrt(dx * dx + dy * dy)
end

--[[
推入一帧定位，更新沿线状态
@param lon number
@param lat number
@param valid boolean
@param speed number 可选，用于 ETA
@return number|nil ETA 秒
]]
function M.update(self, lon, lat, valid, speed)
    if not self.points or not valid then
        return nil
    end
    -- 找最近线段：只在当前段及相邻一段里选，避免折返时进度乱跳，
    -- 但相邻段都不如再下一段时退化为全路线搜索
    local best_i, best_t, best_d
    local function consider(i)
        if i < 1 or i >= #self.points then return end
        local t, d = project_to_segment(lon, lat, self.points[i], self.points[i + 1])
        if not best_d or d < best_d then
            best_i, best_t, best_d = i, t, d
        end
    end
    consider(self.seg_index)
    consider(self.seg_index + 1)
    consider(self.seg_index - 1)
    -- 当前位置离路线太远（抄近路/跳点），全路线重搜
    if best_d > M.WAYPOINT_RADIUS * 2 then
        best_i, best_t, best_d = nil, nil, nil
        for i = 1, #self.points - 1 do
            consider(i)
        end
    end

    self.seg_index = best_i
    self.crosstrack = best_d

    -- 已走里程 = 前序整段 + 当前段投影部分（不回退）
    local before = 0
    for i = 1, best_i - 1 do
        before = before + self.seg_len[i]
    end
    local proj_progress = before + self.seg_len[best_i] * best_t
    if proj_progress > self.progress then
        self.progress = proj_progress
    end
    self.remaining = math.max(self.total - self.progress, 0)

    -- 途经点通过判定：投影越过带名点，或物理距离进入半径
    for i = 2, #self.points do
        local wp = self:named_wp(i)
        if wp and not self.passed[i] then
            local before_i = 0
            for j = 1, i - 1 do before_i = before_i + self.seg_len[j] end
            local dwp = geo.distance(lon, lat, wp.lon, wp.lat)
            if self.progress >= before_i - 2 or dwp <= M.WAYPOINT_RADIUS then
                self.passed[i] = true
                if i == #self.points then
                    self.finished = true
                    if self.on_finish then self.on_finish(self) end
                elseif self.on_waypoint then
                    self.on_waypoint(self, wp)
                end
            end
        end
    end

    -- 终点未命名 / 或已走到 99% 路程，按进度判完成
    if not self.finished and self.total > 0
        and self.progress >= self.total - 5 then
        self.finished = true
        if self.on_finish then self.on_finish(self) end
    end

    if not self.finished then
        self.next_wp = self:next_named(best_i + 1) or self.points[#self.points]
    end

    if speed and speed >= 0.8 and self.remaining then
        return self.remaining / speed
    end
    return nil
end

-- 从索引 start 起找下一个带名途经点
function M.next_named(self, start)
    for i = start, #self.points do
        local wp = self:named_wp(i)
        if wp then return wp end
    end
    return nil
end

function M.off_route(self)
    return self.crosstrack ~= nil and self.crosstrack > M.OFFROAD_LIMIT
end

--[[
画路线：整条绿色，当前位置往前的剩余部分叠红色虚线；途经点橙点
@param ovl overlay
]]
function M.draw(self, ovl)
    if not self.points then
        return
    end
    ovl:add_polyline(self.points, ROUTE_COLOR, 6)
    -- 剩余路段（当前段投影点 -> 终点）用红色强调
    if self.seg_index and not self.finished then
        local remain_pts = self:remaining_points()
        if remain_pts and #remain_pts >= 2 then
            ovl:add_polyline(remain_pts, REM_COLOR, 4, 12, 8)
        end
    end
    -- 带名途经点
    for i = 2, #self.points - 1 do
        local wp = self:named_wp(i)
        if wp then
            local x, y = ovl:to_screen(wp.lon, wp.lat)
            ovl:add_dot(x, y, 6, WP_COLOR, 0xFFFFFF)
        end
    end
end

-- 构造剩余路线点列（在当前段上按投影比例插值出起点）
function M.remaining_points(self)
    if not self.seg_index then
        return nil
    end
    local p1 = self.points[self.seg_index]
    local p2 = self.points[self.seg_index + 1]
    -- 由当前段已走比例反算 t
    local before = 0
    for i = 1, self.seg_index - 1 do
        before = before + self.seg_len[i]
    end
    local t = self.seg_len[self.seg_index] > 0
        and math.min(math.max((self.progress - before) / self.seg_len[self.seg_index], 0), 1)
        or 0
    local pts = { {
        lon = p1.lon + (p2.lon - p1.lon) * t,
        lat = p1.lat + (p2.lat - p1.lat) * t,
    } }
    for i = self.seg_index + 1, #self.points do
        pts[#pts + 1] = self.points[i]
    end
    return pts
end

--[[
路线状态文字
@return string
]]
function M.status_text(self)
    if not self.points then
        return nil
    end
    if self.finished then
        return "路线已完成：" .. self.name
    end
    local pct = self.total > 0 and math.floor(self.progress / self.total * 100 + 0.5) or 0
    local text = string.format("%s  已走%s/%s（%d%%）",
        self.name, geo.fmt_distance(self.progress),
        geo.fmt_distance(self.total), pct)
    if self.next_wp and self.next_wp.name and self.next_wp.name ~= "" then
        text = text .. "  下一点：" .. self.next_wp.name
    end
    if self:off_route() then
        text = text .. string.format("  ⚠偏航%.0f米", self.crosstrack)
    end
    return text
end

return M
