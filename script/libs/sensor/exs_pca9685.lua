--[[
@module  exs_pca9685
@summary PCA9685 16路 PWM/Servo 舵机驱动扩展库
@version 1.0
@date    2026.08.25
@author  沈园园
@usage
本文件为 PCA9685 I2C 16 通道 12 位 PWM/Servo 舵机驱动芯片的 LuatOS 扩展库，核心业务逻辑为：
1、配置主机和 PCA9685 之间的 I2C 通信参数，支持自动识别从设备地址；
2、配置 PCA9685 的 PWM 输出频率（24Hz~1526Hz）与 16 路 PWM 占空比输出；
3、支持舵机角度控制（0°~180° 转换为脉宽输出）。

本文件的对外接口有 9 个：
1、exs_pca9685.init(i2c_id, slave_address, pwm_freq)：初始化 PCA9685
2、exs_pca9685.deinit()：关闭 PCA9685 通信
3、exs_pca9685.set_pwm_freq(freq)：设置 PWM 频率
4、exs_pca9685.set_pwm(channel, duty)：设置通道占空比
5、exs_pca9685.set_pwm_range(channel, on_value, off_value)：设置通道 ON/OFF 计数器
6、exs_pca9685.set_servo_angle(channel, angle, min_pulse, max_pulse)：设置舵机角度
7、exs_pca9685.set_all_pwm(duty)：设置所有通道占空比
8、exs_pca9685.set_output_mode(outdrv, invert)：配置输出模式
9、exs_pca9685.version()：获取版本号

-- 版本更新说明
-- 版本号：202608252000
-- 1、更新时间：2026-08-25 20:00
-- 2、更新内容
  - 第一版，实现 PCA9685 基础驱动功能
  - 自动识别从设备地址功能（扫描 0x40~0x7F）
  - 支持 PWM 频率设置（24Hz~1526Hz）
  - 支持 16 通道占空比控制（12 位 0~4095）
  - 支持舵机角度控制（0°~180°）
  - 支持全通道同步控制（ALL_LED 寄存器）
]]

local exs_pca9685 = {}

-- ==================== 模块常量 ====================

-- PCA9685 I2C 从机地址范围（固定前缀 1000 + A5~A0 硬件地址引脚）
-- 数据手册 7.1 节：地址范围 0x40~0x7F，A5~A0 全接地时为默认地址 0x40
local SLAVE_ADDRESS_MIN = 0x40    -- 地址范围下限（A5~A0 全 0，默认地址）
local SLAVE_ADDRESS_MAX = 0x7F    -- 地址范围上限（A5~A0 全 1）

-- PCA9685 寄存器地址（数据手册 Table 4）
local REG_MODE1         = 0x00    -- 模式寄存器1
local REG_MODE2         = 0x01    -- 模式寄存器2
local REG_LED0_ON_L     = 0x06    -- LED0 ON 计数器低字节
local REG_LED0_ON_H     = 0x07    -- LED0 ON 计数器高字节（bit4=FULL ON）
local REG_LED0_OFF_L    = 0x08    -- LED0 OFF 计数器低字节
local REG_LED0_OFF_H    = 0x09    -- LED0 OFF 计数器高字节（bit4=FULL OFF）
local REG_ALL_LED_ON_L  = 0xFA    -- 全通道 ON 计数器低字节（W only）
local REG_ALL_LED_ON_H  = 0xFB    -- 全通道 ON 计数器高字节（W only）
local REG_ALL_LED_OFF_L = 0xFC    -- 全通道 OFF 计数器低字节（W only）
local REG_ALL_LED_OFF_H = 0xFD    -- 全通道 OFF 计数器高字节（W only）
local REG_PRE_SCALE     = 0xFE    -- PWM 输出频率预分频器

-- MODE1 寄存器位定义（数据手册 Table 5，复位值 0x11：SLEEP=1、ALLCALL=1）
local MODE1_RESTART     = 0x80    -- bit7 重启 PWM 输出（写1触发，写0无效）
local MODE1_EXTCLK      = 0x40    -- bit6 使用外部时钟（默认内部 25MHz）
local MODE1_AI          = 0x20    -- bit5 寄存器自动递增
local MODE1_SLEEP       = 0x10    -- bit4 低功耗模式（振荡器关闭）
local MODE1_SUB1        = 0x08    -- bit3 响应子地址1
local MODE1_SUB2        = 0x04    -- bit2 响应子地址2
local MODE1_SUB3        = 0x02    -- bit1 响应子地址3
local MODE1_ALLCALL     = 0x01    -- bit0 响应全调用地址

-- MODE2 寄存器位定义（数据手册 Table 6，复位值 0x04：OUTDRV=1 推挽）
local MODE2_INVRT       = 0x10    -- bit4 输出逻辑状态反转
local MODE2_OCH         = 0x08    -- bit3 输出改变时机（0=STOP 命令，1=ACK）
local MODE2_OUTDRV      = 0x04    -- bit2 输出驱动结构（1=推挽，0=开漏）
local MODE2_OUTNE1      = 0x02    -- bit1 OE=1 时输出行为
local MODE2_OUTNE0      = 0x01    -- bit0 OE=1 时输出行为

-- LEDn_ON_H / LEDn_OFF_H 位定义（数据手册 Table 7）
-- LEDn_ON_H[4]=1 输出常开；LEDn_OFF_H[4]=1 输出常关（FULL OFF 优先）
local LED_FULL_ON       = 0x10    -- bit4 常开（写 LEDn_ON_H[4]=1）
local LED_FULL_OFF      = 0x10    -- bit4 常关（写 LEDn_OFF_H[4]=1）

-- 通道与 PWM 计数常量
local CHANNEL_MAX       = 16      -- 通道数量（LED0~LED15）
local PWM_COUNT_MAX     = 4096    -- 12 位计数上限（0~4095）
local PWM_DUTY_MAX      = 4095    -- 最大占空比计数值
local PWM_FULL          = 4096    -- FULL ON / FULL OFF 标记值

-- 内部振荡器频率（Hz）
local OSC_CLOCK         = 25000000 -- 25MHz 内部振荡器（数据手册 7.3.5）

-- PWM 频率范围（数据手册 7.3.5：PRE_SCALE 0x03~0xFF）
local PWM_FREQ_MIN      = 24      -- 最小频率（PRE_SCALE=0xFF）
local PWM_FREQ_MAX      = 1526    -- 最大频率（PRE_SCALE=0x03）
local PRE_SCALE_MIN     = 3       -- 硬件强制 PRE_SCALE 最小值

-- 舵机默认参数（单位 ms，标准舵机 50Hz 20ms 周期）
local SERVO_MIN_PULSE   = 0.5     -- 0° 对应脉宽
local SERVO_MAX_PULSE   = 2.5     -- 180° 对应脉宽
local SERVO_MIN_ANGLE   = 0       -- 最小角度
local SERVO_MAX_ANGLE   = 180     -- 最大角度

-- ==================== 内部状态 ====================

-- 运行时状态
exs_pca9685.i2c_id        = nil   -- 主机 I2C 总线 ID
exs_pca9685.slave_address = nil   -- 从设备地址
exs_pca9685.pwm_freq      = nil   -- 当前 PWM 频率（Hz）

-- ==================== I2C 底层操作 ====================

-- 写入 PCA9685 寄存器
-- @param reg 寄存器地址（0x00~0xFF）
-- @param value 要写入的数据（0x00~0xFF）
-- @return boolean 成功返回 true
local function write_register(reg, value)
    if not exs_pca9685.i2c_id or not exs_pca9685.slave_address then
        log.error("exs_pca9685", "设备未初始化")
        return false
    end
    local result = i2c.send(exs_pca9685.i2c_id, exs_pca9685.slave_address, {reg, value})
    return result
end

-- 读取 PCA9685 寄存器
-- @param reg 寄存器地址（0x00~0xFF）
-- @return number 读取到的 1 字节数据，失败返回 nil
local function read_register(reg)
    if not exs_pca9685.i2c_id or not exs_pca9685.slave_address then
        log.error("exs_pca9685", "设备未初始化")
        return nil
    end
    if not i2c.send(exs_pca9685.i2c_id, exs_pca9685.slave_address, reg) then
        return nil
    end
    local data = i2c.recv(exs_pca9685.i2c_id, exs_pca9685.slave_address, 1)
    if data and #data == 1 then
        return string.byte(data, 1)
    end
    return nil
end

-- 写入单通道 ON/OFF 计数器（12 位，支持 FULL ON/FULL OFF）
-- @param channel 通道号（0~15）
-- @param on_value ON 计数器值（0~4095，传 4096 表示 FULL ON 常开）
-- @param off_value OFF 计数器值（0~4095，传 4096 表示 FULL OFF 常关）
-- @return boolean 成功返回 true
local function write_channel(channel, on_value, off_value)
    if channel < 0 or channel >= CHANNEL_MAX then
        log.error("exs_pca9685", "通道号越界:", channel)
        return false
    end
    local reg_base = REG_LED0_ON_L + channel * 4
    -- 写入 ON 计数器（LEDn_ON_L + LEDn_ON_H）
    if on_value >= PWM_COUNT_MAX then
        -- FULL ON：LEDn_ON_H[4]=1，输出常开（数据手册 7.3.3）
        if not write_register(reg_base + 0, 0x00) then return false end
        if not write_register(reg_base + 1, LED_FULL_ON) then return false end
    else
        if not write_register(reg_base + 0, on_value & 0xFF) then return false end
        if not write_register(reg_base + 1, (on_value >> 8) & 0x0F) then return false end
    end
    -- 写入 OFF 计数器（LEDn_OFF_L + LEDn_OFF_H）
    if off_value >= PWM_COUNT_MAX then
        -- FULL OFF：LEDn_OFF_H[4]=1，输出常关
        -- 数据手册 7.3.4 要求 ON 与 OFF 计数不得相同，全关请使用 FULL OFF
        if not write_register(reg_base + 2, 0x00) then return false end
        if not write_register(reg_base + 3, LED_FULL_OFF) then return false end
    else
        if not write_register(reg_base + 2, off_value & 0xFF) then return false end
        if not write_register(reg_base + 3, (off_value >> 8) & 0x0F) then return false end
    end
    return true
end

-- ==================== 对外接口 ====================

-- 初始化 PCA9685，配置 I2C 通信参数，自动识别从设备地址
-- @param i2c_id 主机 I2C 总线 ID（Air780EHV 默认 1）
-- @param slave_address 从机地址（0x40~0x7F，默认 0x40；传 nil 自动扫描识别）
-- @param pwm_freq PWM 频率（Hz，24~1526，默认 50Hz 适配舵机）
-- @return boolean 成功返回 true
function exs_pca9685.init(i2c_id, slave_address, pwm_freq)
    -- 参数默认值
    if i2c_id == nil then i2c_id = 1 end
    if slave_address == nil then slave_address = SLAVE_ADDRESS_MIN end
    if pwm_freq == nil then pwm_freq = 50 end

    -- 初始化 I2C（400kHz 快速模式）
    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("exs_pca9685.init", "I2C 初始化失败, i2c_id=", i2c_id)
        return false
    end
    exs_pca9685.i2c_id = i2c_id

    -- 从设备地址识别：指定地址则直接验证，否则扫描 0x40~0x7F
    local found_addr = nil
    if slave_address >= SLAVE_ADDRESS_MIN and slave_address <= SLAVE_ADDRESS_MAX then
        -- 验证指定地址：读取 MODE1 寄存器
        if i2c.send(i2c_id, slave_address, REG_MODE1) then
            local data = i2c.recv(i2c_id, slave_address, 1)
            if data and #data == 1 then
                found_addr = slave_address
            end
        end
        if not found_addr then
            log.error("exs_pca9685.init", "指定从设备地址无响应:", slave_address)
            return false
        end
    else
        -- 扫描地址范围，通过读取 MODE1 寄存器识别 PCA9685 从设备
        for addr = SLAVE_ADDRESS_MIN, SLAVE_ADDRESS_MAX do
            if i2c.send(i2c_id, addr, REG_MODE1) then
                local data = i2c.recv(i2c_id, addr, 1)
                if data and #data == 1 then
                    found_addr = addr
                    break
                end
            end
        end
        if not found_addr then
            log.error("exs_pca9685.init", "未识别到 PCA9685 从设备，请检查接线/供电/地址配置")
            return false
        end
    end
    exs_pca9685.slave_address = found_addr
    log.info("exs_pca9685.init", "从设备地址识别成功:", found_addr)

    -- 配置 MODE1：清除 SLEEP（退出休眠）、使能 AI（寄存器自动递增）、保留 ALLCALL
    -- 复位后 MODE1 = 0x11（SLEEP=1、ALLCALL=1），需先退出休眠才能正常工作
    if not write_register(REG_MODE1, MODE1_AI | MODE1_ALLCALL) then
        log.error("exs_pca9685.init", "写 MODE1 失败")
        return false
    end

    -- 配置 MODE2：推挽输出（OUTDRV=1，数据手册默认即为推挽，显式设置确保一致性）
    if not write_register(REG_MODE2, MODE2_OUTDRV) then
        log.error("exs_pca9685.init", "写 MODE2 失败")
        return false
    end

    -- 设置 PWM 频率
    if not exs_pca9685.set_pwm_freq(pwm_freq) then
        log.error("exs_pca9685.init", "PWM 频率设置失败:", pwm_freq)
        return false
    end

    log.info("exs_pca9685.init", "初始化完成, i2c=", i2c_id, "addr=0x" .. string.format("%02X", found_addr), "freq=", pwm_freq)
    return true
end

-- 关闭 PCA9685 通信，释放 I2C 总线
-- @return boolean 成功返回 true
function exs_pca9685.deinit()
    if not exs_pca9685.i2c_id or not exs_pca9685.slave_address then
        log.warn("exs_pca9685.deinit", "设备未初始化")
        return false
    end
    -- 将所有通道设置为 FULL OFF（输出常关），避免关闭 I2C 后输出状态不确定
    if not write_register(REG_ALL_LED_ON_L, 0x00) then return false end
    if not write_register(REG_ALL_LED_ON_H, 0x00) then return false end
    if not write_register(REG_ALL_LED_OFF_L, 0x00) then return false end
    if not write_register(REG_ALL_LED_OFF_H, LED_FULL_OFF) then return false end
    -- 关闭 I2C
    i2c.close(exs_pca9685.i2c_id)
    log.info("exs_pca9685.deinit", "关闭 I2C 成功, i2c=", exs_pca9685.i2c_id)
    exs_pca9685.i2c_id = nil
    exs_pca9685.slave_address = nil
    exs_pca9685.pwm_freq = nil
    return true
end

-- 设置 PWM 频率
-- @param freq 目标频率（Hz，24~1526）
-- @return boolean 成功返回 true
function exs_pca9685.set_pwm_freq(freq)
    if not exs_pca9685.i2c_id or not exs_pca9685.slave_address then
        log.error("exs_pca9685", "设备未初始化")
        return false
    end
    -- 频率范围校验
    if freq < PWM_FREQ_MIN or freq > PWM_FREQ_MAX then
        log.error("exs_pca9685.set_pwm_freq", "频率越界(24~1526Hz):", freq)
        return false
    end
    -- PRE_SCALE 计算：prescale = round(25MHz / (4096 * freq)) - 1（数据手册 7.3.5）
    local prescale = math.floor(OSC_CLOCK / (PWM_COUNT_MAX * freq) + 0.5) - 1
    if prescale < PRE_SCALE_MIN then prescale = PRE_SCALE_MIN end
    -- 1、读取 MODE1
    local mode1 = read_register(REG_MODE1)
    if not mode1 then return false end
    -- 2、置位 SLEEP（进入休眠，PRE_SCALE 仅在 SLEEP 模式可写）
    if not write_register(REG_MODE1, mode1 | MODE1_SLEEP) then return false end
    -- 3、写入 PRE_SCALE
    if not write_register(REG_PRE_SCALE, prescale) then return false end
    -- 4、清除 SLEEP（退出休眠）
    if not write_register(REG_MODE1, mode1 & ~MODE1_SLEEP) then return false end
    -- 5、等待振荡器稳定（数据手册 7.3.1.1 要求 ≥500μs）
    sys.wait(1)
    -- 6、若休眠前有 PWM 在运行（RESTART=1），写 RESTART 重启输出（数据手册 7.3.1.1）
    if (mode1 & MODE1_RESTART) ~= 0 then
        if not write_register(REG_MODE1, (mode1 & ~MODE1_SLEEP) | MODE1_RESTART) then return false end
    end
    exs_pca9685.pwm_freq = freq
    log.info("exs_pca9685.set_pwm_freq", "频率设置成功:", freq, "Hz, prescale=0x", string.format("%02X", prescale))
    return true
end

-- 设置通道 PWM 占空比
-- @param channel 通道号（0~15）
-- @param duty 占空比计数值（0~4095，0=全关 4095≈全开）
-- @return boolean 成功返回 true
function exs_pca9685.set_pwm(channel, duty)
    if channel < 0 or channel >= CHANNEL_MAX then
        log.error("exs_pca9685.set_pwm", "通道号越界:", channel)
        return false
    end
    if duty < 0 or duty > PWM_DUTY_MAX then
        log.error("exs_pca9685.set_pwm", "占空比越界(0~4095):", duty)
        return false
    end
    if duty == 0 then
        -- 全关：使用 FULL OFF（数据手册 7.3.4 建议 ON/OFF 不得相同）
        return write_channel(channel, 0, PWM_FULL)
    end
    -- 正常占空比：ON=0（无相位偏移），OFF=duty
    return write_channel(channel, 0, duty)
end

-- 设置通道 ON/OFF 计数器（支持相位偏移与 FULL ON/FULL OFF）
-- @param channel 通道号（0~15）
-- @param on_value ON 计数器值（0~4095，传 4096 表示 FULL ON 常开）
-- @param off_value OFF 计数器值（0~4095，传 4096 表示 FULL OFF 常关）
-- @return boolean 成功返回 true
function exs_pca9685.set_pwm_range(channel, on_value, off_value)
    if channel < 0 or channel >= CHANNEL_MAX then
        log.error("exs_pca9685.set_pwm_range", "通道号越界:", channel)
        return false
    end
    if on_value < 0 or on_value > PWM_FULL then
        log.error("exs_pca9685.set_pwm_range", "ON 计数值越界(0~4096):", on_value)
        return false
    end
    if off_value < 0 or off_value > PWM_FULL then
        log.error("exs_pca9685.set_pwm_range", "OFF 计数值越界(0~4096):", off_value)
        return false
    end
    -- 数据手册 7.3.4 要求 ON 与 OFF 计数不得相同（FULL ON/OFF 组合除外）
    if on_value < PWM_FULL and off_value < PWM_FULL and on_value == off_value then
        log.error("exs_pca9685.set_pwm_range", "ON 与 OFF 计数不得相同（数据手册 7.3.4 要求）")
        return false
    end
    return write_channel(channel, on_value, off_value)
end

-- 设置舵机角度
-- @param channel 通道号（0~15）
-- @param angle 目标角度（0°~180°）
-- @param min_pulse 0° 对应脉宽（ms，默认 0.5）
-- @param max_pulse 180° 对应脉宽（ms，默认 2.5）
-- @return boolean 成功返回 true
function exs_pca9685.set_servo_angle(channel, angle, min_pulse, max_pulse)
    if channel < 0 or channel >= CHANNEL_MAX then
        log.error("exs_pca9685.set_servo_angle", "通道号越界:", channel)
        return false
    end
    if angle < SERVO_MIN_ANGLE or angle > SERVO_MAX_ANGLE then
        log.error("exs_pca9685.set_servo_angle", "角度越界(0~180):", angle)
        return false
    end
    if min_pulse == nil then min_pulse = SERVO_MIN_PULSE end
    if max_pulse == nil then max_pulse = SERVO_MAX_PULSE end
    -- 角度换算脉宽：pulse = min_pulse + angle/180 * (max_pulse - min_pulse)
    local pulse = min_pulse + (angle / (SERVO_MAX_ANGLE - SERVO_MIN_ANGLE)) * (max_pulse - min_pulse)
    -- 脉宽换算 12 位计数：count = pulse(ms) / 周期(ms) * 4096，周期 = 1000 / 频率
    local freq = exs_pca9685.pwm_freq
    if not freq then freq = 50 end
    local count = math.floor(pulse * freq * PWM_COUNT_MAX / 1000 + 0.5)
    if count < 1 then count = 1 end
    if count > PWM_DUTY_MAX then count = PWM_DUTY_MAX end
    -- 写入 ON=0，OFF=count（占空比 = count/4096）
    return write_channel(channel, 0, count)
end

-- 设置所有通道占空比（通过 ALL_LED 寄存器一次加载全部 16 通道）
-- @param duty 占空比计数值（0~4095，0=全关 4095≈全开）
-- @return boolean 成功返回 true
function exs_pca9685.set_all_pwm(duty)
    if duty < 0 or duty > PWM_DUTY_MAX then
        log.error("exs_pca9685.set_all_pwm", "占空比越界(0~4095):", duty)
        return false
    end
    -- 写入 ALL_LED_ON（ON 计数=0，无相位偏移，清除 FULL ON）
    if not write_register(REG_ALL_LED_ON_L, 0x00) then return false end
    if not write_register(REG_ALL_LED_ON_H, 0x00) then return false end
    if duty == 0 then
        -- 全关：ALL_LED_OFF_H[4]=1（FULL OFF）
        if not write_register(REG_ALL_LED_OFF_L, 0x00) then return false end
        if not write_register(REG_ALL_LED_OFF_H, LED_FULL_OFF) then return false end
    else
        -- 正常占空比：ALL_LED_OFF = duty
        if not write_register(REG_ALL_LED_OFF_L, duty & 0xFF) then return false end
        if not write_register(REG_ALL_LED_OFF_H, (duty >> 8) & 0x0F) then return false end
    end
    log.info("exs_pca9685.set_all_pwm", "所有通道占空比设置成功:", duty)
    return true
end

-- 配置输出模式
-- @param outdrv 输出驱动结构（true=推挽，false=开漏，nil=不修改该位）
-- @param invert 输出逻辑反转（true=反转，false=不反转，nil=不修改该位）
-- @return boolean 成功返回 true
function exs_pca9685.set_output_mode(outdrv, invert)
    if not exs_pca9685.i2c_id or not exs_pca9685.slave_address then
        log.error("exs_pca9685", "设备未初始化")
        return false
    end
    local mode2 = read_register(REG_MODE2)
    if not mode2 then return false end
    -- 修改 OUTDRV 位（bit2）：1=推挽，0=开漏
    if outdrv ~= nil then
        if outdrv then
            mode2 = mode2 | MODE2_OUTDRV
        else
            mode2 = mode2 & ~MODE2_OUTDRV
        end
    end
    -- 修改 INVRT 位（bit4）：1=输出逻辑反转，0=不反转
    if invert ~= nil then
        if invert then
            mode2 = mode2 | MODE2_INVRT
        else
            mode2 = mode2 & ~MODE2_INVRT
        end
    end
    if not write_register(REG_MODE2, mode2) then return false end
    log.info("exs_pca9685.set_output_mode", "输出模式配置成功, mode2=0x", string.format("%02X", mode2))
    return true
end

-- 获取扩展库版本号
-- @return string 版本号
function exs_pca9685.version()
    return "202608252000"
end

return exs_pca9685
