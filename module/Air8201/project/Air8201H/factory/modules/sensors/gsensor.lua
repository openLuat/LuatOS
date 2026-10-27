-- 加速度计运动检测模块（多型号自适应：DA221/exvib 与 DA267/exs_da267 双驱动）
-- 板级差异（供电脚/I2C 支撑脚/地址）收敛于本模块驱动装配段。
--
-- 对外接口（仅 3 个，供主链路与低功耗模块使用）：
--   gsensor.init()                 - 初始化（按 profile 装配驱动并完成供电/寄存器配置）
--   gsensor._restore_interrupt()   - 功耗档切换后恢复中断注册与支撑脚（drv_normal/drv_lowpower 调用）
--   gsensor.set_motion_state(b,t)  - 强制设置运动状态（低功耗震动唤醒时用，仅日志占位）
--
-- 说明：
--   1) 三款产品板（8202/8201G/8201H）均配置震动中断脚，低功耗下的震动唤醒由
--      lowpower/drv_lowpower.lua 直接注册引脚处理，本模块不重复消费；
--   2) 正常运行期无业务读取三轴数据，init 中仅做最小中断注册（维持引脚输入态，
--      避免悬空漏电），回调体内不做 I2C 读写；
--   3) setup 失败时打印一趟 I2C 诊断，区分"未上电/总线不通/地址型号错误"。
local gsensor = {}

local config = require "config"

-- 板级配置（board.lua 识别后写入 config.BOARD.gsensor）
local GS_CFG = (config.BOARD and config.BOARD.gsensor) or { impl = "none" }

-- ==================== 加速度计驱动装配（板级差异收敛于此） ====================
-- 统一最小接口：
--   drv.setup()           供电/I2C/寄存器配置（必须在协程中调用），成功返回 true
--   drv.set_callback(fn)  注册中断回调（fn 在中断上下文执行，内部禁止 I2C）
--   drv.assert_support()  幂等拉高板级 I2C 支撑脚（功耗档切换后调用）

-- DA221 / exvib（Air8202）
local function create_exvib_driver(gs)
    local drv = { impl = "exvib" }
    local lib = require "exvib"

    function drv.setup()
        -- exvib 自行管理 I2C 总线与传感器供电脚；open 内部是异步初始化，需等其完成。
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

    -- exvib 自行管理 I2C 与供电脚，仅在板级显式声明 power_pin 时兜底重拉。
    function drv.assert_support()
        if gs.power_pin then gpio.setup(gs.power_pin, 1, gpio.PULLUP) end
    end

    return drv
end

-- DA267 / exs_da267（Air8201G / 8201H）
local function create_da267_driver(gs)
    local drv = { impl = "exs_da267" }
    local lib = require "exs_da267"
    local range = gs.range_g or 2

    -- 写输出脚并校验结果：gpio.setup 成功返回闭包，失败（引脚越界/被占用）返回 nil。
    local function set_out(pin)
        local r = gpio.setup(pin, 1, gpio.PULLUP)
        if r == nil or r == false then
            log.error("gsensor", "gpio.setup 失败(pin=", pin,
                ") —— 该脚疑似已被低功耗配置收走，Lua 层无法重配")
            return false
        end
        return true
    end

    -- 板级 I2C 支撑脚清单：优先取 support_pins（I2C1 上全部器件的使能脚）；
    -- 未声明时回退为「上拉源 + 供电」两脚。
    -- 动机：I2C1 上任一器件未上电，其 ESD 二极管就会把 SDA/SCL 钳在低位，
    -- 主控只看到"传输异常"，上拉再强也无用。
    local support_pins = {}
    if type(gs.support_pins) == "table" then
        for _, pin in ipairs(gs.support_pins) do
            if pin then support_pins[#support_pins + 1] = pin end
        end
    else
        if gs.i2c_pullup_pin then support_pins[#support_pins + 1] = gs.i2c_pullup_pin end
        if gs.power_pin then support_pins[#support_pins + 1] = gs.power_pin end
    end

    local function assert_support()
        for _, pin in ipairs(support_pins) do
            set_out(pin)
        end
    end
    drv.assert_support = assert_support

    function drv.setup()
        -- ① 板级 I2C 支撑脚（上拉源 + 供电），必须先于任何 I2C 通信。
        -- 不使能则 SDA/SCL 无上拉，整条总线无器件应答（实机已复现）。
        assert_support()
        sys.wait(50)
        log.info("gsensor", "板级 I2C 支撑脚已拉高：", table.concat(support_pins, ","))

        local ok = lib.setup({
            i2c_id              = gs.i2c_id or 1,
            addr                = gs.addr or 0x26,
            int_pin             = gs.int_pin,   -- nil 时库内不登记中断
            range               = range,
            motion_enable       = true,
            motion_window       = 60,
            motion_threshold    = 5,
            step_counter_enable = false,
        })
        if not ok then
            log.error("gsensor", "exs_da267.setup 失败（供电/I2C/芯片ID 校验不通过）")
            return false
        end

        log.info("gsensor", "exs_da267 初始化完成（range=", range,
            "g, 中断脚=", tostring(gs.int_pin), "）")
        return true
    end

    function drv.set_callback(cb)
        lib.set_callback(cb)
        if not gs.int_pin then
            log.warn("gsensor", "exs_da267 未配置中断引脚，震动中断不可用")
            return false
        end
        return true
    end

    return drv
end

-- 无运动感知能力（unknown 兜底）
local function create_none_driver()
    return {
        impl           = "none",
        setup          = function() return true end,
        set_callback   = function() return false end,
        assert_support = function() end,
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
目的：一次开机区分失败原因：
  ① 全部地址无应答   → 传感器没上电或总线不通（SDA/SCL 缺上拉）
  ② 0x26 应答但 ID 错 → 型号/地址判断有误
做法全部为官方接口：i2c.send + i2c.recv 读芯片ID 寄存器（0x01，DA267 期望 0x13），
再用 i2c.scan 全量扫描。
]]
local function probe_addr(bus, speed, a, tag)
    i2c.setup(bus, speed)
    i2c.send(bus, a, 0x01, 1)
    local d = i2c.recv(bus, a, 1)
    if d and #d == 1 then
        log.warn("gsensor", string.format("  [%s] 0x%02X 芯片ID=0x%02X%s", tag, a,
            string.byte(d), (string.byte(d) == 0x13) and " ★DA267，正常" or " （非 DA267）"))
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
        " support_pins=", (type(gs.support_pins) == "table")
            and table.concat(gs.support_pins, ",") or "nil")

    probe_addr(bus, i2c.SLOW, addr, "bus" .. bus .. "/SLOW")
    probe_addr(bus, i2c.FAST, addr, "bus" .. bus .. "/FAST")
    probe_addr(other, i2c.SLOW, addr, "bus" .. other .. "/SLOW")

    i2c.setup(bus, i2c.SLOW)
    log.warn("gsensor", "全量扫描 bus", bus, "（以下由官方 i2c.scan 输出）:")
    i2c.scan(bus)
    log.warn("gsensor", "===== 诊断结束 =====")
end

-- 模块状态
local state = {
    initialized = false,   -- 是否初始化完成
    drv = nil,             -- 驱动实例
}

-- 中断最小回调：正常运行期无业务消费震动事件（低功耗唤醒由 drv_lowpower 直接
-- 注册引脚处理），此处仅维持引脚输入态，不做任何 I2C 操作。
local function interrupt_handler()
    log.debug("gsensor", "震动中断触发")
end

function gsensor.init()
    if state.initialized then
        return true
    end

    state.drv = create_driver(GS_CFG)

    if not state.drv.setup() then
        -- 失败即打印一次 I2C 诊断，便于定位是"没上电/接错"还是"地址/型号不对"
        diag_i2c(GS_CFG)
        return false
    end

    state.drv.set_callback(interrupt_handler)

    state.initialized = true
    log.info("gsensor", "运动检测初始化成功（驱动=", tostring(GS_CFG.impl),
        "，中断脚=", tostring(GS_CFG.int_pin), "）")
    return true
end

-- 功耗档切换后恢复（drv_lowpower / drv_normal 调用）
-- pm.power(pm.WORK_MODE, n) 会复位引脚配置，板级 I2C 支撑脚与中断注册必须一并重做。
function gsensor._restore_interrupt()
    if not state.initialized or not state.drv then return end
    if state.drv.assert_support then state.drv.assert_support() end
    state.drv.set_callback(interrupt_handler)
    log.info("gsensor", "已恢复：中断注册 + 板级 I2C 支撑脚")
end

-- 低功耗震动唤醒时由 drv_lowpower 调用；当前无业务读取运动状态，仅保留接口与日志。
function gsensor.set_motion_state(moving)
    log.info("gsensor", "运动状态强制设置为:", moving and "运动中" or "静止")
end

return gsensor
