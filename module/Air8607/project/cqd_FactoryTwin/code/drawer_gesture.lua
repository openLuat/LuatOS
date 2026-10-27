-- Pure Lua, single-primary-pointer top drawer gesture recognition.
-- This module owns no UI objects or event handlers. Map native events to
-- DOWN/HOLD/UP/CANCEL before calling touch(event,x,y,track_id,timestamp_ms).
-- Only a matching final UP can return OPEN or CLOSE. Success updates is_open().
-- Call set_open(boolean) whenever buttons/overlay change drawer visibility.
local Gesture = {}
Gesture.__index = Gesture
local WRAP = 4294967296
local EPSILON = 0.0000001 -- fractional coordinates may arrive after UI scaling

local function finite(value)
    return type(value) == "number" and value == value and
        value ~= math.huge and value ~= -math.huge
end

local function number(value, fallback, allow_zero)
    if not finite(value) or value < 0 or (not allow_zero and value == 0) then
        return fallback
    end
    return value
end

local function pointer(id)
    return (finite(id) and id >= 0 and id % 1 == 0) or
        (type(id) == "string" and id ~= "")
end

local function coordinates(x, y, timestamp)
    return finite(x) and x >= 0 and finite(y) and y >= 0 and
        finite(timestamp) and timestamp >= 0
end

function Gesture.new(config)
    config = config or {}
    local height = number(config.drawer_height, 288)
    local duration = number(config.max_duration_ms, 2000)
    if duration >= WRAP / 2 then duration = 2000 end
    local ratio = number(config.dominance_ratio, 0.65)
    if ratio > 1 then ratio = 0.65 end
    return setmetatable({
        open = false,
        config = {
            top_zone = number(config.top_zone, 64, true),
            open_threshold = number(config.open_threshold, 72),
            close_threshold = number(config.close_threshold, 64),
            drawer_height = height,
            close_zone_height = math.min(height, number(config.close_zone_height, 58)),
            max_duration_ms = duration,
            max_horizontal = number(config.max_horizontal, 100),
            dominance_ratio = ratio,
            movement_slop = number(config.movement_slop, 8, true),
            reversal_tolerance = number(config.reversal_tolerance, 18, true)
        }
    }, Gesture)
end

function Gesture:is_open()
    return self.open
end

function Gesture:cancel()
    self.track = nil
end

function Gesture:set_open(value)
    if type(value) ~= "boolean" then return false, "invalid_open" end
    self.open = value
    self:cancel()
    return true
end

local function reject(track, reason)
    if not track.rejected then
        track.rejected = true
        track.rejection_reason = reason
    end
end

function Gesture:_move(x, y, timestamp)
    local track, cfg = self.track, self.config
    if track.rejected then return end
    if not coordinates(x, y, timestamp) then reject(track, "invalid_input"); return end
    local elapsed = (timestamp % WRAP - track.start_timestamp) % WRAP
    if elapsed > cfg.max_duration_ms then reject(track, "timeout"); return end
    if elapsed < track.elapsed_ms then reject(track, "time_reversed"); return end
    track.elapsed_ms = elapsed
    local progress = (y - track.start_y) * track.direction
    local horizontal = math.abs(x - track.start_x)
    track.progress, track.horizontal = progress, horizontal
    if horizontal > cfg.max_horizontal + EPSILON then reject(track, "horizontal_excursion"); return end
    if progress < -cfg.movement_slop - EPSILON then reject(track, "wrong_direction"); return end
    if track.max_progress >= cfg.movement_slop and
        track.max_progress - progress > cfg.reversal_tolerance + EPSILON then
        reject(track, "reversal"); return
    end
    -- Ignore initial finger jitter, then require vertical dominance throughout
    -- the path. A later vertical endpoint cannot rescue a sideways excursion.
    if math.max(horizontal, math.abs(progress)) >= cfg.movement_slop and
        horizontal > math.max(cfg.movement_slop, math.max(0, progress) * cfg.dominance_ratio) + EPSILON then
        reject(track, "diagonal"); return
    end
    track.max_progress = math.max(track.max_progress, progress)
end

function Gesture:touch(event, x, y, track_id, timestamp)
    if event == "CANCEL" then
        if track_id == nil or (self.track and self.track.id == track_id) then self:cancel() end
        return nil
    end
    if event ~= "DOWN" and event ~= "HOLD" and event ~= "UP" then return nil end
    if not pointer(track_id) then return nil end
    if event == "DOWN" then
        -- Even a wrong-area DOWN owns the primary slot until it ends. Secondary
        -- fingers cannot turn an existing touch sequence into a valid gesture.
        if self.track or not coordinates(x, y, timestamp) then return nil end
        local cfg = self.config
        local in_zone = (not self.open and y <= cfg.top_zone) or
            (self.open and y >= cfg.drawer_height - cfg.close_zone_height and y <= cfg.drawer_height)
        self.track = {
            id = track_id, start_x = x, start_y = y,
            start_timestamp = timestamp % WRAP, elapsed_ms = 0,
            direction = self.open and -1 or 1,
            action = self.open and "CLOSE" or "OPEN",
            progress = 0, horizontal = 0, max_progress = 0,
            rejected = not in_zone,
            rejection_reason = not in_zone and "start_outside_zone" or nil
        }
        return nil
    end
    if not self.track or self.track.id ~= track_id then return nil end
    self:_move(x, y, timestamp)
    if event ~= "UP" then return nil end
    local track, cfg = self.track, self.config
    local threshold = track.action == "OPEN" and cfg.open_threshold or cfg.close_threshold
    local action
    -- Apply the strict dominance boundary at release, independently of jitter
    -- allowance used during the first few pixels of movement.
    if not track.rejected and track.progress + EPSILON >= threshold and
        track.horizontal <= math.min(cfg.max_horizontal, track.progress * cfg.dominance_ratio) + EPSILON then
        action = track.action
        self.open = action == "OPEN"
    end
    self:cancel()
    return action
end

-- Detached diagnostic state, useful for unit tests and bring-up logs.
function Gesture:snapshot()
    local result = {open = self.open, tracking = self.track ~= nil}
    if self.track then
        for key, value in pairs(self.track) do result[key] = value end
    end
    return result
end

return Gesture
