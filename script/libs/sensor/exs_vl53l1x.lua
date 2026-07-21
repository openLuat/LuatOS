--[[
@module  exs_vl53l1x
@summary VL53L1X 飞行时间(ToF)测距传感器扩展库
@version 1.0
@date    2026.07.21
@author  江访
@usage
本文件为 VL53L1X 飞行时间测距传感器（ST 出品）的 LuatOS 扩展库。
寄存器地址与配置值严格对照 ST 官方 API（en.STSW-IMG007/api/core）：
  - vl53l1_register_map.h        寄存器地址
  - vl53l1_register_settings.h   寄存器值定义
  - vl53l1_api_preset_modes.c    预设模式配置（preset_mode_standard_ranging）
  - vl53l1_api_core.c            启停测距、清中断、读结果
  - vl53l1_silicon_core.c        软复位
  - vl53l1_wait.c                等待 boot 完成 / 等待数据就绪

核心功能为：
1、初始化（硬件/软件复位 -> 等待固件就绪 -> 写入 Standard Ranging 预设模式 -> 启动测距）
2、读取测距数据（距离 mm、状态码）
3、I2C 总线卡死自动检测与恢复
4、睡眠/唤醒/关闭
5、GPIO1 中断支持（回调模式 / get_int_flag 轮询模式）
6、串扰校准（配合白纸板校准保护玻璃串扰）
7、三档测距模式（standard/short/long）

对外接口 6 个：
1、exs_vl53l1x.setup(config)：初始化 VL53L1X 并启动测距
2、exs_vl53l1x.get_data()：读取一帧测距数据（阻塞等待数据就绪）
3、exs_vl53l1x.sleep()：进入软件待机（停止测距）
4、exs_vl53l1x.wakeup()：从软件待机唤醒（重新启动测距，与 sleep 配对）
5、exs_vl53l1x.close()：关闭传感器
6、exs_vl53l1x.version()：获取版本号

注意：
- 预设模式为 Standard Ranging（连续 back-to-back 测距），与官方
  VL53L1_preset_mode_standard_ranging() 一致。
- get_data() 内部已包含：轮询 GPIO__TIO_HV_STATUS 判断数据就绪 -> 读结果 ->
  清 range 中断 -> 再次写 mode_start 触发下一帧。
- int1.int_gpio 填写 GPIO 端口号（不是 pin 引脚号），如 GPIO10 填 10。
- 中断注册放在 g_ready=true 之后，避免注册时电平触发回调导致误报。

-- 版本更新说明
版本号：202607211200
1、更新时间：2026-07-21
2、更新内容：
            支持软件I2C、硬件I2C初始化
            支持标准测距、三档模式切换（standard/short/long）
            支持I2C 总线卡死自动检测与恢复
            支持睡眠/唤醒/关闭，支持低功耗待机
]]

local exs_vl53l1x = {}

-- ==================== 模块常量 ====================

-- I2C 设备地址（官方 VL53L1_EWOK_I2C_DEV_ADDR_DEFAULT = 0x29）
local DEV_ADDR = 0x29

-- ==================== 寄存器地址（来自官方 vl53l1_register_map.h）====================

-- 软复位（active low，写 0x00 拉低，写 0x01 释放）
local REG_SOFT_RESET                       = 0x0000

-- 固件系统状态（bit0=1 表示固件启动完成）
local REG_FIRMWARE__SYSTEM_STATUS          = 0x00E5

-- 芯片标识
local REG_IDENTIFICATION__MODEL_ID         = 0x010F  -- 应返回 0xEA
local REG_IDENTIFICATION__MODULE_TYPE      = 0x0110  -- 应返回 0xCC
local MODEL_ID_VAL                         = 0xEA
local MODULE_TYPE_VAL                      = 0xCC

-- 静态配置区
local REG_DSS_CONFIG__TARGET_TOTAL_RATE_MCPS_HI = 0x0024
local REG_GPIO_HV_MUX__CTRL                     = 0x0030
local REG_GPIO__TIO_HV_STATUS                   = 0x0031

-- 通用配置区
local REG_SYSTEM__INTERRUPT_CONFIG_GPIO     = 0x0046
local REG_DSS_CONFIG__ROI_MODE_CONTROL     = 0x004F

-- 时序配置区
local REG_MM_CONFIG__TIMEOUT_MACROP_A_HI   = 0x005A
local REG_RANGE_CONFIG__VCSEL_PERIOD_A     = 0x0060
local REG_RANGE_CONFIG__SIGMA_THRESH_HI    = 0x0064
local REG_RANGE_CONFIG__MIN_COUNT_RATE_RTN_LIMIT_MCPS_HI = 0x0066

-- 动态配置区
local REG_SYSTEM__GROUPED_PARAMETER_HOLD_0 = 0x0071
local REG_SD_CONFIG__WOI_SD0               = 0x0078
local REG_SD_CONFIG__INITIAL_PHASE_SD0     = 0x007A
local REG_SYSTEM__GROUPED_PARAMETER_HOLD_1 = 0x007C
local REG_SD_CONFIG__FIRST_ORDER_SELECT    = 0x007D
local REG_SD_CONFIG__QUANTIFIER            = 0x007E
local REG_ROI_CONFIG__USER_ROI_CENTRE_SPAD = 0x007F
local REG_ROI_CONFIG__USER_ROI_REQUESTED_GLOBAL_XY_SIZE = 0x0080
local REG_SYSTEM__SEQUENCE_CONFIG          = 0x0081
local REG_SYSTEM__GROUPED_PARAMETER_HOLD   = 0x0082

-- 系统控制区（5 字节，0x0083 起）
local REG_POWER_MANAGEMENT__GO1_POWER_FORCE = 0x0083
local REG_SYSTEM__STREAM_COUNT_CTRL        = 0x0084
local REG_FIRMWARE__ENABLE                 = 0x0085
local REG_SYSTEM__INTERRUPT_CLEAR          = 0x0086
local REG_SYSTEM__MODE_START               = 0x0087

-- 结果寄存器
local REG_RESULT__RANGE_STATUS             = 0x0089  -- bit[4:0]=range_status, bit[6]=min_thr, bit[7]=gph_id
local REG_RESULT__STREAM_COUNT             = 0x008B
local REG_RESULT__FINAL_CROSSTALK_CORRECTED_RANGE_MM_SD0 = 0x0096  -- 16-bit 距离 mm

-- 校准相关寄存器
local REG_ALGO__CROSSTALK_COMPENSATION_PLANE_OFFSET_KCPS   = 0x0016  -- 16-bit 串扰补偿偏移(7.9 fp)
local REG_ALGO__CROSSTALK_COMPENSATION_X_PLANE_GRADIENT_KCPS = 0x0018  -- 16-bit X梯度
local REG_ALGO__CROSSTALK_COMPENSATION_Y_PLANE_GRADIENT_KCPS = 0x001A  -- 16-bit Y梯度
local REG_RESULT__PEAK_SIGNAL_COUNT_RATE_CROSSTALK_CORRECTED_MCPS_SD0 = 0x0098  -- 16-bit 峰值信号速率(9.7 fp)
local REG_RESULT__DSS_ACTUAL_EFFECTIVE_SPADS_SD0           = 0x008C  -- 16-bit SPAD数量

-- ==================== 寄存器值定义（来自官方 vl53l1_register_settings.h）====================

-- SYSTEM__MODE_START 位组合
local MODE_STREAMING        = 0x01  -- VL53L1_DEVICESCHEDULERMODE_STREAMING
local MODE_SINGLE_SD        = 0x00  -- VL53L1_DEVICEREADOUTMODE_SINGLE_SD (0x00 << 2)
local MODE_BACKTOBACK       = 0x20  -- VL53L1_DEVICEMEASUREMENTMODE_BACKTOBACK
local MODE_ABORT            = 0x80  -- VL53L1_DEVICEMEASUREMENTMODE_ABORT
local MODE_STOP_MASK        = 0x0F  -- VL53L1_DEVICEMEASUREMENTMODE_STOP_MASK

-- 标准 ranging 启动值 = STREAMING | SINGLE_SD | BACKTOBACK = 0x21
local MODE_START_STANDARD   = MODE_STREAMING | MODE_SINGLE_SD | MODE_BACKTOBACK

-- SYSTEM__INTERRUPT_CLEAR
local CLEAR_RANGE_INT       = 0x01  -- VL53L1_CLEAR_RANGE_INT

-- SYSTEM__INTERRUPT_CONFIG_GPIO
local INT_CONFIG_NEW_SAMPLE_READY = 0x20  -- VL53L1_INTERRUPT_CONFIG_NEW_SAMPLE_READY

-- GPIO_HV_MUX__CTRL
local GPIO_POL_ACTIVE_LOW              = 0x10  -- VL53L1_DEVICEINTERRUPTPOLARITY_ACTIVE_LOW
local GPIO_MODE_RANGE_AND_ERROR        = 0x01  -- VL53L1_DEVICEGPIOMODE_OUTPUT_RANGE_AND_ERROR_INTERRUPTS
local GPIO_HV_MUX_CTRL_STD             = GPIO_POL_ACTIVE_LOW + GPIO_MODE_RANGE_AND_ERROR  -- 0x11

-- SYSTEM__SEQUENCE_CONFIG = VHV|PHASECAL|DSS1|DSS2|MM2|RANGE = 0x6B
local SEQ_VHV_EN       = 0x01
local SEQ_PHASECAL_EN  = 0x02
local SEQ_DSS1_EN      = 0x08
local SEQ_DSS2_EN      = 0x10
local SEQ_MM2_EN       = 0x40
local SEQ_RANGE_EN     = 0x80
local SEQUENCE_CONFIG_STD = SEQ_VHV_EN + SEQ_PHASECAL_EN + SEQ_DSS1_EN + SEQ_DSS2_EN + SEQ_MM2_EN + SEQ_RANGE_EN  -- 0x6B

-- range_status 位掩码
local RANGE_STATUS_MASK = 0x1F  -- VL53L1_RANGE_STATUS__RANGE_STATUS_MASK

-- ==================== 状态码映射 ====================
-- 官方的 ConvertStatusLite() 将 device_error(raw) 映射为 user_range_status
-- raw 值对应 VL53L1_DEVICEERROR_ 枚举(来自寄存器 0x0089 bit[4:0])
-- 映射表来自 vl53l1_api.c::ConvertStatusLite
local RAW_RANGECOMPLETE            = 9   -- raw=9 -> RANGESTATUS_RANGE_VALID(0)
local RAW_RANGECOMPLETE_NOWRAP     = 1   -- raw=1 -> RANGESTATUS_RANGE_VALID_NO_WRAP_CHECK_FAIL(6)
local RAW_RANGEPHASECHECK          = 2   -- raw=2 -> RANGESTATUS_OUTOFBOUNDS_FAIL(4)
local RAW_MSRCNOTARGET             = 4   -- raw=4 -> RANGESTATUS_SIGNAL_FAIL(2)
local RAW_SIGMATHRESHOLDCHECK      = 5   -- raw=5 -> RANGESTATUS_SIGMA_FAIL(1)
local RAW_PHASECONSISTENCY         = 6   -- raw=6 -> RANGESTATUS_WRAP_TARGET_FAIL(7)
local RAW_RANGEIGNORETHRESHOLD     = 7   -- raw=7 -> RANGESTATUS_XTALK_SIGNAL_FAIL(9)
local RAW_MINCLIP                  = 8   -- raw=8 -> RANGESTATUS_RANGE_VALID_MIN_RANGE_CLIPPED(3)
local RAW_GPHSTREAMCOUNT0READY     = 10  -- raw=10 -> RANGESTATUS_SYNCRONISATION_INT(10)

-- 用户可见的 RangeStatus(来自 vl53l1_def.h)
local ST_VALID     = 0   -- VL53L1_RANGESTATUS_RANGE_VALID
local ST_SIGMA     = 1   -- VL53L1_RANGESTATUS_SIGMA_FAIL
local ST_SIGNAL    = 2   -- VL53L1_RANGESTATUS_SIGNAL_FAIL
local ST_MINRANGE  = 3   -- VL53L1_RANGESTATUS_RANGE_VALID_MIN_RANGE_CLIPPED
local ST_PHASE     = 4   -- VL53L1_RANGESTATUS_OUTOFBOUNDS_FAIL
local ST_HW        = 5   -- VL53L1_RANGESTATUS_HARDWARE_FAIL
local ST_NOWRAP    = 6   -- VL53L1_RANGESTATUS_RANGE_VALID_NO_WRAP_CHECK_FAIL
local ST_WRAP      = 7   -- VL53L1_RANGESTATUS_WRAP_TARGET_FAIL
local ST_PROCESS   = 8   -- VL53L1_RANGESTATUS_PROCESSING_FAIL
local ST_XTALK     = 9   -- VL53L1_RANGESTATUS_XTALK_SIGNAL_FAIL
local ST_SYNC      = 10  -- VL53L1_RANGESTATUS_SYNCRONISATION_INT
local ST_MERGED    = 11  -- VL53L1_RANGESTATUS_RANGE_VALID_MERGED_PULSE
local ST_LOWSIGNAL = 12  -- VL53L1_RANGESTATUS_TARGET_PRESENT_LACK_OF_SIGNAL
local ST_MINRANGEF = 13  -- VL53L1_RANGESTATUS_MIN_RANGE_FAIL
local ST_INVALID   = 14  -- VL53L1_RANGESTATUS_RANGE_INVALID

-- raw->user 映射(对照官方 ConvertStatusLite)
local CONVERT_STATUS = {
    [RAW_RANGECOMPLETE]        = ST_VALID,     -- 9 -> 0: 正常测距成功
    [RAW_RANGECOMPLETE_NOWRAP] = ST_NOWRAP,    -- 1 -> 6
    [RAW_RANGEPHASECHECK]      = ST_PHASE,     -- 2 -> 4
    [RAW_MSRCNOTARGET]         = ST_SIGNAL,    -- 4 -> 2
    [RAW_SIGMATHRESHOLDCHECK]  = ST_SIGMA,     -- 5 -> 1
    [RAW_PHASECONSISTENCY]     = ST_WRAP,       -- 6 -> 7
    [RAW_RANGEIGNORETHRESHOLD] = ST_XTALK,      -- 7 -> 9
    [RAW_MINCLIP]              = ST_MINRANGE,   -- 8 -> 3
    [RAW_GPHSTREAMCOUNT0READY] = ST_SYNC,       -- 10 -> 10
}

-- 用户可见 RangeStatus 描述(vl53l1_api_strings.c)
local RANGE_STATUS_LIST = {
    [ST_VALID]     = "测距成功",
    [ST_SIGMA]     = "Sigma 失效",
    [ST_SIGNAL]    = "信号失效",
    [ST_MINRANGE]  = "目标距离小于最小值",
    [ST_PHASE]     = "相位超出范围",
    [ST_HW]        = "硬件故障",
    [ST_NOWRAP]    = "测距成功(未绕行检查)",
    [ST_WRAP]      = "相位绕行",
    [ST_PROCESS]   = "处理失败",
    [ST_XTALK]     = "串扰信号",
    [ST_SYNC]      = "同步中断",
    [ST_MERGED]    = "合并脉冲",
    [ST_LOWSIGNAL] = "信号弱",
    [ST_MINRANGEF] = "最小距离失败",
    [ST_INVALID]   = "范围无效",
}

-- 将 raw device_error 转换为用户可见 RangeStatus
-- 对照官方 ConvertStatusLite() + SetSimpleData() 中的 device_status 分支
local function convert_range_status(raw_status)
    return CONVERT_STATUS[raw_status] or ST_INVALID
end

-- ==================== 内部状态 ====================

local g_i2c_bus   = nil
local g_is_soft   = false
local g_scl_pin   = nil
local g_sda_pin   = nil
local g_xshut_pin = nil
local g_ready     = false
-- 中断极性：true=ACTIVE_HIGH(0x00)，false=ACTIVE_LOW(0x10)。默认按 STANDARD 配置 = ACTIVE_LOW
local g_int_active_high = false
-- GPIO1 中断支持
local g_int1_gpio = nil  -- GPIO1 引脚号
local g_int1_cb   = nil  -- GPIO1 回调函数
local g_int1_flag = false  -- 中断标志

-- ==================== I2C 操作 ====================

local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0); sys.wait(1)
        gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)
        if gpio.get(g_sda_pin) == 1 then
            gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
            break
        end
        gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
        gpio.set(g_scl_pin, 1); sys.wait(1)
    end
    gpio.set(g_sda_pin, 0); sys.wait(1)
    gpio.set(g_scl_pin, 1); sys.wait(1)
    gpio.set(g_sda_pin, 1); sys.wait(1)
    return true
end

local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)
    local is_stall = (gpio.get(g_sda_pin) == 0 and gpio.get(g_scl_pin) == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end
    log.warn("exs_vl53l1x", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_bus, i2c.SLOW) end
    return true
end

-- 写单字节寄存器（16-bit 寄存器地址）
local function wr8(reg, val)
    local h = (reg >> 8) & 0xFF; local l = reg & 0xFF
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l, val})
    if not ok and try_bus_recovery() then
        ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l, val})
    end
    return ok
end

-- 写多字节（reg 为 16-bit 地址，data 为字节数组）
local function wr_multi(reg, data)
    local h = (reg >> 8) & 0xFF; local l = reg & 0xFF
    local buf = {h, l}
    for i = 1, #data do buf[#buf + 1] = data[i] end
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, buf)
    if not ok and try_bus_recovery() then
        ok = i2c.send(g_i2c_bus, DEV_ADDR, buf)
    end
    return ok
end

-- 读单字节
local function rd8(reg)
    local h = (reg >> 8) & 0xFF; local l = reg & 0xFF
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l}) end
        if not ok then return nil end
    end
    local d = i2c.recv(g_i2c_bus, DEV_ADDR, 1)
    if not d or #d < 1 then return nil end
    return d:byte(1)
end

-- 读 16-bit（大端，HI 在前）
local function rd16(reg)
    local h = (reg >> 8) & 0xFF; local l = reg & 0xFF
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l}) end
        if not ok then return nil end
    end
    local d = i2c.recv(g_i2c_bus, DEV_ADDR, 2)
    if not d or #d < 2 then return nil end
    return (d:byte(1) << 8) | d:byte(2)
end

-- ==================== 内部函数 ====================

-- 软复位（对照官方 vl53l1_silicon_core.c::VL53L1_soft_reset）
-- 流程：写 0x00 拉低复位 -> 等 100us~1ms -> 写 0x01 释放 -> 等 boot 完成
local function soft_reset()
    wr8(REG_SOFT_RESET, 0x00)
    sys.wait(1)
    wr8(REG_SOFT_RESET, 0x01)
    sys.wait(1)
end

-- 等待固件 boot 完成（对照官方 VL53L1_wait_for_boot_completion）
-- 轮询 FIRMWARE__SYSTEM_STATUS (0x00E5) bit0，最长 1200ms
local function wait_firmware_ready()
    for i = 1, 120 do
        local status = rd8(REG_FIRMWARE__SYSTEM_STATUS)
        if status then
            if (status & 0x01) == 0x01 then
                log.info("exs_vl53l1x", string.format("固件就绪 0x00E5=0x%02X", status))
                return true
            end
        end
        sys.wait(10)
    end
    log.error("exs_vl53l1x", "固件未就绪（超时 1200ms）")
    return false
end

-- 写预设模式配置（对照官方 VL53L1_preset_mode_standard_ranging）
-- mode: "standard"(默认,约1.4m) / "long"(约4.6m,对应preset_mode_standard_ranging_long_range)
-- 分块连续写入，每块对应官方一组寄存器
local function write_preset_config(mode)
    mode = mode or "standard"

    -- === Static Config (0x0024 起, 与模式无关,只写一次) ===
    -- DSS_CONFIG__TARGET_TOTAL_RATE_MCPS = 0x0A00 (20.0 Mcps, 9.7 fp)
    wr8(REG_DSS_CONFIG__TARGET_TOTAL_RATE_MCPS_HI, 0x0A); wr8(0x0025, 0x00)
    wr8(0x0026, 0x00)  -- DEBUG__CTRL
    wr8(0x0027, 0x00)  -- TEST_MODE__CTRL
    wr8(0x0028, 0x00)  -- CLK_GATING__CTRL
    wr8(0x0029, 0x00)  -- NVM_BIST__CTRL
    wr8(0x002A, 0x00)  -- NVM_BIST__NUM_NVM_WORDS
    wr8(0x002B, 0x00)  -- NVM_BIST__START_ADDRESS
    wr8(0x002C, 0x00)  -- HOST_IF__STATUS
    wr8(0x002D, 0x00)  -- PAD_I2C_HV__CONFIG
    wr8(0x002E, 0x00)  -- PAD_I2C_HV__EXTSUP_CONFIG
    wr8(0x002F, 0x00)  -- GPIO_HV_PAD__CTRL
    wr8(REG_GPIO_HV_MUX__CTRL, GPIO_HV_MUX_CTRL_STD)  -- 0x0030 = 0x11 (active low + range/error)
    wr8(0x0031, 0x02)  -- GPIO__TIO_HV_STATUS
    wr8(0x0032, 0x00)  -- GPIO__FIO_HV_STATUS
    wr8(0x0033, 0x02)  -- ANA_CONFIG__SPAD_SEL_PSWIDTH
    wr8(0x0034, 0x08)  -- ANA_CONFIG__VCSEL_PULSE_WIDTH_OFFSET
    wr8(0x0035, 0x00)  -- ANA_CONFIG__FAST_OSC__CONFIG_CTRL
    wr8(0x0036, 0x08)  -- SIGMA_ESTIMATOR__EFFECTIVE_PULSE_WIDTH_NS
    wr8(0x0037, 0x10)  -- SIGMA_ESTIMATOR__EFFECTIVE_AMBIENT_WIDTH_NS
    wr8(0x0038, 0x01)  -- SIGMA_ESTIMATOR__SIGMA_REF_MM
    wr8(0x0039, 0x01)  -- ALGO__CROSSTALK_COMPENSATION_VALID_HEIGHT_MM
    wr8(0x003A, 0x00)  -- SPARE_HOST_CONFIG__STATIC_CONFIG_SPARE_0
    wr8(0x003B, 0x00)  -- SPARE_HOST_CONFIG__STATIC_CONFIG_SPARE_1
    wr8(0x003C, 0x00); wr8(0x003D, 0x00)  -- ALGO__RANGE_IGNORE_THRESHOLD_MCPS
    wr8(0x003E, 0xFF)  -- ALGO__RANGE_IGNORE_VALID_HEIGHT_MM
    wr8(0x003F, 0x00)  -- ALGO__RANGE_MIN_CLIP
    wr8(0x0040, 0x02)  -- ALGO__CONSISTENCY_CHECK__TOLERANCE
    wr8(0x0041, 0x00)  -- SPARE_HOST_CONFIG__STATIC_CONFIG_SPARE_2
    wr8(0x0042, 0x00)  -- SD_CONFIG__RESET_STAGES_MSB
    wr8(0x0043, 0x00)  -- SD_CONFIG__RESET_STAGES_LSB

    -- === General Config (0x0044 起) ===
    wr8(0x0044, 0x00)  -- GPH_CONFIG__STREAM_COUNT_UPDATE_VALUE
    wr8(0x0045, 0x00)  -- GLOBAL_CONFIG__STREAM_DIVIDER
    wr8(REG_SYSTEM__INTERRUPT_CONFIG_GPIO, INT_CONFIG_NEW_SAMPLE_READY)  -- 0x0046 = 0x20
    wr8(0x0047, 0x0B)  -- CAL_CONFIG__VCSEL_START
    wr8(0x0048, 0x00); wr8(0x0049, 0x00)  -- CAL_CONFIG__REPEAT_RATE
    wr8(0x004A, 0x02)  -- GLOBAL_CONFIG__VCSEL_WIDTH
    wr8(0x004B, 0x0D)  -- PHASECAL_CONFIG__TIMEOUT_MACROP (13 macrop = 1ms)
    wr8(0x004C, 0x21)  -- PHASECAL_CONFIG__TARGET (4.4 fp -> 2.0625)
    wr8(0x004D, 0x00)  -- PHASECAL_CONFIG__OVERRIDE
    wr8(REG_DSS_CONFIG__ROI_MODE_CONTROL, 0x01)  -- 0x004F = 0x01 (TARGET_RATE)
    wr8(0x0050, 0x00); wr8(0x0051, 0x00)  -- SYSTEM__THRESH_RATE_HIGH
    wr8(0x0052, 0x00); wr8(0x0053, 0x00)  -- SYSTEM__THRESH_RATE_LOW
    wr8(0x0054, 0x8C); wr8(0x0055, 0x00)  -- DSS_CONFIG__MANUAL_EFFECTIVE_SPADS_SELECT (8.8 fp -> 140)
    wr8(0x0056, 0x00)  -- DSS_CONFIG__MANUAL_BLOCK_SELECT
    wr8(0x0057, 0x38)  -- DSS_CONFIG__APERTURE_ATTENUATION (0.8 fp -> 4.6x)
    wr8(0x0058, 0xFF)  -- DSS_CONFIG__MAX_SPADS_LIMIT
    wr8(0x0059, 0x01)  -- DSS_CONFIG__MIN_SPADS_LIMIT

    -- === Timing Config (0x005A 起) ===
    -- 标准模式(standard)：约 2.9m 有效测距，VCSEL 24/20 period (官方 preset_mode_standard_ranging)
    -- 短距离模式(short)：约 1.36m 有效测距，VCSEL 16/12 period，抗环境光最强 (官方 preset_mode_standard_ranging_short_range)
    -- 长距离模式(long)：约 4.6m 有效测距，VCSEL 32/28 period (官方 preset_mode_standard_ranging_long_range)
    local vcsel_a, vcsel_b, mm_a, mm_b, range_a, range_b
    local valid_phase_high, min_rate, sigma_thresh_val
    local woi_sd0_val, woi_sd1_val

    if mode == "long" then
        -- 长距离覆写 (对照官方 preset_mode_standard_ranging_long_range)
        vcsel_a = 0x0F; vcsel_b = 0x0D
        mm_a = 0x001A; mm_b = 0x0020          -- 同 standard
        range_a = 0x01CC; range_b = 0x01F5      -- 同 standard
        sigma_thresh_val = 0x0168               -- 同 standard (14.2 fp)
        min_rate = 0x0080                        -- 1.0 Mcps
        valid_phase_high = 0xB8                  -- 5.3 fp -> 23.0 -> 4.6m
        woi_sd0_val = 0x0F; woi_sd1_val = 0x0D  -- 对应 vcsel_a/b
    elseif mode == "short" then
        -- 短距离覆写 (对照官方 preset_mode_standard_ranging_short_range)
        vcsel_a = 0x07; vcsel_b = 0x05
        mm_a = 0x001A; mm_b = 0x0020          -- 同 standard
        range_a = 0x01CC; range_b = 0x01F5      -- 同 standard
        sigma_thresh_val = 0x003C               -- 14.2 fp -> 15mm
        min_rate = 0x0080                        -- 1.0 Mcps
        valid_phase_high = 0x38                  -- 5.3 fp -> 7.0 -> 1.4m
        woi_sd0_val = 0x07; woi_sd1_val = 0x05  -- 对应 vcsel_a/b
    else
        -- 标准距离 (默认)
        vcsel_a = 0x0B; vcsel_b = 0x09
        mm_a = 0x001A; mm_b = 0x0020
        range_a = 0x01CC; range_b = 0x01F5
        sigma_thresh_val = 0x0168
        min_rate = 0x00C0                        -- 1.5 Mcps
        valid_phase_high = 0x78                  -- 5.3 fp -> 15.0 -> 3m
        woi_sd0_val = 0x0B; woi_sd1_val = 0x09
    end
    wr8(REG_MM_CONFIG__TIMEOUT_MACROP_A_HI, (mm_a >> 8) & 0xFF); wr8(0x005B, mm_a & 0xFF)
    wr8(0x005C, (mm_b >> 8) & 0xFF); wr8(0x005D, mm_b & 0xFF)
    wr8(0x005E, (range_a >> 8) & 0xFF); wr8(0x005F, range_a & 0xFF)
    wr8(REG_RANGE_CONFIG__VCSEL_PERIOD_A, vcsel_a)
    wr8(0x0061, (range_b >> 8) & 0xFF); wr8(0x0062, range_b & 0xFF)
    wr8(0x0063, vcsel_b)
    wr8(REG_RANGE_CONFIG__SIGMA_THRESH_HI, (sigma_thresh_val >> 8) & 0xFF); wr8(0x0065, sigma_thresh_val & 0xFF)
    wr8(REG_RANGE_CONFIG__MIN_COUNT_RATE_RTN_LIMIT_MCPS_HI, (min_rate >> 8) & 0xFF); wr8(0x0067, min_rate & 0xFF)
    wr8(0x0068, 0x08)  -- RANGE_CONFIG__VALID_PHASE_LOW (5.3 fp -> 1.0)
    wr8(0x0069, valid_phase_high)

    -- === Dynamic Config (0x0071 起) ===
    wr8(REG_SYSTEM__GROUPED_PARAMETER_HOLD_0, 0x01)  -- 0x0071
    wr8(0x0072, 0x00); wr8(0x0073, 0x00)  -- SYSTEM__THRESH_HIGH
    wr8(0x0074, 0x00); wr8(0x0075, 0x00)  -- SYSTEM__THRESH_LOW
    wr8(0x0076, 0x00)  -- SYSTEM__ENABLE_XTALK_PER_QUADRANT
    wr8(0x0077, 0x02)  -- SYSTEM__SEED_CONFIG (EVEN_UPDATE_ONLY)
    wr8(REG_SD_CONFIG__WOI_SD0, woi_sd0_val)  -- 0x0078
    wr8(0x0079, woi_sd1_val)  -- SD_CONFIG__WOI_SD1
    wr8(REG_SD_CONFIG__INITIAL_PHASE_SD0, 0x0A)  -- 0x007A
    wr8(0x007B, 0x0A)  -- SD_CONFIG__INITIAL_PHASE_SD1
    wr8(REG_SYSTEM__GROUPED_PARAMETER_HOLD_1, 0x01)  -- 0x007C
    wr8(REG_SD_CONFIG__FIRST_ORDER_SELECT, 0x00)  -- 0x007D (2nd order)
    wr8(REG_SD_CONFIG__QUANTIFIER, 0x02)  -- 0x007E (2nd order -> 1024)
    wr8(REG_ROI_CONFIG__USER_ROI_CENTRE_SPAD, 0xC7)  -- 0x007F (SPAD 199)
    wr8(REG_ROI_CONFIG__USER_ROI_REQUESTED_GLOBAL_XY_SIZE, 0xFF)  -- 0x0080 (16x16)
    wr8(REG_SYSTEM__SEQUENCE_CONFIG, SEQUENCE_CONFIG_STD)  -- 0x0081 = 0x6B
    wr8(REG_SYSTEM__GROUPED_PARAMETER_HOLD, 0x02)  -- 0x0082

    -- === System Control (0x0083 起, 5 字节) ===
    wr8(REG_POWER_MANAGEMENT__GO1_POWER_FORCE, 0x00)  -- 0x0083
    wr8(REG_SYSTEM__STREAM_COUNT_CTRL, 0x00)          -- 0x0084
    wr8(REG_FIRMWARE__ENABLE, 0x01)                   -- 0x0085
    wr8(REG_SYSTEM__INTERRUPT_CLEAR, CLEAR_RANGE_INT) -- 0x0086 = 0x01 (清 range 中断)

    log.info("exs_vl53l1x", string.format("预设模式配置写入完成 (mode=%s)", mode))
    return true
end

-- 等待数据就绪
-- 如果配置了 GPIO1 中断引脚，直接读 GPIO 电平判断；否则通过 I2C 读 TIO_HV_STATUS
local function wait_data_ready(timeout_ms)
    timeout_ms = timeout_ms or 1000
    local waited = 0

    if g_int1_gpio then
        -- 用 GPIO1 引脚电平判断（ACTIVE_LOW：触发时低电平；ACTIVE_HIGH：触发时高电平）
        while waited < timeout_ms do
            local level = gpio.get(g_int1_gpio)
            -- 因设了 PULLUP，ACTIVE_LOW 触发时引脚被拉低
            if g_int_active_high then
                if level == 1 then return true end
            else
                if level == 0 then return true end
            end
            sys.wait(1)
            waited = waited + 1
        end
        return false
    end

    -- 无 GPIO1 时通过 I2C 读 GPIO__TIO_HV_STATUS (0x0031) bit0
    while waited < timeout_ms do
        local tio = rd8(REG_GPIO__TIO_HV_STATUS)
        if tio then
            local bit0 = tio & 0x01
            if g_int_active_high then
                if bit0 == 1 then return true end
            else
                if bit0 == 0 then return true end
            end
        end
        sys.wait(5)
        waited = waited + 5
    end
    return false
end

-- 清 range 中断 + 触发下一次测量（对照官方 VL53L1_clear_interrupt_and_enable_next_range）
local function clear_int_and_start_next()
    wr8(REG_SYSTEM__INTERRUPT_CLEAR, CLEAR_RANGE_INT)  -- 0x0086 = 0x01
    wr8(REG_SYSTEM__MODE_START, MODE_START_STANDARD)   -- 0x0087 = 0x21
end

-- ==================== 外部 API ====================

-- 初始化并启动测距
-- config 字段：
--   i2c_id     硬件 I2C 总线 id（与 scl/sda 二选一）
--   scl        软件 I2C SCL 引脚（与 i2c_id 二选一）
--   sda        软件 I2C SDA 引脚
--   xshut      硬件复位引脚（可选，不传则用软复位）
--   range_mode 测距模式: "standard"(默认,约2.9m) / "short"(约1.36m,抗强光) / "long"(约4.6m)
--   xtalk_offset 串扰校准偏移值，由 calibrate_xtalk() 返回（可选，传入后自动写入寄存器）
--   int1       中断配置表（可选）：{int_gpio=GPIO端口号, cb=回调函数}
--                 int_gpio：GPIO端口号（不是pin引脚号），如GPIO10填10
--                 cb：数据回调(data)（可选），不传则用 get_int_flag() 轮询
function exs_vl53l1x.setup(config)
    if type(config) ~= "table" then
        log.error("exs_vl53l1x.setup 参数错误")
        return false
    end

    if config.xshut then g_xshut_pin = config.xshut end

    -- I2C 初始化
    if config.scl and config.sda then
        g_scl_pin = config.scl; g_sda_pin = config.sda
        if config.i2c_id then
            i2c_bus_recovery()
            if i2c.setup(config.i2c_id, i2c.SLOW) == 0 then
                log.error("exs_vl53l1x.setup 硬件 I2C 失败"); return false
            end
            g_i2c_bus = config.i2c_id; g_is_soft = false
        else
            i2c_bus_recovery()
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then log.error("exs_vl53l1x.setup 软件 I2C 失败"); return false end
            g_is_soft = true
        end
    else
        local id = config.i2c_id or 0
        if i2c.setup(id, i2c.SLOW) == 0 then log.error("exs_vl53l1x.setup I2C 失败"); return false end
        g_i2c_bus = id; g_is_soft = false; g_scl_pin = nil; g_sda_pin = nil
    end

    -- 复位（优先硬件 XSHUT，否则软复位）
    if g_xshut_pin then
        gpio.setup(g_xshut_pin, gpio.OUTPUT, gpio.PULLUP, 0); sys.wait(5)
        gpio.set(g_xshut_pin, 1); sys.wait(5)
    else
        soft_reset()
    end

    -- 等待固件就绪
    if not wait_firmware_ready() then return false end

    -- 写入预设模式配置（支持 range_mode="standard" 或 "long"）
    local range_mode = config.range_mode or "standard"
    write_preset_config(range_mode)

    -- 如果传入了校准后的串扰偏移值,写入串扰补偿寄存器
    -- xtalk_offset 由 calibrate_xtalk() 返回,或从文件加载
    local xtalk_off = config.xtalk_offset
    if xtalk_off and type(xtalk_off) == "number" and xtalk_off > 0 and xtalk_off <= 65535 then
        local plane_offset = (xtalk_off * 512 + 500) / 1000  -- 与 calibrate_xtalk 同样的转换
        wr8(REG_ALGO__CROSSTALK_COMPENSATION_PLANE_OFFSET_KCPS, (plane_offset >> 8) & 0xFF)
        wr8(REG_ALGO__CROSSTALK_COMPENSATION_PLANE_OFFSET_KCPS + 1, plane_offset & 0xFF)
        wr8(REG_ALGO__CROSSTALK_COMPENSATION_X_PLANE_GRADIENT_KCPS, 0x00)
        wr8(REG_ALGO__CROSSTALK_COMPENSATION_X_PLANE_GRADIENT_KCPS + 1, 0x00)
        wr8(REG_ALGO__CROSSTALK_COMPENSATION_Y_PLANE_GRADIENT_KCPS, 0x00)
        wr8(REG_ALGO__CROSSTALK_COMPENSATION_Y_PLANE_GRADIENT_KCPS + 1, 0x00)
        log.info("exs_vl53l1x", string.format("串扰补偿已应用: offset=%d", xtalk_off))
    end

    -- 验证芯片标识
    local mid = rd8(REG_IDENTIFICATION__MODEL_ID)
    local mt = rd8(REG_IDENTIFICATION__MODULE_TYPE)
    log.info("exs_vl53l1x", string.format("芯片 MID=0x%02X MT=0x%02X", mid or 0, mt or 0))
    if mid ~= MODEL_ID_VAL then
        log.warn("exs_vl53l1x", string.format("MID 不符（期望 0x%02X 实际 0x%02X）", MODEL_ID_VAL, mid or 0))
    end

    -- 读取中断极性，用于后续 wait_data_ready 判断
    local gpio_mux = rd8(REG_GPIO_HV_MUX__CTRL) or 0
    g_int_active_high = ((gpio_mux & GPIO_POL_ACTIVE_LOW) == 0)  -- bit4=0 -> ACTIVE_HIGH

    -- 启动测距：写 SYSTEM__MODE_START = 0x21 (STREAMING | SINGLE_SD | BACKTOBACK)
    wr8(REG_SYSTEM__MODE_START, MODE_START_STANDARD)
    sys.wait(200)  -- 等第一帧测量完成

    g_ready = true

    -- GPIO1 中断引脚注册（放在 g_ready=true 之后，避免注册时的电平触发回调导致 get_data 报"请先 setup"）
    if config.int1 and type(config.int1) == "table" and config.int1.int_gpio then
        g_int1_gpio = config.int1.int_gpio
        g_int1_cb = config.int1.cb
        g_int1_flag = false
        gpio.setup(g_int1_gpio, function()
            g_int1_flag = true
            if g_int1_cb and g_ready then
                local data = exs_vl53l1x.get_data()
                if data then g_int1_cb(data) end
            end
        end, gpio.PULLUP, gpio.FALLING)
        log.info("exs_vl53l1x", string.format("GPIO1 中断已注册, gpio=%d cb=%s",
            g_int1_gpio, (g_int1_cb and "有" or "无")))
    end

    log.info("exs_vl53l1x", "初始化完成，Standard Ranging 测距已启动")
    return true
end

-- 读取一帧测距数据（阻塞等待数据就绪。自动跳过 stream_count=0 的无效帧）
-- 返回 table：{ distance, status, status_str, stream_count } 或 nil
function exs_vl53l1x.get_data()
    if not g_ready then log.error("exs_vl53l1x.get_data 请先 setup()"); return nil end

    for retry = 1, 4 do
        -- 等待数据就绪（最长 1000ms）
        if not wait_data_ready(1000) then
            log.warn("exs_vl53l1x", "数据就绪超时")
            -- 超时也要清中断+触发下一次，避免卡死
            clear_int_and_start_next()
            return nil
        end

        -- 读测距状态 (0x0089)
        local status_val = rd8(REG_RESULT__RANGE_STATUS)
        if not status_val then return nil end
        local raw_status = status_val & RANGE_STATUS_MASK  -- bit[4:0], 官方 device_error

        -- 读 stream_count (0x008B)
        local stream_count = rd8(REG_RESULT__STREAM_COUNT)

        -- 官方第一帧处理(vl53l1_api_core.c::VL53L1_copy_sys_and_core_results_to_range_results)：
        -- stream_count==0 且 raw==RANGECOMPLETE(9) -> RANGECOMPLETE_NO_WRAP_CHECK(1)
        if stream_count == 0 and raw_status == RAW_RANGECOMPLETE then
            raw_status = RAW_RANGECOMPLETE_NOWRAP
        end

        -- 官方 ConvertStatusLite() 映射 raw device_error -> user range_status
        local user_status = convert_range_status(raw_status)
        local status_str = RANGE_STATUS_LIST[user_status] or ("未知(" .. user_status .. ")")

        -- 读距离 (0x0096, 16-bit)
        local distance = rd16(REG_RESULT__FINAL_CROSSTALK_CORRECTED_RANGE_MM_SD0) or 0

        -- 清中断 + 触发下一次测量（back-to-back 模式必需）
        clear_int_and_start_next()

        -- 跳过 stream_count=0 的无效帧（setup/wakeup 后的第一帧数据不可用）
        if stream_count == 0 then
            sys.wait(10)
        else
            return {
                distance     = distance,
                status       = user_status,
                status_str   = status_str,
                stream_count = stream_count,
            }
        end
    end

    log.warn("exs_vl53l1x", "连续 4 帧 stream=0，跳过")
    return nil
end

-- 查询 GPIO1 中断触发标志
-- 查询后自动清除标志。适合高频场景（不传 cb 时轮询用）
function exs_vl53l1x.get_int_flag()
    local f = g_int1_flag
    if f then g_int1_flag = false end
    return f
end

-- 串扰校准
-- 参考 SparkFun VL53L1X_CalibrateXtalk 简化实现
-- 用法：
--   local xtalk = exs_vl53l1x.calibrate_xtalk({
--       scl = 31, sda = 30,
--       target_distance_mm = 400,   -- 目标距离,默认400mm
--       samples = 50,                 -- 采样帧数,默认50
--   })
--   if xtalk then
--       -- 后续 setup({xtalk_offset = xtalk}) 即可使用校准值
--       -- xtalk 也可保存到文件,下次直接用
--   end
-- 注意：
--   1. 在校准前,在传感器正前方 target_distance_mm 处放一个纯白平面目标(如白纸板)
--   2. 确保目标正对传感器,距离尽量精确
--   3. 环境光线尽量稳定,避免强光直射
--   4. 校准完成后,后续 setup 传入 xtalk_offset 即可
function exs_vl53l1x.calibrate_xtalk(config)
    if type(config) ~= "table" then
        log.error("exs_vl53l1x.calibrate_xtalk 参数错误")
        return nil
    end

    local target_dist_mm = config.target_distance_mm or 400
    local num_samples = config.samples or 50

    log.info("exs_vl53l1x", "===== 串扰校准开始 =====")
    log.info("exs_vl53l1x", string.format("目标距离=%dmm 采样帧数=%d", target_dist_mm, num_samples))
    log.info("exs_vl53l1x", "请确保传感器正前方放置纯白平面目标")

    -- 保存原始 g_ready 状态,校准完后恢复
    local saved_ready = g_ready
    local saved_bus = g_i2c_bus
    local saved_soft = g_is_soft
    local saved_scl = g_scl_pin
    local saved_sda = g_sda_pin

    -- 如果已经 setup 过,先关闭
    if g_ready then
        wr8(REG_SYSTEM__MODE_START, MODE_ABORT)
        sys.wait(2)
        g_ready = false
    end

    -- I2C 初始化
    if config.scl and config.sda then
        if config.i2c_id then
            i2c.setup(config.i2c_id, i2c.SLOW)
            g_i2c_bus = config.i2c_id; g_is_soft = false
        else
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then
                log.error("exs_vl53l1x.calibrate_xtalk 软件 I2C 失败")
                return nil
            end
            g_is_soft = true; g_scl_pin = config.scl; g_sda_pin = config.sda
        end
    else
        local id = config.i2c_id or 0
        if i2c.setup(id, i2c.SLOW) == 0 then
            log.error("exs_vl53l1x.calibrate_xtalk I2C 失败")
            return nil
        end
        g_i2c_bus = id; g_is_soft = false
    end

    -- 复位 + 等固件就绪
    soft_reset()
    if not wait_firmware_ready() then return nil end

    -- 写标准模式预设配置
    write_preset_config("standard")

    -- 先清零串扰补偿寄存器（关键：校准前必须清零）
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_PLANE_OFFSET_KCPS, 0x00)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_PLANE_OFFSET_KCPS + 1, 0x00)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_X_PLANE_GRADIENT_KCPS, 0x00)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_X_PLANE_GRADIENT_KCPS + 1, 0x00)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_Y_PLANE_GRADIENT_KCPS, 0x00)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_Y_PLANE_GRADIENT_KCPS + 1, 0x00)

    -- 读取中断极性
    local gpio_mux = rd8(REG_GPIO_HV_MUX__CTRL) or 0
    g_int_active_high = ((gpio_mux & GPIO_POL_ACTIVE_LOW) == 0)

    -- 启动测距
    wr8(REG_SYSTEM__MODE_START, MODE_START_STANDARD)
    sys.wait(50)

    -- 采集样本
    local sum_signal = 0
    local sum_distance = 0
    local sum_spad = 0
    local valid_count = 0

    for i = 1, num_samples + 10 do  -- 多采样10帧,跳过开头的无效帧
        if not wait_data_ready(200) then
            -- 超时也要清中断
            wr8(REG_SYSTEM__INTERRUPT_CLEAR, CLEAR_RANGE_INT)
            wr8(REG_SYSTEM__MODE_START, MODE_START_STANDARD)
            sys.wait(5)
            goto continue
        end

        local stream = rd8(REG_RESULT__STREAM_COUNT) or 0
        local distance = rd16(REG_RESULT__FINAL_CROSSTALK_CORRECTED_RANGE_MM_SD0) or 0
        local signal = rd16(REG_RESULT__PEAK_SIGNAL_COUNT_RATE_CROSSTALK_CORRECTED_MCPS_SD0) or 0
        local spad = rd16(REG_RESULT__DSS_ACTUAL_EFFECTIVE_SPADS_SD0) or 0

        -- 清中断 + 触发下一帧
        wr8(REG_SYSTEM__INTERRUPT_CLEAR, CLEAR_RANGE_INT)
        wr8(REG_SYSTEM__MODE_START, MODE_START_STANDARD)

        -- 跳过无效帧
        if stream == 0 or distance > 65500 then
            goto continue
        end
        if distance < 10 or distance > target_dist_mm * 2 then
            goto continue
        end
        if spad == 0 then
            goto continue
        end

        valid_count = valid_count + 1
        sum_distance = sum_distance + distance
        sum_signal = sum_signal + signal
        sum_spad = sum_spad + spad

        if valid_count % 10 == 0 then
            log.info("exs_vl53l1x", string.format("  校准采样[%d/%d] 距离=%dmm", valid_count, num_samples, distance))
        end

        if valid_count >= num_samples then
            break
        end

        ::continue::
    end

    -- 停止测距
    wr8(REG_SYSTEM__MODE_START, MODE_ABORT)
    sys.wait(2)
    wr8(REG_SYSTEM__MODE_START, 0x00)

    log.info("exs_vl53l1x", string.format("校准采样有效帧=%d", valid_count))

    if valid_count < 10 then
        log.error("exs_vl53l1x", "校准采样不足,请检查目标摆放和环境")
        g_ready = saved_ready
        return nil
    end

    local avg_distance = sum_distance / valid_count
    local avg_signal = sum_signal / valid_count
    local avg_spad = sum_spad / valid_count

    log.info("exs_vl53l1x", string.format("均值: 距离=%.1fmm 信号=%.1f spad=%.1f", avg_distance, avg_signal, avg_spad))

    -- 计算串扰值(SparkFun公式: 512 * avgSignalRate * (1 - avgDistance/targetDist) / avgSpadNb)
    local raw_xtalk = 512 * avg_signal * (1 - avg_distance / target_dist_mm) / avg_spad

    -- 限制在合理范围(0~64, 超出可能计算错误)
    if raw_xtalk < 0 then raw_xtalk = 0 end
    if raw_xtalk > 65535 then raw_xtalk = 65535 end

    local xtalk_val = math.floor(raw_xtalk + 0.5)
    log.info("exs_vl53l1x", string.format("串扰值=%d (raw=%.2f)", xtalk_val, raw_xtalk))

    -- 写回串扰补偿寄存器(7.9格式: 值*1000>>9, 转化为kcps)
    -- SparkFun公式: (xtalkValue << 9) / 1000 写回, 即 xtalk_val * 512 / 1000
    local plane_offset = (xtalk_val * 512 + 500) / 1000  -- 四舍五入
    local po_hi = (plane_offset >> 8) & 0xFF
    local po_lo = plane_offset & 0xFF

    wr8(REG_ALGO__CROSSTALK_COMPENSATION_PLANE_OFFSET_KCPS, po_hi)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_PLANE_OFFSET_KCPS + 1, po_lo)
    -- X/Y梯度置0(简化校准,不区分平面方向)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_X_PLANE_GRADIENT_KCPS, 0x00)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_X_PLANE_GRADIENT_KCPS + 1, 0x00)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_Y_PLANE_GRADIENT_KCPS, 0x00)
    wr8(REG_ALGO__CROSSTALK_COMPENSATION_Y_PLANE_GRADIENT_KCPS + 1, 0x00)

    log.info("exs_vl53l1x", "串扰校准完成")
    log.info("exs_vl53l1x", "后续 setup 时传入 {xtalk_offset = " .. xtalk_val .. "} 即可使用校准值")
    log.info("exs_vl53l1x", "===== 串扰校准结束 =====")

    -- 恢复原始状态(不破坏已 setup 的连接)
    g_ready = saved_ready
    if not saved_ready then
        g_i2c_bus = saved_bus; g_is_soft = saved_soft
        g_scl_pin = saved_scl; g_sda_pin = saved_sda
    end

    return xtalk_val
end
function exs_vl53l1x.sleep()
    if not g_ready then return end
    -- 写 ABORT 让正在进行的测量立即停止，ABORT 位自动清零
    wr8(REG_SYSTEM__MODE_START, MODE_ABORT)
    sys.wait(2)
    -- 再写 0x00 确保模式位清零
    wr8(REG_SYSTEM__MODE_START, 0x00)
    log.info("exs_vl53l1x", "已进入软件待机")
end

-- 从软件待机唤醒（重新启动测距）
-- 与 sleep() 配对使用：sleep 写 mode_start=0x00 停止，wakeup 写 mode_start=0x21 启动
-- 注意：唤醒前请确保已调用过 setup()，且未调用 close()
function exs_vl53l1x.wakeup()
    if not g_ready then
        log.warn("exs_vl53l1x.wakeup 未初始化，请先 setup()")
        return false
    end
    -- 清可能残留的中断，再写 mode_start 启动测距
    wr8(REG_SYSTEM__INTERRUPT_CLEAR, CLEAR_RANGE_INT)
    wr8(REG_SYSTEM__MODE_START, MODE_START_STANDARD)
    sys.wait(10)
    log.info("exs_vl53l1x", "已从软件待机唤醒，测距已恢复")
    return true
end

-- 关闭传感器
function exs_vl53l1x.close()
    if not g_ready then return end
    -- 注销 GPIO1 中断
    if g_int1_gpio then
        gpio.setup(g_int1_gpio, nil)
        g_int1_gpio = nil; g_int1_cb = nil; g_int1_flag = false
    end
    wr8(REG_SYSTEM__MODE_START, MODE_ABORT)
    sys.wait(2)
    wr8(REG_SYSTEM__MODE_START, 0x00)
    g_ready = false; g_i2c_bus = nil
    log.info("exs_vl53l1x", "传感器已关闭")
end

-- 获取版本号
function exs_vl53l1x.version()
    return "202607201200"
end

return exs_vl53l1x
