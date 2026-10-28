--[[
@module claw_model
@summary 抓娃娃游戏状态机（纯 Lua5.3，不碰时钟/图形/音频）
@ver 1.0.0
@author cqd
@note 所有推进都由 step(dt_ms) 驱动，UI 只读 snapshot() 快照。
      阶段机：IDLE -> DROP -> GRAB -> LIFT -> CARRY -> RELEASE -> RESULT -> IDLE
@usage
local Claw = require "claw_model"
local model = Claw.new(config, rng.float)
model:input(-1)              -- 按住左移（松开传 0）
model:target(300)            -- 点玻璃柜，爪子移到该 X
model:grab()                 -- 按下抓取
model:step(40)               -- 帧推进
local s = model:snapshot()   -- 渲染快照
]]

local Claw = {}
Claw.__index = Claw

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- 构造游戏状态机
-- @tparam table config 布局与调参（见 config.lua）
-- @tparam function rng_fn 返回 [0,1) 浮点的随机函数
function Claw.new(config, rng_fn)
    assert(type(config) == "table", "config table required")
    assert(type(rng_fn) == "function", "rng function required")
    for _, k in ipairs({ "claw_min_x", "claw_max_x", "claw_rest_y", "claw_grab_y",
                        "toy_y", "toy_r", "floor_y", "chute_x", "chute_land_y" }) do
        assert(finite(config[k]), "config." .. k .. " must be a finite number")
    end
    assert(type(config.toys) == "table" and #config.toys > 0, "config.toys required")

    local self = setmetatable({}, Claw)
    self.rng = rng_fn
    -- 布局
    self.claw_min_x = config.claw_min_x
    self.claw_max_x = config.claw_max_x
    self.claw_rest_y = config.claw_rest_y
    self.claw_grab_y = config.claw_grab_y
    self.toy_y = config.toy_y
    self.toy_r = config.toy_r
    self.floor_y = config.floor_y
    self.chute_x = config.chute_x
    self.chute_land_y = config.chute_land_y
    self.fall_g = config.toy_fall_g or 2600
    -- 调参
    self.claw_speed = config.claw_speed or 420
    self.drop_speed = config.drop_speed or 520
    self.lift_speed = config.lift_speed or 380
    self.carry_speed = config.carry_speed or 460
    self.grab_ms = config.grab_ms or 480
    self.release_ms = config.release_ms or 620
    self.result_hold_ms = config.result_hold_ms or 1400
    self.grab_chance = config.grab_chance or 0.62
    self.align_bonus = config.align_bonus or 0.33
    self.capture_pad = config.capture_pad or 18
    -- 状态
    self.phase = "IDLE"
    self.elapsed_ms = 0
    self.phase_ms = 0
    self.claw_x = math.floor((config.claw_min_x + config.claw_max_x) / 2)
    self.claw_y = config.claw_rest_y
    self.prong = 1          -- 1 全张开，0 全闭合
    self.move_dir = 0       -- -1 / 0 / 1
    self.target_x = nil
    self.swing, self.swing_v = 0, 0
    self.carried = nil
    self.result_ok = nil
    self.score, self.attempts, self.successes = 0, 0, 0
    self.event_seq, self.last_event = 0, nil
    self.toys = {}
    for i, t in ipairs(config.toys) do
        self.toys[i] = {
            id = i,
            x = math.floor(t.x),
            y = config.toy_y,
            r = t.r or config.toy_r,
            kind = t.kind or "bear",
            color = t.color or 0xE8A33D,
            caught = false,
        }
    end
    self.falling = {}
    return self
end

local function emit(self, name)
    self.event_seq = self.event_seq + 1
    self.last_event = name
end

-- 按住左右移动（-1 左 / 0 松开 / 1 右），仅 IDLE 有效
function Claw:input(dir)
    if self.phase ~= "IDLE" then return false, "not_idle" end
    dir = finite(dir) and math.floor(dir) or 0
    dir = clamp(dir, -1, 1)
    if dir ~= 0 then self.target_x = nil end
    self.move_dir = dir
    return true
end

-- 点玻璃柜移动到目标 X（仅 IDLE 有效，拖动可连续更新）
function Claw:target(x)
    if self.phase ~= "IDLE" then return false, "not_idle" end
    if not finite(x) then return false, "invalid_x" end
    self.target_x = math.floor(clamp(x, self.claw_min_x, self.claw_max_x))
    self.move_dir = 0
    return true
end

-- 按下抓取，启动抓取序列（仅 IDLE 有效）
function Claw:grab()
    if self.phase ~= "IDLE" then return false, "not_idle" end
    self.attempts = self.attempts + 1
    self.phase = "DROP"
    self.phase_ms = 0
    self.move_dir = 0
    self.target_x = nil
    self.result_ok = nil
    emit(self, "grab_start")
    return true
end

-- 抓取判定：最近的可抓娃娃 + 距离对准度折算成功率
local function resolve_capture(self)
    local best, best_d
    for _, toy in ipairs(self.toys) do
        if not toy.caught then
            local d = math.abs(toy.x - self.claw_x)
            if d <= toy.r + self.capture_pad and (not best_d or d < best_d) then
                best, best_d = toy, d
            end
        end
    end
    if not best then return nil, false end
    local reach = best.r + self.capture_pad
    local chance = clamp(self.grab_chance + self.align_bonus * (1 - best_d / reach), 0, 0.95)
    if self.rng() < chance then
        return best, true
    end
    return nil, false
end

-- 帧推进
-- @tparam number dt_ms 距上一帧的毫秒数（内部钳制到 250ms 防卡顿穿帮）
function Claw:step(dt_ms)
    if not finite(dt_ms) or dt_ms < 0 then return false, "invalid_dt" end
    if dt_ms > 250 then dt_ms = 250 end
    local dt = dt_ms / 1000
    self.elapsed_ms = self.elapsed_ms + dt_ms

    -- 出货下落
    for i = #self.falling, 1, -1 do
        local f = self.falling[i]
        f.vy = f.vy + self.fall_g * dt
        f.y = f.y + f.vy * dt
        if f.y >= self.chute_land_y then
            table.remove(self.falling, i)
        end
    end

    -- 吊挂摆动（弹簧回正）
    if self.carried then
        self.swing_v = self.swing_v + (-self.swing * 9 - self.swing_v * 1.6) * dt
        self.swing = self.swing + self.swing_v * dt
    end

    local p = self.phase
    if p == "IDLE" then
        self.prong = self.prong + (1 - self.prong) * math.min(1, dt * 6)
        self.claw_y = self.claw_y + (self.claw_rest_y - self.claw_y) * math.min(1, dt * 6)
        if self.move_dir ~= 0 then
            self.claw_x = clamp(self.claw_x + self.move_dir * self.claw_speed * dt,
                                self.claw_min_x, self.claw_max_x)
        elseif self.target_x then
            local d = self.target_x - self.claw_x
            local st = self.claw_speed * dt
            if math.abs(d) <= st then
                self.claw_x = self.target_x
                self.target_x = nil
            else
                self.claw_x = self.claw_x + (d > 0 and st or -st)
            end
        end
    elseif p == "DROP" then
        self.claw_y = math.min(self.claw_grab_y, self.claw_y + self.drop_speed * dt)
        if self.claw_y >= self.claw_grab_y then
            self.phase = "GRAB"
            self.phase_ms = 0
        end
    elseif p == "GRAB" then
        self.phase_ms = self.phase_ms + dt_ms
        local k = clamp(self.phase_ms / self.grab_ms, 0, 1)
        self.prong = 1 - k
        if k >= 1 then
            local toy, ok = resolve_capture(self)
            if ok and toy then
                self.carried = toy
                self.swing = 0
                self.swing_v = (self.claw_x <= self.chute_x) and 0.10 or -0.10
                self.result_ok = true
                emit(self, "grab_ok")
            else
                self.result_ok = false
                emit(self, "grab_fail")
            end
            self.phase = "LIFT"
            self.phase_ms = 0
        end
    elseif p == "LIFT" then
        self.claw_y = math.max(self.claw_rest_y, self.claw_y - self.lift_speed * dt)
        if self.claw_y <= self.claw_rest_y then
            self.phase = "CARRY"
            self.phase_ms = 0
        end
    elseif p == "CARRY" then
        local d = self.chute_x - self.claw_x
        local st = self.carry_speed * dt
        if math.abs(d) <= st then
            self.claw_x = self.chute_x
            self.phase = "RELEASE"
            self.phase_ms = 0
        else
            self.claw_x = self.claw_x + (d > 0 and st or -st)
        end
    elseif p == "RELEASE" then
        self.phase_ms = self.phase_ms + dt_ms
        local k = clamp(self.phase_ms / self.release_ms, 0, 1)
        self.prong = k
        if k >= 0.45 and self.carried then
            local toy = self.carried
            self.carried = nil
            toy.caught = true
            self.score = self.score + 1
            self.successes = self.successes + 1
            self.falling[#self.falling + 1] = {
                x = self.chute_x, y = self.claw_y + 96, vy = 40,
                kind = toy.kind, color = toy.color, r = toy.r,
            }
            emit(self, "prize_drop")
        end
        if k >= 1 then
            self.phase = "RESULT"
            self.phase_ms = 0
        end
    elseif p == "RESULT" then
        self.phase_ms = self.phase_ms + dt_ms
        if self.phase_ms >= self.result_hold_ms then
            self.phase = "IDLE"
            self.phase_ms = 0
            -- 娃娃抓完自动补货，保证 demo 可一直玩
            local alive = 0
            for _, toy in ipairs(self.toys) do
                if not toy.caught then alive = alive + 1 end
            end
            if alive == 0 then
                for _, toy in ipairs(self.toys) do
                    toy.caught = false
                end
                emit(self, "refill")
            end
        end
    end
    return true
end

-- 渲染快照（深拷贝出与内部状态无关的只读表）
function Claw:snapshot()
    local toys = {}
    for i, toy in ipairs(self.toys) do
        toys[i] = {
            id = toy.id, x = toy.x, y = toy.y, r = toy.r,
            kind = toy.kind, color = toy.color, caught = toy.caught,
        }
    end
    local falling = {}
    for i, f in ipairs(self.falling) do
        falling[i] = { x = f.x, y = f.y, r = f.r, kind = f.kind, color = f.color }
    end
    local carried
    if self.carried then
        carried = {
            x = self.carried.x, r = self.carried.r,
            kind = self.carried.kind, color = self.carried.color,
        }
    end
    return {
        phase = self.phase,
        claw_x = self.claw_x,
        claw_y = self.claw_y,
        prong = self.prong,
        swing = self.swing,
        carried = carried,
        toys = toys,
        falling = falling,
        score = self.score,
        attempts = self.attempts,
        successes = self.successes,
        result_ok = self.result_ok,
        elapsed_ms = self.elapsed_ms,
        event_seq = self.event_seq,
        last_event = self.last_event,
    }
end

return Claw
