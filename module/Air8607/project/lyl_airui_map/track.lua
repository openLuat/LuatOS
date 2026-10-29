--[[
@module  track
@summary GPS 轨迹记录：按时间/距离阈值采样，里程、速度、移动时间统计，SD 持久化
@version 1.0
@date    2026.10.28
@usage
轨迹文件：/sd/map/tracks/track_<开始时间戳>.json，结构
{
  "name": "2026-10-28 09:00",
  "start": 1793000000,
  "stop": 1793003600,
  "distance": 1234.5,   -- 米
  "moving": 1500,       -- 移动时间（秒）
  "elapsed": 3600,      -- 总时长（秒，含停留）
  "max_speed": 9.2,     -- m/s
  "points": [ {"lon":114.31,"lat":34.80,"t":1793000000} ]
}
业务层每次拿到 GPS 定位后调用 update()；只有在 recording 状态才会采样。
采样采用“距离或时间阈值”双条件，过滤静止漂移和重复点。
]]

local store = require "store"
local geo = require "geo"
local M = {}

M.DIR = "/sd/map/tracks"

-- 采样阈值
M.MIN_DIST = 6       -- 距上一点至少 6 米才记（过滤静止漂移）
M.FORCE_TIME = 10    -- 即使没动，每 10 秒补一个点（轨迹时间连续）
M.MOVE_SPEED = 0.5   -- m/s，高于此速度算“移动”
M.MAX_POINTS = 20000 -- 单次轨迹点数上限，防止 SD 写爆

local TRACK_COLOR = 0x1E7BE8 -- 蓝：已走轨迹
local START_COLOR = 0x2BA84A -- 绿：起点
local END_COLOR = 0xE0322E   -- 红：终点

function M.create()
    local self = setmetatable({}, { __index = M })
    self.recording = false
    self:reset()
    return self
end

function M.reset(self)
    self.points = {}
    self.start_at = nil
    self.stop_at = nil
    self.distance = 0       -- 累计里程（米）
    self.moving = 0         -- 移动时间（秒）
    self.max_speed = 0      -- 最高速度（m/s）
    self.cur_speed = 0      -- 最近一段速度（m/s）
    self.last_lon = nil
    self.last_lat = nil
    self.last_t = nil
    self.last_save_t = nil
end

--[[
开始记录
@param now number 时间戳（秒），默认 os.time()
]]
function M.start(self, now)
    now = now or (os.time and os.time())
    self:reset()
    self.recording = true
    self.start_at = now
    log.info("track", "开始记录", tostring(now))
    return true
end

--[[
停止记录并存盘
@param now number
@return string|nil 保存成功的文件路径
]]
function M.stop(self, now)
    if not self.recording then
        return nil
    end
    now = now or (os.time and os.time())
    self.recording = false
    self.stop_at = now
    local path = self:save()
    log.info("track", "停止记录，点数", #self.points, "里程", self.distance)
    return path
end

function M.is_recording(self)
    return self.recording
end

function M.count(self)
    return #self.points
end

--[[
推入一帧 GPS 定位（业务层主循环 / GPS 任务调用）
@param lon number
@param lat number
@param valid boolean 定位是否有效
@param now number 时间戳（秒）
]]
function M.update(self, lon, lat, valid, now)
    if not self.recording or not valid or not lon or not lat or not now then
        return
    end
    -- 第一个点直接记录
    if #self.points == 0 then
        self:append(lon, lat, now, 0, 0)
        return
    end
    local d = geo.distance(self.last_lon, self.last_lat, lon, lat)
    local dt = now - self.last_t
    local seg_speed = (dt > 0) and (d / dt) or 0

    -- 满足任一即采样：移动超过距离阈值（低速也能记），或时间到强制补点
    local take = false
    if d >= M.MIN_DIST then
        take = true
    elseif dt >= M.FORCE_TIME then
        take = true
    end
    if take and #self.points < M.MAX_POINTS then
        self:append(lon, lat, now, d, seg_speed)
    end
end

-- 追加采样点并累计统计
function M.append(self, lon, lat, now, d, seg_speed)
    self.points[#self.points + 1] = { lon = lon, lat = lat, t = now }
    self.distance = self.distance + d
    if seg_speed >= M.MOVE_SPEED then
        -- 与上一点的间隔计入移动时间
        local dt = self.last_t and (now - self.last_t) or 0
        if dt > 0 and dt <= M.FORCE_TIME + 5 then
            self.moving = self.moving + dt
        end
    end
    if seg_speed > self.max_speed then
        self.max_speed = seg_speed
    end
    self.cur_speed = seg_speed
    self.last_lon, self.last_lat, self.last_t = lon, lat, now

    -- 记录中每分钟自动落盘一次，防止意外掉电丢全程
    if not self.last_save_t or (now - self.last_save_t) >= 60 then
        self:save()
        self.last_save_t = now
    end
end

--[[
轨迹存盘（记录中也可调用，用于自动保存）
@return string|nil 文件路径
]]
function M.save(self)
    if #self.points == 0 then
        return nil
    end
    store.mkdir("/sd/map")
    store.mkdir(M.DIR)
    local stamp = self.start_at or self.points[1].t
    local path = M.DIR .. "/track_" .. tostring(stamp) .. ".json"
    local elapsed = (self.stop_at or self.last_t or stamp) - stamp
    local data = {
        name = os.date and os.date("%Y-%m-%d %H:%M", stamp) or tostring(stamp),
        start = stamp,
        stop = self.stop_at,
        distance = math.floor(self.distance * 10 + 0.5) / 10,
        moving = self.moving,
        elapsed = elapsed,
        max_speed = math.floor(self.max_speed * 100 + 0.5) / 100,
        points = self.points,
    }
    local ok = store.save(path, data, false)
    if not ok then
        log.error("track", "轨迹保存失败", path)
        return nil
    end
    return path
end

--[[
加载一条历史轨迹（停止后查看 / 开机回显）
@param path string
@return boolean
]]
function M.load(self, path)
    local data = store.load(path)
    if not data or type(data.points) ~= "table" then
        return false
    end
    self:reset()
    self.recording = false
    self.points = data.points
    self.start_at = data.start
    self.stop_at = data.stop
    self.distance = data.distance or 0
    self.moving = data.moving or 0
    self.max_speed = data.max_speed or 0
    if self.points[1] then
        self.last_lon = self.points[#self.points].lon
        self.last_lat = self.points[#self.points].lat
        self.last_t = self.points[#self.points].t
    end
    return true
end

--[[
在覆盖层上画轨迹：折线 + 起点绿点 + 终点红点
@param ovl overlay
]]
function M.draw(self, ovl)
    if #self.points < 1 then
        return
    end
    if #self.points >= 2 then
        ovl:add_polyline(self.points, TRACK_COLOR, 5)
    end
    local p0 = self.points[1]
    local x0, y0 = ovl:to_screen(p0.lon, p0.lat)
    ovl:add_dot(x0, y0, 6, START_COLOR, 0xFFFFFF)
    if #self.points > 1 then
        local p1 = self.points[#self.points]
        local x1, y1 = ovl:to_screen(p1.lon, p1.lat)
        ovl:add_dot(x1, y1, 6, END_COLOR, 0xFFFFFF)
    end
end

--[[
统计摘要文字（状态栏用）
@return string
]]
function M.summary(self)
    if #self.points == 0 then
        return "无轨迹"
    end
    local stamp = self.start_at or self.points[1].t
    local elapsed = (self.stop_at or self.last_t or stamp) - stamp
    local avg = self.moving > 0 and (self.distance / self.moving) or 0
    if self.recording then
        return string.format("记录中 %s  里程%s  均速%s  %d点",
            geo.fmt_duration(elapsed), geo.fmt_distance(self.distance),
            geo.fmt_speed(avg), #self.points)
    end
    return string.format("轨迹 %s  里程%s  移动%s  最高%s",
        geo.fmt_duration(elapsed), geo.fmt_distance(self.distance),
        geo.fmt_duration(self.moving), geo.fmt_speed(self.max_speed))
end

return M
