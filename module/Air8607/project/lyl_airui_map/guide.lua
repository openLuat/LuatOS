--[[
@module  guide
@summary 轻量目的地引导（直线式，无需路网）：距离、方位箭头、转向提示、ETA、到达提醒
@version 1.0
@date    2026.10.28
@usage
这不是沿道路的路径规划，而是“指方位 + 直线距离”的简易指南针式引导，
适合野外、园区、厂区等没有路网数据的场景，全程离线：
1. 业务层选定目的地（收藏点或地图长按点）后 set_destination()
2. 每帧 GPS 更新调用 update(lon,lat,heading,speed,valid)
3. draw(ovl) 画：当前位置到目的地的虚线、目的地图钉、
   目的地不在屏内时在屏幕边缘指一个方向箭头
4. 到达阈值内触发 on_arrive 回调（业务层可弹窗/语音播报）
]]

local geo = require "geo"
local M = {}

M.ARRIVE_RADIUS = 30    -- 到达半径（米）
M.NEAR_RADIUS = 200     -- 接近提示（米）
M.EDGE_MARGIN = 40      -- 屏边箭头距边缘的像素

local DEST_COLOR = 0xE0322E  -- 红：目的地
local LINE_COLOR = 0xE0322E

function M.create()
    local self = setmetatable({}, { __index = M })
    self.dest = nil
    self.distance = nil
    self.bearing = nil
    self.turn = nil
    self.eta = nil
    self.arrived = false
    self.near_notified = false
    self.last_d = nil
    self.on_arrive = nil      -- function(guide)
    self.on_near = nil        -- function(guide)
    return self
end

--[[
设置目的地
@param dest table {name=,lon=,lat=}
]]
function M.set_destination(self, dest)
    self.dest = dest
    self.arrived = false
    self.near_notified = false
    self.last_d = nil
    log.info("guide", "目的地", dest and dest.name or "取消")
end

function M.cancel(self)
    self:set_destination(nil)
end

function M.active(self)
    return self.dest ~= nil
end

--[[
推入一帧定位
@param lon number
@param lat number
@param heading number 航向角（北0顺时针），无航向传 nil
@param speed number 地速 m/s，可选
@param valid boolean
@return boolean 本帧状态是否有变化（业务层可据此刷新状态栏）
]]
function M.update(self, lon, lat, heading, speed, valid)
    if not self.dest then
        return false
    end
    if not valid or not lon or not lat then
        self.distance = nil
        return true
    end
    local d = geo.distance(lon, lat, self.dest.lon, self.dest.lat)
    local brg = geo.bearing(lon, lat, self.dest.lon, self.dest.lat)
    self.distance = d
    self.bearing = brg

    -- 相对航向的转向角（-180~180，正=右转）
    if heading then
        local t = brg - heading
        while t > 180 do t = t - 360 end
        while t < -180 do t = t + 360 end
        self.turn = t
    else
        self.turn = nil
    end

    -- ETA：用当前速度粗估，速度过低不估
    if speed and speed >= 0.8 then
        self.eta = d / speed
    else
        self.eta = nil
    end

    -- 接近 / 到达判定（只触发一次）
    if d <= M.NEAR_RADIUS and not self.near_notified then
        self.near_notified = true
        if self.on_near then self.on_near(self) end
    end
    if d <= M.ARRIVE_RADIUS and not self.arrived then
        self.arrived = true
        if self.on_arrive then self.on_arrive(self) end
    end

    local changed = true
    if self.last_d and math.abs(self.last_d - d) < 1 then
        changed = false
    end
    self.last_d = d
    return changed
end

-- 转向口语化提示
local function turn_text(t)
    if not t then
        return nil
    end
    local a = math.abs(t)
    local dir = t > 0 and "右" or "左"
    if a <= 22 then
        return "朝目标方向直行"
    elseif a <= 60 then
        return "前方" .. dir .. "转"
    elseif a <= 110 then
        return dir .. "急转"
    elseif a >= 150 then
        return "请掉头"
    else
        return "向" .. dir .. "后方转"
    end
end

--[[
引导状态文字（状态栏用）
@return string
]]
function M.status_text(self)
    if not self.dest then
        return nil
    end
    if self.arrived then
        return "已到达：" .. self.dest.name
    end
    if not self.distance then
        return "等待有效定位…  目的地：" .. self.dest.name
    end
    local parts = {
        string.format("距%s %s（%s方向）",
            self.dest.name, geo.fmt_distance(self.distance),
            geo.compass(self.bearing)),
    }
    local tip = turn_text(self.turn)
    if tip then
        parts[#parts + 1] = tip
    end
    if self.eta then
        parts[#parts + 1] = "预计" .. geo.fmt_duration(self.eta) .. "到达"
    end
    return table.concat(parts, "  ")
end

--[[
在覆盖层上画引导：虚线连当前位置，目的地图钉；屏外时边缘箭头
@param ovl overlay
@param cur_lon number  当前经度
@param cur_lat number  当前纬度
@param heading number  当前航向（边缘箭头用目标方位即可，可不传）
]]
function M.draw(self, ovl, cur_lon, cur_lat)
    if not self.dest then
        return
    end
    local dx, dy = ovl:to_screen(self.dest.lon, self.dest.lat)
    if ovl:visible(dx, dy) then
        -- 目的地在屏内：图钉 + 当前位置到目的地的虚线
        if cur_lon and cur_lat then
            local cx, cy = ovl:to_screen(cur_lon, cur_lat)
            local seg = {
                { lon = cur_lon, lat = cur_lat },
                { lon = self.dest.lon, lat = self.dest.lat },
            }
            ovl:add_polyline(seg, LINE_COLOR, 3, 10, 8)
            ovl:add_dot(cx, cy, 4, 0x333333, 0xFFFFFF)
        end
        ovl:add_pin(dx, dy, DEST_COLOR, true)
    else
        -- 目的地在屏外：从屏幕中心朝投影方向，在边缘放箭头
        local w, h = ovl.w, ovl.h
        local ccx, ccy = w / 2, h / 2
        local vx, vy = dx - ccx, dy - ccy
        local ax, ay
        if math.abs(vx) < 1 and math.abs(vy) < 1 then
            ax, ay = ccx, M.EDGE_MARGIN
        else
            local sx = (vx ~= 0) and math.abs((w / 2 - M.EDGE_MARGIN) / vx) or math.huge
            local sy = (vy ~= 0) and math.abs((h / 2 - M.EDGE_MARGIN) / vy) or math.huge
            local s = math.min(sx, sy)
            ax, ay = ccx + vx * s, ccy + vy * s
        end
        -- 屏幕方向反算方位角：屏幕 y 向下，atan2(vx,-vy)
        local scr_brg = math.deg(math.atan(vx, -vy))
        if scr_brg < 0 then scr_brg = scr_brg + 360 end
        ovl:add_arrow(ax, ay, scr_brg, DEST_COLOR)
    end
end

return M
