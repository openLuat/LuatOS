-- 宠物公园的纯 Lua 行为层：不创建 UI，不依赖系统时钟。
-- 调用方以启动后的绝对毫秒数 update()；各阶段从前一截止时间开始，迟到不漂移。
local C = require("config")
local M = {}
local pets, generators = {}, {}
local created, last_ms = false, 0
local active_count = 0
local quality = "low"
local MODULUS, MULTIPLIER = 2147483647, 16807

local function prng(seed)
    seed = tonumber(seed)
    if not seed or seed ~= seed or seed == math.huge or seed == -math.huge then seed = 1 end
    local state = math.floor(seed) % MODULUS
    if state <= 0 then state = MODULUS - 1 end
    return function(low, high)
        -- 最大乘积小于 2^46，Lua 整数和双精度数都可以精确保存。
        state = (state * MULTIPLIER) % MODULUS
        if low == nil then return state end
        return low + math.floor(state / MODULUS * (high - low + 1))
    end
end

local function check_config()
    assert(type(C.PETS) == "table" and #C.PETS == 8, "scene requires eight pets")
    assert(C.X_MIN < C.X_MAX and C.MIN_DISTANCE > 0, "invalid scene bounds")
    assert(C.MAX_DISTANCE >= C.MIN_DISTANCE, "invalid run distance")
    assert(C.X_MAX - C.X_MIN >= 2 * C.MIN_DISTANCE, "scene is too narrow")
    assert(C.DURATION_MIN >= 1 and C.DURATION_MAX >= C.DURATION_MIN,
        "invalid scene duration")
    assert(C.DURATION_MIN % 1 == 0 and C.DURATION_MAX % 1 == 0,
        "scene durations must be integer seconds")
    assert(C.LANE_DRIFT >= 0 and C.RUN_POSE_MS > 0, "invalid pose settings")
    assert(type(C.HQ_MAX_COUNT) == "number" and C.HQ_MAX_COUNT % 1 == 0
        and C.HQ_MAX_COUNT >= 1 and C.HQ_MAX_COUNT <= 4, "invalid high quality count")
    assert(type(C.HQ_RUN_FRAMES) == "number" and C.HQ_RUN_FRAMES % 1 == 0
        and C.HQ_RUN_FRAMES > 2 and type(C.HQ_FPS) == "number"
        and C.HQ_FPS > 0 and C.HQ_FPS < math.huge, "invalid high quality poses")
    local count = C.INITIAL_PET_COUNT or 8
    assert(type(count) == "number" and count % 1 == 0 and count >= 1 and count <= 8,
        "initial pet count must be an integer from 1 to 8")
end

local function begin_phase(pet, random, phase, at_ms)
    pet.phase = phase
    pet.start_ms = at_ms
    pet.duration_ms = random(C.DURATION_MIN, C.DURATION_MAX) * 1000
    pet.end_ms = at_ms + pet.duration_ms
    pet.from_x, pet.from_y = pet.x, pet.y
    pet.target_x, pet.target_y = pet.x, pet.y

    if phase == "run" then
        local sign = random(0, 1) == 0 and -1 or 1
        local available = sign > 0 and C.X_MAX - pet.x or pet.x - C.X_MIN
        if available < C.MIN_DISTANCE then
            sign = -sign
            available = sign > 0 and C.X_MAX - pet.x or pet.x - C.X_MIN
        end
        local distance = random(C.MIN_DISTANCE, math.floor(math.min(C.MAX_DISTANCE, available)))
        pet.target_x = pet.x + sign * distance
        pet.target_y = pet.lane + random(-C.LANE_DRIFT, C.LANE_DRIFT)
        pet.direction = sign > 0 and "r" or "l"
        pet.frame, pet.bob = 1, 0
    else
        pet.frame, pet.bob = 0, 0
    end
end

local function render_pose(pet, now_ms)
    local elapsed = now_ms - pet.start_ms
    if pet.phase == "run" then
        local t = math.max(0, math.min(1, elapsed / pet.duration_ms))
        local eased = t * t * (3 - 2 * t)
        pet.x = pet.from_x + (pet.target_x - pet.from_x) * eased
        pet.y = pet.from_y + (pet.target_y - pet.from_y) * eased
        if pet.quality == "high" then
            pet.frame = 1 + math.floor(elapsed * C.HQ_FPS / 1000) % C.HQ_RUN_FRAMES
        else
            pet.frame = 1 + math.floor(elapsed / C.RUN_POSE_MS) % 2
        end
        -- 位移起伏沿用原步态节奏；增加姿态帧不会把每次起伏也加快一倍。
        pet.bob = -math.floor(3 * math.abs(math.sin(elapsed * math.pi / C.RUN_POSE_MS)) + 0.5)
    else
        -- 停止期间地面坐标严格不变，只有绘制用的 bob 轻轻呼吸。
        pet.x, pet.y = pet.from_x, pet.from_y
        pet.frame = 0
        pet.bob = math.floor(math.sin(elapsed * 2 * math.pi / 2400) + 0.5)
    end
end

function M.restart(seed)
    check_config()
    active_count = C.INITIAL_PET_COUNT or 8
    quality = active_count <= C.HQ_MAX_COUNT and "high" or "low"
    local master = prng(seed or 1)
    local span = C.X_MAX - C.X_MIN
    for index, spec in ipairs(C.PETS) do
        local random = prng(master())
        generators[index] = random
        local pet = pets[index] or {}
        pets[index] = pet
        pet.id, pet.kind, pet.variant = spec.id, spec.kind, spec.variant
        pet.lane, pet.zoom = spec.lane, spec.zoom
        pet.quality = index <= active_count and quality or "low"
        -- 八个初始横向位置交错分散，保留小范围随机变化。
        local slot = ((index - 1) * 5) % #C.PETS
        local jitter = random(-24, 24)
        pet.x = math.max(C.X_MIN, math.min(C.X_MAX,
            math.floor(C.X_MIN + (slot + 0.5) * span / #C.PETS + jitter + 0.5)))
        pet.y = pet.lane + random(-C.LANE_DRIFT, C.LANE_DRIFT)
        pet.direction = random(0, 1) == 0 and "l" or "r"
        begin_phase(pet, random, (index - 1) % 4 < 2 and "run" or "idle", 0)
        render_pose(pet, 0)
    end
    created, last_ms = true, 0
    return pets
end

function M.create(seed)
    if created then return pets, false end
    M.restart(seed)
    return pets, true
end

function M.update(now_ms)
    assert(type(now_ms) == "number" and now_ms == now_ms and now_ms >= 0
        and now_ms < math.huge, "scene time must be finite nonnegative milliseconds")
    if not created or now_ms < last_ms then return false end
    for index = 1, active_count do
        local pet = pets[index]
        -- 以各自的截止时间消耗所有已过阶段；只保留最终可见姿态。
        -- 每只宠物独立随机源，所以补帧与逐帧推进的随机结果一致。
        while now_ms >= pet.end_ms do
            local deadline = pet.end_ms
            if pet.phase == "run" then
                pet.x, pet.y = pet.target_x, pet.target_y
                begin_phase(pet, generators[index], "idle", deadline)
            else
                pet.x, pet.y = pet.from_x, pet.from_y
                begin_phase(pet, generators[index], "run", deadline)
            end
        end
        render_pose(pet, now_ms)
    end
    local changed = now_ms ~= last_ms
    last_ms = now_ms
    return changed
end

function M.trigger_run(id, now_ms)
    -- 点击也使用 update() 的绝对时间。先校验，避免无效点击推进其他宠物。
    if not created or type(id) ~= "number" or id % 1 ~= 0
        or id < 1 or id > active_count then return false end
    if type(now_ms) ~= "number" or now_ms ~= now_ms or now_ms < last_ms
        or now_ms < 0 or now_ms >= math.huge then return false end
    -- 从点击时刻的真实插值位置继续跑；正在跑动时也可以重新选择目标。
    M.update(now_ms)
    local pet = pets[id]
    begin_phase(pet, generators[id], "run", now_ms)
    render_pose(pet, now_ms)
    return true
end

function M.set_count(count, now_ms)
    -- 数量和时钟都有效才推进场景；无效操作不改变时间或随机源。
    if not created or type(count) ~= "number" or count % 1 ~= 0
        or count < 1 or count > #pets then return false end
    if type(now_ms) ~= "number" or now_ms ~= now_ms or now_ms < last_ms
        or now_ms < 0 or now_ms >= math.huge then return false end
    M.update(now_ms)
    for index = active_count + 1, count do
        local pet = pets[index]
        -- 隐藏时坐标冻结。恢复时从原地开始一个完整阶段，不追赶隐藏时间。
        begin_phase(pet, generators[index], pet.phase, now_ms)
        render_pose(pet, now_ms)
    end
    active_count = count
    quality = count <= C.HQ_MAX_COUNT and "high" or "low"
    for index, pet in ipairs(pets) do
        -- 切档只改表现字段，不重新抽取随机数、不重启仍可见宠物的跑动轨迹。
        pet.quality = index <= active_count and quality or "low"
        if index <= active_count then render_pose(pet, now_ms) end
    end
    return true
end

function M.count()
    return active_count
end

function M.quality()
    return quality
end

function M.pets()
    return pets
end

function M.summary()
    local result = {run = 0, idle = 0, active = active_count, quality = quality}
    for index = 1, active_count do
        local pet = pets[index]
        result[pet.phase] = result[pet.phase] + 1
    end
    return result
end

return M
