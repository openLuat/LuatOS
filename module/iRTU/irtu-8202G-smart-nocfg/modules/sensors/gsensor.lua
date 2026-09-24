-- 加速度计运动检测模块（多型号自适应：DA221/exvib 与 DA267/exs_da267 双驱动）
-- 驱动装配与标度归一化在本模块内部完成（见下方"加速度计驱动装配"段），
-- 不额外拆出自造的适配库 —— lib/ 只存放合宙官方扩展库。
--
-- 对外接口（跨型号保持不变）：
--   gsensor.init()              - 初始化（按 profile 装配驱动，注册震动中断或轮询降级）
--   gsensor.on_vibration(cb,i)  - 注册震动回调（主循环用于发布 MOTION_EVENT）
--   gsensor.is_moving()         - 查询是否运动中（震动后 N 秒内返回 true，超时恢复静止）
--   gsensor.set_motion_state(b) - 强制设置运动状态（低功耗震动唤醒时用）
--   gsensor.read_xyz()          - 主动读取三轴加速度（单位 g）
--   gsensor.read_raw_xyz()      - 主动读取三轴原始计数值（12 位有符号，-2048~2047）
--   gsensor.get_last_xyz()      - 获取最近一次震动中断采集的三轴快照（表或 nil）
--   gsensor.is_xyz_fresh(ms)    - 快照是否在指定毫秒数内（默认 1000ms），用于判断"刚刚震过"
--   gsensor.stream_start()      - 开启 20Hz 三轴原始数据流式采样（GNSS 开启期间调用）
--   gsensor.stream_stop()       - 停止流式采样并清空缓冲（GNSS 关闭时调用）
--   gsensor.get_stream_data(n)  - 取最近 n 个样本（默认200=10秒）按 12bit 紧凑编码拼成字节串
--   gsensor.consume_pending_gps()- 消费"待处理 GPS"标志（震动后强制本次上报走 GPS）
--   gsensor.get_status()        - 获取模块状态
-- 说明：中断回调内不直接做 I2C 读写（中断上下文禁止耗时/阻塞操作），
--       仅发布 GSENSOR_XYZ_CAPTURE 事件，由 xyz_capture_task 协程执行读取并存快照。
local gsensor = {}

local config = require "config"

-- 板级配置（T0 已识别）
local GS_CFG = (config.BOARD and config.BOARD.gsensor) or { impl = "none" }

-- ==================== 加速度计驱动装配（板级差异收敛于此） ====================
-- 按 profile.gsensor.impl 选择底层官方扩展库，向本模块暴露统一接口：
--   drv.int_capable       是否具备中断能力（false 时上层退化为轮询判定）
--   drv.setup()           供电/I2C/寄存器配置 + 中断登记（必须在协程中调用）
--   drv.set_callback(fn)  注册中断回调（fn 在中断上下文执行，内部禁止 I2C）
--   drv.read_g()          x,y,z（单位 g）
--   drv.read_raw()        rx,ry,rz（12bit 原始值，-2048~2047）
--   drv.read_all()        x,y,z,rx,ry,rz（单次 I2C 同时取）
--   drv.close()
--
-- ★ 跨型号标度一致性（重要）
-- TLV 1301 / 1303 上报的是 12bit "原始值"，而两组库的原始值标度**不一致**：
--   - exvib（DA221，2g）：read_xyz() 的第 4~6 个返回值即硬件 12bit 原始值
--   - exs_da267 v1.1：get_data() 只返回 g 值，库内灵敏度为 32768/range（2g → 16384），
--     与 DA221 口径（2g → 1024）相差 16 倍
-- 若各按自身标度上云，同一物理加速度在 8202 与 8201G/H 上会呈现不同数值，平台侧解读失真。
-- 因此本层对 da267 做归一化：raw = clamp(round(g × raw_per_g))，raw_per_g 由 profile 提供。

local function clamp12(v)
    v = math.floor(v + 0.5)
    if v > 2047 then return 2047 end
    if v < -2048 then return -2048 end
    return v
end

-- DA221 / exvib（Air8202，保持原行为不变）
local function create_exvib_driver(gs)
    local drv = { impl = "exvib", int_capable = gs.int_pin ~= nil }
    local lib = require "exvib"

    function drv.setup()
        -- exvib 自行管理 I2C 总线与传感器供电脚（库内按 780 分支处理），此处不重复设置。
        -- open 内部是异步初始化（sys.taskInit），调用后需等其完成再配中断。
        lib.open(1)   -- 1 = 微小震动检测（2g；库内已定制 ODR 250Hz + 阈值 0x20）
        sys.wait(300)
        log.info("gsensor", "exvib 初始化完成")
        return true
    end

    function drv.set_callback(cb)
        if not gs.int_pin then
            log.warn("gsensor", "exvib 未配置中断引脚，震动中断不可用")
            return false
        end
        gpio.debounce(gs.int_pin, 100)
        gpio.setup(gs.int_pin, cb)
        return true
    end

    function drv.read_g()
        local x, y, z = lib.read_xyz()
        return x, y, z
    end

    -- read_xyz 第 4~6 个返回值即硬件 12bit 原始值，直接透传（与改动前完全一致）
    function drv.read_raw()
        local _, _, _, rx, ry, rz = lib.read_xyz()
        return rx, ry, rz
    end

    function drv.read_all()
        return lib.read_xyz()   -- x,y,z,rx,ry,rz（单次 I2C）
    end

    function drv.close()
        lib.close()
    end

    -- 板级支撑脚幂等使能（功耗档切换会复位引脚配置，见 da267 分支的说明）。
    -- exvib 自行管理 I2C 与供电脚，此处仅在板级显式声明了 power_pin 时兜底重拉。
    function drv.assert_support()
        if gs.power_pin then gpio.setup(gs.power_pin, 1, gpio.PULLUP) end
    end

    return drv
end

-- DA267 / exs_da267（Air8201G / 8201H）
local function create_da267_driver(gs)
    local drv = { impl = "exs_da267", int_capable = gs.int_pin ~= nil }
    local lib = require "exs_da267"
    local raw_per_g = gs.raw_per_g or 1024   -- 协议基线：1g → 1024 LSB

    local range    = gs.range_g or 2
    local setup_ok = false   -- lib.setup 曾经成功过（决定掉电后能否重新配置）
    local fail_cnt = 0       -- 连续读取失败计数
    local last_fix = 0       -- 上次自愈的 mcu.ticks（限流，避免 20Hz 下刷屏）
    local last_cyc = 0       -- 上次断电重上电的 mcu.ticks（更长限流）
    local CYCLE_GAP_MS = 30000   -- 断电重上电最小间隔：避免频繁切断 V_BCKP
    local last_cfg = 0       -- 上次重配寄存器（tier-3）的 mcu.ticks
    local CFG_GAP_MS = 10000 -- 重配寄存器最小间隔（每次约 10 笔 I2C，不宜频繁）
    local READ_RETRY = 3     -- 单次读取的重试次数（骑过间歇性传输异常）
    local stat_ok, stat_fail = 0, 0   -- 累计成功/失败计数（用于量化"间歇"程度，随自愈日志输出）

    -- 按官方语义写一个输出脚，并**校验是否真的写成功**。
    -- 官方 gpio.setup 文档：输出模式成功时返回"设置电平的闭包"；失败（引脚越界/被占用）返回 nil。
    -- ★ 这个返回值就是区分下列两种根因的决定性证据：
    --   ① 引脚被低功耗配置/PMU 收走 → 重配失败(nil) → 再怎么重拉都无用
    --   ② 引脚没问题，是总线被器件钳住 → 重配成功但仍超时 → 需断电复位器件
    local function set_out(pin, level, pull, why)
        local r
        if pull then r = gpio.setup(pin, level, pull) else r = gpio.setup(pin, level) end
        if r == nil or r == false then
            log.error("gsensor", "gpio.setup 失败(pin=", pin, " level=", level,
                ") —— 该脚疑似已被低功耗配置收走，Lua 层无法重配（", why, "）")
            return false
        end
        return true
    end

    --[[
    幂等重新拉高「板级 I2C 支撑脚」：外部上拉源 + 传感器供电。

    ★ 背景（2026-09-17 实机）：
      · 已证实：本板 I2C1 的上拉确实由 GPIO28 控制 —— 加 `gpio.setup(28,1)` **之前**
        全地址超时、DA267 初始化失败；**之后**初始化成功。
      · 已证实：pm.power(pm.WORK_MODE, n) 切功耗档会**复位该脚的中断注册**
        （lowpower/drv_lowpower.lua 专为此写了 `_restore_interrupt()`）。
      · **未证实**：切功耗档是否会丢失 **AGPIO 的输出电平**。官方说明 AGPIO 在低功耗下
        可保持电平，且实机"重拉 GPIO28 后仍全部超时"，故本函数**不能**当成该故障的根因。
        保留它作为**幂等保险**（同时覆盖"引脚被第三方复位"这类未知情形）。

    纯 gpio 写、无阻塞，可在任意上下文调用。
    ]]
    -- 支撑脚清单：优先取板级声明的 `support_pins`（I2C1 上**全部**器件的使能脚）；
    -- 未声明时回退为「上拉源 + 供电」两脚（8201H / 8202 现状不变）。
    -- 动机：I2C1 上不止一个器件，**任一未上电其 ESD 二极管就会把 SDA/SCL 钳在低位**
    -- → 主控只看到"传输超时"(-13) 而非 NACK，且上拉再强也无用。
    local support_pins = {}
    if type(gs.support_pins) == "table" then
        for _, pin in ipairs(gs.support_pins) do
            if pin then support_pins[#support_pins + 1] = pin end
        end
    else
        if gs.i2c_pullup_pin then support_pins[#support_pins + 1] = gs.i2c_pullup_pin end
        if gs.power_pin then support_pins[#support_pins + 1] = gs.power_pin end
    end

    local function assert_support(why)
        why = why or "使能支撑脚"
        for _, pin in ipairs(support_pins) do
            set_out(pin, 1, gpio.PULLUP, why)
        end
    end

    -- 重建 I2C 控制器（官方接口 i2c.close + i2c.setup）
    -- ★ 这是**实测最轻量、最有效**的一步（2026-09-18 实机长日志）：
    --   故障期间 117 次读取全部失败，错误码一律 -6「传输过程发生异常」（**不是**超时）；
    --   而库内 `lib.setup()` 里的 `i2c.close()`+`i2c.setup(SLOW)` 一跑，
    --   紧接着就是 `初始化完成，量程: 2 g` ✅ —— 即**控制器一重建就恢复**。
    --   → 器件是活的、线路是通的，坏的是**控制器内部状态**
    --     （疑似上一次传输未正常收尾，之后控制器持续返回"忙/异常"）。
    --   故失败时**第一优先**做这件事；且只碰 i2c、不动 GPIO（避免重设上拉脚造成额外扰动）。
    local last_reinit = 0
    local REINIT_GAP_MS = 200
    local function reinit_bus(announce)
        local now = mcu.ticks()
        if now - last_reinit < REINIT_GAP_MS then return end
        last_reinit = now
        local bus = gs.i2c_id or 1
        i2c.close(bus)
        i2c.setup(bus, i2c.SLOW)
        if announce then
            log.warn("gsensor", "I2C 读取失败 → 重建 I2C 控制器（i2c.close + i2c.setup）")
        end
    end

    local function do_lib_setup()
        return lib.setup({
            i2c_id              = gs.i2c_id or 1,
            addr                = gs.addr or 0x26,
            int_pin             = gs.int_pin,   -- nil 时库内不登记中断 → 上层轮询降级
            range               = range,
            motion_enable       = true,
            motion_window       = 60,
            motion_threshold    = 5,
            step_counter_enable = false,
        })
    end

    --[[
    运行期自愈。恢复顺序按"代价由低到高"，且**失败路径不阻塞**，交给 50ms 后的下一拍验证：

      ⓪ 重建 I2C 控制器      —— 在 read_g 里直接调用（见 reinit_bus）：**实测最有效**、最轻量
      ① 重拉支撑脚           —— 覆盖"引脚被功耗档切换/外部复位"
      ② 给传感器断电重上电   —— 覆盖"器件失电/闩锁后 ESD 钳位总线"（需 profile 开启 power_cycle_recover）
      ③ 重配寄存器           —— 覆盖"器件掉过电、配置丢失"

    ⚠️ 已修正的旧叙事：曾把该故障归因为"器件失电 → ESD 二极管钳位 → 超时(-13)"，
       但 2026-09-18 实机长日志显示错误码恒为 **-6「传输过程发生异常」**（0 次超时），
       且 `i2c.close()+i2c.setup()` 一跑就恢复 → **器件与线路都是好的**，属控制器状态问题。
    ]]
    local function heal(reason)
        local now = mcu.ticks()
        if now - last_fix < 2000 then return end
        last_fix = now

        assert_support(reason)

        if fail_cnt >= 3 then
            -- ② 断电重上电（长限流；需 profile 开启 `power_cycle_recover`，8201G 已开启）
            -- 本板 GPIO24 = G-Sensor 供电（V_BCKP，2026-09-18 用户确认）。
            -- 注：本故障中并非必需（控制器重建即可恢复），保留作为最后一道兜底。
            if gs.power_cycle_recover == true and gs.power_pin and (now - last_cyc) >= CYCLE_GAP_MS then
                last_cyc = now
                log.warn("gsensor", "I2C 连续失败", fail_cnt, "次 → 给传感器断电重上电（pin=",
                    gs.power_pin, "，间隔限", CYCLE_GAP_MS / 1000, "s）")
                gpio.setup(gs.power_pin, 0, gpio.PULLUP)
                sys.wait(200)
                assert_support("断电后重新上电")
                sys.wait(100)
            end

            -- ③ 重配寄存器（10s 限流）
            -- ★ 实机证据（2026-09-18 上一份日志）：故障期间唯一**确实把总线救回来**的动作
            --   就是库内 `lib.setup()`（= i2c.close+setup **并重写一批寄存器**）。
            --   而单纯 i2c.close+setup 连做 15 次都无效 → 寄存器状态才是关键。
            if setup_ok and (now - last_cfg) >= CFG_GAP_MS then
                last_cfg = now
                log.warn("gsensor", "重新配置传感器寄存器（", reason, "）")
                local s_ok, s_r = pcall(do_lib_setup)
                if not (s_ok and s_r) then
                    log.error("gsensor", "重配传感器失败（供电/总线仍不可用）:", tostring(s_r))
                end
            end
        else
            log.warn("gsensor", "I2C 读取失败 → 重新拉高板级支撑脚（", reason,
                "；累计 成功", stat_ok, " 失败", stat_fail, "）")
        end
        -- ⚠️ 此处**不清零 fail_cnt**：只有"读到有效数据"才清零（见 read_g）。
        --    原先在此清零是个设计缺陷 —— tier-1 每 2s 跑一次就会把计数抹掉，
        --    导致 fail_cnt 永远到不了 3，**tier-2/3 从此再也触发不了**。
        --    （实机 2026-09-18 复现：`断电重上电`/`重新配置传感器寄存器` 均为 0 次。）
    end

    -- 供低功耗模块在切功耗档后调用（功耗档切换会复位引脚配置）
    drv.assert_support = assert_support

    function drv.setup()
        -- ① 板级 I2C 支撑脚（上拉源 + 供电），必须先于任何 I2C 通信
        -- 8201G：I2C1_SDA / I2C1_SCL 的 10k 上拉（R16 / R17）由 **GPIO28（AGPIO8 / PIN78）** 使能；
        --        DA267 供电/电平使能 = GPIO24（AGPIO4，控制 V_BCKP）。
        -- ⚠️ 不使能则 SDA/SCL 无上拉，整条总线无器件应答
        --    （实机已复现：i2c.scan 全地址"传输超时"、DA267 芯片ID 校验失败）。
        assert_support("开机初始化")
        sys.wait(50)   -- 等上拉与供电建立
        log.info("gsensor", "板级 I2C1 支撑脚已全部拉高（上拉源=", tostring(gs.i2c_pullup_pin),
            " 供电=", tostring(gs.power_pin),
            " 全量清单=", table.concat(support_pins, ","), "）")

        local ok = do_lib_setup()
        if not ok then
            log.error("gsensor", "exs_da267.setup 失败（供电/I2C/芯片ID 校验不通过）")
            return false
        end
        setup_ok = true

        log.info("gsensor", "exs_da267 初始化完成（range=", range, "g, 中断脚=",
            tostring(gs.int_pin), ", 归一化 raw_per_g=", raw_per_g, "）")
        return true
    end

    function drv.set_callback(cb)
        lib.set_callback(cb)
        if not gs.int_pin then
            log.warn("gsensor", "exs_da267 未配置中断引脚，震动中断不可用（轮询降级）")
            return false
        end
        return true
    end

    function drv.read_g()
        -- 读取层短重试：实机（2026-09-18）显示该故障是**间歇性**的 ——
        -- 同一时刻有的读成功、有的返回 -6「传输过程发生异常」，
        -- 且单纯重建控制器(i2c.close+setup)无效。故在读取层做几次短退避重试，
        -- 可骑过短时干扰，避免上层看到数据空洞。
        local d
        for attempt = 1, READ_RETRY do
            d = lib.get_data()
            if d then break end
            if attempt < READ_RETRY then sys.wait(2) end
        end

        if d then
            stat_ok = stat_ok + 1
            fail_cnt = 0
            return d.x, d.y, d.z
        end

        stat_fail = stat_fail + 1
        fail_cnt = fail_cnt + 1
        -- ⓪ 第一优先：重建 I2C 控制器（最轻量；见 reinit_bus 注释）
        reinit_bus(fail_cnt == 1)
        -- ①~③ 其余自愈（重拉支撑脚 / 断电重上电 / 重配寄存器），限流 2s
        heal("运行期读取失败")
        return nil
    end

    -- 归一化：把库返回的 g 值换算为与 8202 基线一致的 12bit 原始值标度
    function drv.read_raw()
        local x, y, z = drv.read_g()
        if x == nil then return nil end
        return clamp12(x * raw_per_g), clamp12(y * raw_per_g), clamp12(z * raw_per_g)
    end

    function drv.read_all()
        local x, y, z = drv.read_g()
        if x == nil then return nil end
        return x, y, z,
            clamp12(x * raw_per_g), clamp12(y * raw_per_g), clamp12(z * raw_per_g)
    end

    function drv.close()
        lib.close()
        if gs.power_pin then
            gpio.setup(gs.power_pin, 0, gpio.PULLUP)
        end
    end

    return drv
end

-- 无运动感知能力（unknown 兜底）
local function create_none_driver()
    return {
        impl         = "none",
        int_capable  = false,
        setup        = function() return true end,
        set_callback = function() return false end,
        read_g       = function() return nil end,
        read_raw     = function() return nil end,
        read_all     = function() return nil end,
        close        = function() end,
        assert_support = function() end,   -- 无外设，空实现（保持驱动接口一致）
    }
end

-- 按 profile 装配驱动实例
local function create_driver(gs)
    gs = gs or {}
    if gs.impl == "exvib" then
        return create_exvib_driver(gs)
    elseif gs.impl == "exs_da267" then
        return create_da267_driver(gs)
    end
    log.warn("gsensor", "无可用加速度计实现(impl=", tostring(gs.impl), ")，运动感知已禁用")
    return create_none_driver()
end

--[[
Setup 失败时的一次性 I2C 诊断（每次开机最多一趟）

目的：一次开机就能区分失败原因，避免反复试错：
  ① 全部地址无应答          → 传感器没上电（power_pin 不对）或总线不通（SDA/SCL 未复用/缺上拉）
  ② 只有 0x27 有应答        → 总线上是模组内置传感器（EGG 口径），板载 DA267 不在
  ③ 0x26 有应答但 ID ≠ 0x13 → 型号/地址判断有误
做法（全部为官方接口）：
  · i2c.scan(bus)          官方开发期扫描工具，会把所有应答地址直接打到日志
  · i2c.send + i2c.recv    读 DA267 芯片ID 寄存器（0x01，期望 0x13），与 exs_da267 库内用法一致
]]
-- 探测单个地址：读芯片ID 寄存器 0x01（DA267 期望 0x13），与 exs_da267 库内用法一致
local function probe_addr(bus, speed, a, tag)
    i2c.setup(bus, speed)
    i2c.send(bus, a, 0x01, 1)
    local d = i2c.recv(bus, a, 1)
    if d and #d == 1 then
        log.warn("gsensor", string.format("  [%s] 0x%02X 芯片ID(0x01)=0x%02X%s", tag, a, string.byte(d),
            (string.byte(d) == 0x13) and " ★DA267，正常" or " （非 DA267）"))
        return true
    end
    log.warn("gsensor", string.format("  [%s] 0x%02X 无应答/超时", tag, a))
    return false
end

local function diag_i2c(gs)
    local bus = gs.i2c_id or 1
    local other = (bus == 1) and 2 or 1
    local addr = gs.addr or 0x26

    log.warn("gsensor", "===== 加速度计 I2C 诊断 =====")
    log.warn("gsensor", "配置: impl=", tostring(gs.impl), " bus=", bus,
        " addr=0x" .. string.format("%02X", addr),
        " int_pin=", tostring(gs.int_pin), " power_pin=", tostring(gs.power_pin),
        " i2c_pullup_pin=", tostring(gs.i2c_pullup_pin),
        " support_pins=", (type(gs.support_pins) == "table")
            and table.concat(gs.support_pins, ",") or "nil",
        " range=", tostring(gs.range_g), "g")

    -- ① 目标地址：慢速
    probe_addr(bus, i2c.SLOW, addr, "bus" .. bus .. "/SLOW")
    -- ② 目标地址：快速 —— 官方《i2c.scan》原文"如探测不到则修改此项"
    probe_addr(bus, i2c.FAST, addr, "bus" .. bus .. "/FAST")
    -- ③ 换另一路 I2C：排除"传感器实际接在另一条总线"
    probe_addr(other, i2c.SLOW, addr, "bus" .. other .. "/SLOW")

    -- ④ 官方全量扫描：区分"只有目标地址不响应"与"整条总线无器件"
    i2c.setup(bus, i2c.SLOW)
    log.warn("gsensor", "全量扫描 bus", bus, "（以下由官方 i2c.scan 输出；全部超时=总线上无任何器件）:")
    i2c.scan(bus)
    log.warn("gsensor", "===== 诊断结束 =====")
end

-- ====== 20Hz 流式采样（GNSS 开启期间采集，供 TLV 1301 上报） ======
-- 采样率 20Hz：10 秒窗口 200 样本；输出 12bit 紧凑编码：
-- 每 2 个样本 6 个 12bit 值 = 72bit = 9 字节，200 样本 = 100 组 × 9 字节 = 900 字节，
-- TLV 总长 4+900=904，为整包 1400 字节上限留足余量
-- （AirCloud 约束：单条数据包内全部 TLV 总字节 ≤ 1400）
local STREAM_HZ = 20              -- 采样率（每秒 20 次）
local STREAM_INTERVAL_MS = 50     -- 采样间隔(ms) = 1000/20
local STREAM_BUFFER_MAX = 205     -- 缓冲容量：10 秒=200 样本 + 少量余量

-- 轮询降级（无中断引脚时的兜底）：静置时合加速度≈1g，偏离超过阈值连续 N 次判定为震动
local POLL_INTERVAL_MS = 200      -- 轮询周期
local POLL_HITS_NEEDED = 3        -- 连续命中次数（约 600ms）

-- 模块状态
local state = {
    initialized = false,       -- 是否初始化完成
    drv = nil,                 -- 驱动实例（由 create_driver 按 profile 装配）
    int_capable = false,       -- 是否具备硬件中断能力
    vibration_callback = nil,  -- 震动回调（由主循环注册）
    last_vibration_time = 0,   -- 上次震动时间戳（用于 2000ms 限流）
    vibration_interval = 2000, -- 震动回调限流间隔(ms)：2秒内连续震动只算一次

    is_moving = false,         -- 当前是否运动中
    last_motion_time = 0,      -- 上次运动时间戳（用于超时恢复）
    motion_timeout = 10,       -- 运动超时(秒)：超过此时间无震动自动恢复静止
    pending_gps = false,       -- 震动唤醒待处理标志：置位后下一次上报强制走 GPS

    last_xyz = nil,            -- 最近一次中断采集的三轴快照 {x,y,z,raw_x,raw_y,raw_z,ts}
    xyz_capture_on = false,    -- 采集任务运行标志

    stream_on = false,         -- 20Hz 流式采样开关（GNSS 开启期间为 true）
    stream_buffer = {},        -- 流式采样滚动缓冲：每个元素为 6 字节打包样本（x/y/z int16 大端）
    stream_task_on = false,    -- 流式采样任务运行标志
    poll_task_on = false,      -- 轮询降级任务运行标志
}

-- 震动事件处理：硬件中断与轮询降级共用同一入口
-- @param from_poll boolean 是否来自轮询降级（来自轮询时不打印原始中断日志，避免刷屏）
local function interrupt_handler(from_poll)
    if not state.initialized then return end

    local now = os.time()

    -- 【灵敏度标定用，已降级为 debug】每次硬件中断触发都打印（含被 2s 限流挡掉的）。
    -- 需要标定震动灵敏度时把 log.debug 临时改回 log.info，即可观察触发频率。
    if not from_poll then
        log.debug("gsensor", "INT触发 距上次震动", (now - state.last_vibration_time), "s")
    end

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
        if got and state.initialized and state.drv then
            -- 中断触发后稍作延时，等传感器数据稳定再读
            sys.wait(50)
            local ok, x, y, z, rx, ry, rz = pcall(state.drv.read_all, state.drv)
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

-- 20Hz 流式采样任务：GNSS 开启期间（stream_on=true）持续读取三轴原始值，
-- 每个样本以 6 字节（x/y/z 各 2 字节有符号 int16 大端）存入滚动缓冲，
-- 上报时通过 get_stream_data 取最近 200 个样本（10 秒），压缩为 12bit 紧凑位流输出。
-- 用 mcu.ticks 做时间片调度，自动补偿 I2C 读取耗时，保证实际采样率贴近 20Hz。
local function stream_task()
    log.info("gsensor", "20Hz 流式采样任务启动")
    local next_tick = mcu.ticks()
    while true do
        if state.stream_on and state.initialized and state.drv then
            local ok, rx, ry, rz = pcall(state.drv.read_raw, state.drv)
            if ok and rx ~= nil then
                table.insert(state.stream_buffer, string.pack(">i2i2i2", rx, ry, rz))
                if #state.stream_buffer > STREAM_BUFFER_MAX then
                    table.remove(state.stream_buffer, 1)
                end
            end
            -- 时间片调度：固定 50ms 节拍；I2C 耗时自动补偿；
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

-- 轮询降级任务（仅 int_capable=false 时运行）：
-- 静置时合加速度≈1g；|合加速度-1| 超过 motion_threshold_g 连续 POLL_HITS_NEEDED 次即视为震动。
-- 代价：震动响应延迟约 600ms、功耗略升；仅作无中断引脚板型的兜底，不作为验收路径。
local function motion_poll_task()
    local thr = GS_CFG.motion_threshold_g or 0.18
    local hits = 0
    log.warn("gsensor", "无中断引脚，启用轮询降级（周期", POLL_INTERVAL_MS, "ms，阈值", thr, "g）")
    while state.initialized do
        sys.wait(POLL_INTERVAL_MS)
        if state.initialized and state.drv and not state.int_capable then
            local ok, x, y, z = pcall(state.drv.read_g, state.drv)
            if ok and x then
                local mag = math.sqrt(x * x + y * y + z * z)
                if math.abs(mag - 1) > thr then
                    hits = hits + 1
                    if hits >= POLL_HITS_NEEDED then
                        hits = 0
                        interrupt_handler(true)
                    end
                else
                    hits = 0
                end
            end
        end
    end
    state.poll_task_on = false
    log.info("gsensor", "轮询降级任务退出")
end

function gsensor.init()
    if state.initialized then
        return true
    end

    state.drv = create_driver(GS_CFG)
    state.int_capable = state.drv.int_capable == true

    if not state.drv.setup() then
        log.error("gsensor", "加速度计驱动初始化失败（impl=", tostring(GS_CFG.impl),
            "），运动感知不可用 —— 后果：1300 三轴不上报、1301/1303 振动流为 0 样本")
        -- 失败即打印一次 I2C 诊断，便于定位是"没上电/接错"还是"地址/型号不对"
        diag_i2c(GS_CFG)
        return false
    end

    -- 注册震动回调：有中断引脚时走硬件中断；否则由轮询任务兜底
    state.drv.set_callback(interrupt_handler)

    state.initialized = true
    state.last_vibration_time = os.time()
    log.info("gsensor", "运动检测初始化成功（驱动=", tostring(GS_CFG.impl),
        "，中断脚=", tostring(GS_CFG.int_pin),
        "，中断可用=", tostring(state.int_capable), "）")

    -- 启动三轴快照采集任务（订阅 GSENSOR_XYZ_CAPTURE，读到数据存 state.last_xyz）
    if not state.xyz_capture_on then
        state.xyz_capture_on = true
        sys.taskInit(xyz_capture_task)
    end

    -- 启动 20Hz 流式采样任务（常驻协程，由 stream_on 控制采样/待机）
    if not state.stream_task_on then
        state.stream_task_on = true
        sys.taskInit(stream_task)
    end

    -- 无中断能力时启用轮询降级
    if not state.int_capable and not state.poll_task_on then
        state.poll_task_on = true
        sys.taskInit(motion_poll_task)
    end

    return true
end

-- 功耗档切换后恢复（drv_lowpower / drv_normal 调用）
-- ★ 关键：pm.power(pm.WORK_MODE, n) 会**复位引脚配置**，因此除中断脚外，
--   板级 I2C 支撑脚（上拉源 / 器件供电）也必须一并重新拉高 ——
--   否则 I2C 会持续失败（实机 2026-09-17：开机初始化成功、运行中突然全部超时/异常）。
function gsensor._restore_interrupt()
    if not state.initialized or not state.drv then return end
    if state.drv.assert_support then state.drv.assert_support() end
    state.drv.set_callback(interrupt_handler)
    log.info("gsensor", "已恢复：中断注册 + 板级 I2C 支撑脚")
end

function gsensor.close()
    if not state.initialized then return end

    -- 先清标志让采集任务退出（waitUntil 200ms 超时后检测到退出）
    state.initialized = false
    state.last_xyz = nil

    if state.drv then
        state.drv.close()
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
    if not state.initialized or not state.drv then return nil end
    return state.drv.read_g()
end

-- 主动读取三轴原始计数值（12 位有符号，-2048~2047）。同样只能在协程上下文调用。
-- 返回 raw_x, raw_y, raw_z；未初始化返回 nil。
function gsensor.read_raw_xyz()
    if not state.initialized or not state.drv then return nil end
    return state.drv.read_raw()
end

-- ====== 20Hz 流式采样接口（GNSS 开启期间采集，作为 TLV 1301 上报） ======

-- 开启流式采样（清空缓冲从头采）。GNSS 开启时调用。
function gsensor.stream_start()
    state.stream_buffer = {}
    state.stream_on = true
    log.info("gsensor", "流式采样开启: 20Hz, 缓冲上限", STREAM_BUFFER_MAX, "样本")
end

-- 停止流式采样并清空缓冲。GNSS 关闭时调用。
function gsensor.stream_stop()
    state.stream_on = false
    state.stream_buffer = {}
    log.info("gsensor", "流式采样停止, 缓冲已清空")
end

-- 两个 12bit 值打包为 3 字节（大端位流：a 占高 12bit，b 占低 12bit）。
local function pack12(a, b)
    a, b = a & 0xFFF, b & 0xFFF
    return string.char((a >> 4) & 0xFF, ((a & 0xF) << 4) | ((b >> 8) & 0xF), b & 0xFF)
end

-- 取最近 count 个样本（默认 200 = 10 秒），以 12bit 紧凑编码拼接为字节串。
-- 编码格式：每 2 个样本一组共 9 字节，bit 流顺序为 x1,y1,z1,x2,y2,z2（各 12bit，MSB 在前），
-- 即把 72bit 大端位流按 12bit 切成 6 段，前 3 段为第 1 个样本的 x/y/z，后 3 段为第 2 个样本。
-- 服务端解码：每 9 字节一组还原 6 个 12bit 值，最高位为符号位，符号扩展后即原始计数。
-- 200 样本 = 100 组 × 9 字节 = 900 字节，1301 TLV 总长 4+900=904。
-- 样本数为奇数时丢弃最旧 1 个样本（保证 2 个一组）；采样数不足 count 时返回实际数量。
-- 返回 (data, actual_count)；未开启或无数据返回 ("", 0)。
function gsensor.get_stream_data(count)
    count = count or 200
    local buf = state.stream_buffer
    local n = math.min(count, #buf)
    if n <= 1 then return "", 0 end
    n = n - (n % 2)  -- 奇数时丢弃最旧 1 个样本，保证 2 个一组
    local out = {}
    for i = #buf - n + 1, #buf - 1, 2 do
        local x1, y1, z1 = string.unpack(">i2i2i2", buf[i])
        local x2, y2, z2 = string.unpack(">i2i2i2", buf[i + 1])
        -- 9 字节 = 3 个 3 字节组：x1y1 | z1x2 | y2z2，拼接后即 x1,y1,z1,x2,y2,z2 顺序的 72bit 位流
        out[#out + 1] = pack12(x1, y1) .. pack12(z1, x2) .. pack12(y2, z2)
    end
    return table.concat(out), n
end

-- 获取最近一次震动中断采集的三轴快照（由 xyz_capture_task 写入）。
-- 返回表 {x,y,z, raw_x,raw_y,raw_z, ts}（ts 为 os.time() 秒级时间戳），无快照返回 nil。
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
        impl = GS_CFG.impl,
        int_capable = state.int_capable,
        is_moving = state.is_moving,
        last_motion_time = state.last_motion_time,
        motion_timeout = state.motion_timeout,
    }
end

return gsensor
