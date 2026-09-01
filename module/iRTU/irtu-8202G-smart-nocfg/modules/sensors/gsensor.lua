-- DA221 运动检测模块（替代原 da267 计步+运动检测，DA221 仅支持运动检测）
-- 对外接口：
--   gsensor.init()              - 初始化（经 exvib 库配置 DA221，WAKEUP2 中断）
--   gsensor.on_vibration(cb,i)  - 注册震动回调（主循环用于发布 MOTION_EVENT）
--   gsensor.is_moving()         - 查询是否运动中（震动后 10s 内返回 true，超时恢复静止）
--   gsensor.set_motion_state(b) - 强制设置运动状态（低功耗震动唤醒时用）
--   gsensor.read_xyz()          - 主动读取三轴加速度（单位 g）
--   gsensor.read_raw_xyz()      - 主动读取三轴原始计数值（12 位有符号，-2048~2047）
--   gsensor.get_last_xyz()      - 获取最近一次震动中断采集的三轴快照（表或 nil）
--   gsensor.is_xyz_fresh(ms)    - 快照是否在指定毫秒数内（默认 1000ms），用于判断"刚刚震过"
--   gsensor.stream_start()      - 开启 25Hz 三轴原始数据流式采样（GNSS 开启期间调用）
--   gsensor.stream_stop()       - 停止流式采样并清空缓冲（GNSS 关闭时调用）
--   gsensor.get_stream_data(n)  - 取最近 n 个样本（默认125=5秒）拼好的字节串与实际样本数
-- 说明：中断回调内不直接做 I2C 读写（中断上下文禁止耗时/阻塞操作），
--       仅发布 GSENSOR_XYZ_CAPTURE 事件，由 xyz_capture_task 协程执行读取并存快照。
local gsensor = {}

-- DA221 中断脚：WAKEUP2（需与硬件一致）
local INT_PIN = gpio.WAKEUP2

-- ====== 25Hz 流式采样（GNSS 开启期间采集，供 TLV 1293 上报） ======
local STREAM_HZ = 25              -- 采样率（每秒 25 次）
local STREAM_INTERVAL_MS = 40     -- 采样间隔(ms) = 1000/25
local STREAM_BUFFER_MAX = 130     -- 缓冲容量：5 秒=125 样本 + 少量余量
-- 每样本 6 字节：x/y/z 各 2 字节有符号 int16 大端（网络字节序），样本按时间正序排列

-- 模块状态
local state = {
    initialized = false,       -- 是否初始化完成
    vibration_callback = nil,  -- 震动回调（由主循环注册）
    last_vibration_time = 0,   -- 上次震动时间戳（用于 2000ms 限流）
    vibration_interval = 2000, -- 震动回调限流间隔(ms)：2秒内连续震动只算一次

    is_moving = false,         -- 当前是否运动中
    last_motion_time = 0,      -- 上次运动时间戳（用于超时恢复）
    motion_timeout = 10,       -- 运动超时(秒)：超过此时间无震动自动恢复静止
    pending_gps = false,       -- 震动唤醒待处理标志：置位后下一次上报强制走 GPS

    exvib = nil,               -- DA221 驱动库句柄（init 时缓存）
    last_xyz = nil,            -- 最近一次中断采集的三轴快照 {x,y,z,raw_x,raw_y,raw_z,ts}
    xyz_capture_on = false,    -- 采集任务运行标志

    stream_on = false,         -- 25Hz 流式采样开关（GNSS 开启期间为 true）
    stream_buffer = {},        -- 流式采样滚动缓冲：每个元素为 6 字节打包样本（x/y/z int16 大端）
    stream_task_on = false,    -- 流式采样任务运行标志
}

local function interrupt_handler()
    if not state.initialized then return end

    local now = os.time()

    -- 【测试日志】每次硬件中断触发都打印（含被 2s 限流挡掉的），
    -- 用于标定震动灵敏度：马路上实测看此日志出现频率即可判断是否触发
    log.info("gsensor", "INT触发 距上次震动", (now - state.last_vibration_time), "s")

    if state.vibration_callback then
        local last_time = state.last_vibration_time
        local interval = state.vibration_interval
        if now - last_time >= (interval / 1000) then
            state.last_vibration_time = now

            if not state.is_moving then
                state.is_moving = true
                log.info("gsensor", "状态切换: 静止 → 运动中")
            end
            state.last_motion_time = now

            -- 关键：震动唤醒后（可能刚从低功耗恢复）网络恢复需要时间，
            -- 必须延长运动有效期到60秒，否则 is_moving 会在等网络期间超时变 false，
            -- 导致智能模式震动上报走基站而非 GPS
            state.motion_timeout = 60
            -- 震动触发：标记待处理 GPS，确保本次上报走 GPS（不依赖 is_moving 时序）
            state.pending_gps = true

            -- 请求采集三轴快照：中断上下文不做 I2C，仅发布事件，由采集任务读取
            -- （跟随限流：2s 内连续震动只采集一次，避免频繁读 I2C）
            sys.publish("GSENSOR_XYZ_CAPTURE")

            state.vibration_callback()
        end
    end
end

-- 三轴快照采集任务：订阅 GSENSOR_XYZ_CAPTURE 事件（由中断回调发布），
-- 在协程上下文中执行 I2C 读取（中断上下文不允许 I2C），结果存 state.last_xyz。
-- 200ms 超时轮询，close() 时随 initialized=false 退出。
local function xyz_capture_task()
    log.info("gsensor", "三轴快照采集任务启动")
    while state.initialized do
        local got = sys.waitUntil("GSENSOR_XYZ_CAPTURE", 200)
        if got and state.initialized and state.exvib then
            -- 中断触发后稍作延时，等传感器数据稳定再读
            sys.wait(50)
            local ok, x, y, z, rx, ry, rz = pcall(state.exvib.read_xyz, state.exvib)
            if ok and x then
                state.last_xyz = {
                    x = x, y = y, z = z,
                    raw_x = rx, raw_y = ry, raw_z = rz,
                    ts = os.time(),
                }
                log.info("gsensor", "XYZ快照 x", string.format("%.3f", x), "y", string.format("%.3f", y),
                    "z", string.format("%.3f", z), "raw", rx, ry, rz)
            else
                log.warn("gsensor", "三轴读取失败:", ok, x)
            end
        end
    end
    state.xyz_capture_on = false
    log.info("gsensor", "三轴快照采集任务退出")
end

-- 25Hz 流式采样任务：GNSS 开启期间（stream_on=true）持续读取 DA221 原始三轴，
-- 每个样本打包 6 字节（x/y/z 各 2 字节有符号 int16 大端）存入滚动缓冲，
-- 上报时通过 get_stream_data 取最近 125 个样本（5 秒）。
-- 用 mcu.ticks 做时间片调度，自动补偿 I2C 读取耗时，保证实际采样率贴近 25Hz。
local function stream_task()
    log.info("gsensor", "25Hz 流式采样任务启动")
    local next_tick = mcu.ticks()
    while true do
        if state.stream_on and state.initialized and state.exvib then
            local ok, _, _, _, rx, ry, rz = pcall(state.exvib.read_xyz, state.exvib)
            if ok and rx ~= nil then
                table.insert(state.stream_buffer, string.pack(">i2i2i2", rx, ry, rz))
                if #state.stream_buffer > STREAM_BUFFER_MAX then
                    table.remove(state.stream_buffer, 1)
                end
            end
            -- 时间片调度：固定 40ms 节拍；I2C 耗时自动补偿；
            -- 落后超过 1 秒（如刚从待机恢复）重新对齐节拍，避免连发追赶
            next_tick = next_tick + STREAM_INTERVAL_MS
            local wait_ms = next_tick - mcu.ticks()
            if wait_ms > STREAM_INTERVAL_MS then
                wait_ms = STREAM_INTERVAL_MS
            elseif wait_ms < -1000 then
                next_tick = mcu.ticks()
                wait_ms = 0
            elseif wait_ms < 0 then
                wait_ms = 0
            end
            sys.wait(wait_ms)
        else
            sys.wait(200)
            next_tick = mcu.ticks()
        end
    end
end

function gsensor.init()
    if state.initialized then
        return true
    end

    -- 加载 DA221 驱动库（exvib），open(1)=微小震动检测（2g量程，车辆行驶/路面振动检测，已定制 ODR 250Hz + 阈值0x20）
    local ok, exvib = pcall(require, "exvib")
    if not ok or not exvib then
        log.error("gsensor", "加载 exvib 库失败")
        return false
    end
    state.exvib = exvib

    -- open 内部为异步初始化（供电+I2C+寄存器），等待其完成后再配中断
    exvib.open(1)
    sys.wait(300)

    -- 配置 WAKEUP2 中断：震动时 DA221 INT 脚产生中断，进入 interrupt_handler
    gpio.debounce(INT_PIN, 100)
    gpio.setup(INT_PIN, interrupt_handler)

    state.initialized = true
    state.last_vibration_time = os.time()
    log.info("gsensor", "DA221 运动检测初始化成功")

    -- 启动三轴快照采集任务（订阅 GSENSOR_XYZ_CAPTURE，读到数据存 state.last_xyz）
    if not state.xyz_capture_on then
        state.xyz_capture_on = true
        sys.taskInit(xyz_capture_task)
    end

    -- 启动 25Hz 流式采样任务（常驻协程，由 stream_on 控制采样/待机）
    if not state.stream_task_on then
        state.stream_task_on = true
        sys.taskInit(stream_task)
    end
    return true
end

-- 低功耗唤醒后恢复中断（drv_lowpower 调用），确保震动仍能触发
function gsensor._restore_interrupt()
    if not state.initialized then return end
    gpio.debounce(INT_PIN, 100)
    gpio.setup(INT_PIN, interrupt_handler)
    log.info("gsensor", "中断已恢复")
end

function gsensor.close()
    if not state.initialized then return end

    -- 先清标志让采集任务退出（waitUntil 200ms 超时后检测到退出）
    state.initialized = false
    state.last_xyz = nil

    gpio.setup(INT_PIN, 0)
    local ok, exvib = pcall(require, "exvib")
    if ok and exvib and exvib.close then
        exvib.close()
    end

    log.info("gsensor", "已关闭")
end

-- 注册震动回调：震动（过限流）时触发 cb，主循环用它发布 MOTION_EVENT
function gsensor.on_vibration(callback, interval)
    state.vibration_callback = callback
    if interval then
        state.vibration_interval = interval
    end
end

function gsensor.is_moving()
    if not state.initialized then return false end

    if state.is_moving then
        local now = os.time()
        if now - state.last_motion_time >= state.motion_timeout then
            state.is_moving = false
            log.info("gsensor", "状态切换: 运动中 → 静止（超时", state.motion_timeout, "秒无震动）")
        end
    end

    return state.is_moving
end

function gsensor.set_motion_timeout(timeout)
    if timeout and timeout > 0 then
        state.motion_timeout = timeout
        log.info("gsensor", "运动超时时间设置为:", timeout, "秒")
    end
end

function gsensor.set_motion_state(moving, timeout)
    state.is_moving = moving
    if moving then
        state.last_motion_time = os.time()
        if timeout and timeout > 0 then
            -- 临时延长运动有效期（如震动唤醒后网络恢复需要时间，默认10秒不够）
            state.motion_timeout = timeout
        end
        -- 震动唤醒：标记待处理 GPS（低功耗唤醒路径也强制本次上报走 GPS）
        state.pending_gps = true
    end
    log.info("gsensor", "运动状态强制设置为:", moving and "运动中" or "静止")
end

-- 消费待处理 GPS 标志：返回 true 表示本次上报应强制走 GPS（读取后清除）
function gsensor.consume_pending_gps()
    local pending = state.pending_gps
    state.pending_gps = false
    return pending
end

-- 主动读取三轴加速度（单位 g）。注意：此接口直接读 I2C，只能在协程上下文调用
-- （如在 sys.taskInit 任务或主循环 waitUntil 分支中调用，不能在 gpio 中断回调中调用）。
-- 返回 x, y, z；未初始化返回 nil。
function gsensor.read_xyz()
    if not state.initialized or not state.exvib then return nil end
    local x, y, z = state.exvib.read_xyz()
    return x, y, z
end

-- 主动读取三轴原始计数值（12 位有符号，-2048~2047）。同样只能在协程上下文调用。
-- 返回 raw_x, raw_y, raw_z；未初始化返回 nil。
function gsensor.read_raw_xyz()
    if not state.initialized or not state.exvib then return nil end
    local _, _, _, rx, ry, rz = state.exvib.read_xyz()
    return rx, ry, rz
end

-- ====== 25Hz 流式采样接口（GNSS 开启期间采集，作为 TLV 1293 上报） ======

-- 开启流式采样（清空缓冲从头采）。GNSS 开启时调用。
function gsensor.stream_start()
    state.stream_buffer = {}
    state.stream_on = true
    log.info("gsensor", "流式采样开启: 25Hz, 缓冲上限", STREAM_BUFFER_MAX, "样本")
end

-- 停止流式采样并清空缓冲。GNSS 关闭时调用。
function gsensor.stream_stop()
    state.stream_on = false
    state.stream_buffer = {}
    log.info("gsensor", "流式采样停止, 缓冲已清空")
end

-- 取最近 count 个样本（默认 125 = 5 秒）拼接为字节串。
-- 数据格式：每样本 6 字节，按 x,y,z 顺序各 2 字节有符号 int16 大端（网络字节序），
-- 样本按时间正序排列；125 个样本共 750 字节。
-- 采样数不足 count 时返回实际数量（如刚开启采样的首次上报）。
-- 返回 (data, actual_count)；未开启或无数据返回 ("", 0)。
function gsensor.get_stream_data(count)
    count = count or 125
    local buf = state.stream_buffer
    local n = math.min(count, #buf)
    if n <= 0 then return "", 0 end
    local out = {}
    for i = #buf - n + 1, #buf do
        out[#out + 1] = buf[i]
    end
    return table.concat(out), n
end

-- 获取最近一次震动中断采集的三轴快照（由 xyz_capture_task 写入）。
-- 返回表 {x,y,z, raw_x,raw_y,raw_z, ts}（ts 为 os.time() 秒级时间戳），无快照返回 nil。
-- 适用于跌倒检测/姿态判断：震动瞬间的数据由中断自动采集，此处随时可取。
function gsensor.get_last_xyz()
    return state.last_xyz
end

-- 判断最近一次快照是否在 fresh_ms 毫秒内（默认 1000ms）。
-- 返回 true 表示"刚刚发生过有效震动并采集到了三轴数据"。
function gsensor.is_xyz_fresh(fresh_ms)
    local snap = state.last_xyz
    if not snap then return false end
    local age_ms = (os.time() - snap.ts) * 1000
    return age_ms <= (fresh_ms or 1000)
end

function gsensor.get_status()
    return {
        initialized = state.initialized,
        is_moving = state.is_moving,
        last_motion_time = state.last_motion_time,
        motion_timeout = state.motion_timeout,
    }
end

return gsensor
