--[[
@module  exs_qmc5883p
@summary QMC5883P 三轴地磁传感器扩展库
@version 1.0
@date    2026.08.05
@author  江访
@usage
本文件为 QMC5883P 地磁传感器（QST 出品，QMC5883L 停产替代型号）的 LuatOS 扩展库，核心功能为：
1、初始化 QMC5883P，配置 I2C 引脚和采样参数（量程、输出速率、过采样、降采样）
2、读取三轴磁场数据（X/Y/Z），自动转换为微特斯拉（μT）单位
3、量程动态切换（±2G / ±8G / ±12G / ±30G）
4、输出速率动态切换（10Hz / 50Hz / 100Hz / 200Hz）
5、过采样率（OSR1）与降采样率（OSR2）配置
6、SET/RESET 偏移消除模式配置（芯片内置温度补偿，输出数据已补偿）
7、软复位（soft_reset）与自检（self_test）
8、睡眠/唤醒/关闭
9、I2C 总线卡死自动检测与恢复

本文件的对外接口有 11 个：
1、exs_qmc5883p.setup(config)：初始化 QMC5883P
2、exs_qmc5883p.get_data()：读取三轴磁场数据
3、exs_qmc5883p.set_range(range)：切换量程
4、exs_qmc5883p.set_odr(hz)：切换输出速率
5、exs_qmc5883p.set_osr(osr, osr2)：配置过采样/降采样
6、exs_qmc5883p.soft_reset()：软复位
7、exs_qmc5883p.self_test()：自检
8、exs_qmc5883p.sleep()：进入挂起模式
9、exs_qmc5883p.wakeup()：从挂起模式唤醒
10、exs_qmc5883p.close()：关闭传感器
11、exs_qmc5883p.version()：获取版本号

-- 版本更新说明
版本号：202608050000
1、更新时间：2026-08-05
2、更新内容：
            - 初版，实现 QMC5883P 驱动所有基础功能
            - 支持软件 I2C 和硬件 I2C 两种模式
            - 支持量程切换（±2G / ±8G / ±12G / ±30G）
            - 支持输出速率切换（10Hz / 50Hz / 100Hz / 200Hz）
            - 支持过采样率（OSR1）与降采样率（OSR2）配置
            - 支持 SET/RESET 偏移消除模式配置
            - 支持软复位与芯片自检
            - 支持挂起/唤醒/关闭
]]

local exs_qmc5883p = {}

-- ==================== 模块常量 ====================

-- I2C 设备地址（默认 7 位地址 0x2C，写 0x58，读 0x59）
local DEV_ADDR_DEFAULT = 0x2C

-- 芯片 ID 期望值
local CHIP_ID_EXPECTED = 0x80

-- 寄存器地址
local REG_CHIP_ID    = 0x00  -- 芯片 ID（只读，恒为 0x80）
local REG_DATA_X_LSB = 0x01  -- X 轴数据低字节
local REG_DATA_X_MSB = 0x02  -- X 轴数据高字节
local REG_DATA_Y_LSB = 0x03  -- Y 轴数据低字节
local REG_DATA_Y_MSB = 0x04  -- Y 轴数据高字节
local REG_DATA_Z_LSB = 0x05  -- Z 轴数据低字节
local REG_DATA_Z_MSB = 0x06  -- Z 轴数据高字节
local REG_STATUS     = 0x09  -- 状态寄存器：bit1=OVFL 溢出，bit0=DRDY 数据就绪（只读）
local REG_CTRL1      = 0x0A  -- 控制寄存器1：OSR2[7:6] OSR1[5:4] ODR[3:2] MODE[1:0]
local REG_CTRL2      = 0x0B  -- 控制寄存器2：SOFT_RST[7] SELF_TEST[6] RFU[5:4] RNG[3:2] SET/RESET[1:0]
local REG_VENDOR_0D  = 0x0D  -- 厂商保留寄存器（官方驱动初始化必须写入 0x40）
local REG_AXIS_SIGN  = 0x29  -- 轴符号定义寄存器（官方要求写入 0x06）

-- 控制寄存器1 (0x0A) 位域
local CTRL1_OSR2_SHIFT = 6     -- OSR2 降采样率位偏移
local CTRL1_OSR1_SHIFT = 4     -- OSR1 过采样率位偏移
local CTRL1_ODR_SHIFT  = 2     -- ODR 位偏移
local CTRL1_MODE_SHIFT = 0     -- MODE 位偏移

-- MODE 工作模式
local MODE_SUSPEND    = 0x00   -- 挂起模式（上电/软复位后的默认模式）
local MODE_NORMAL     = 0x01   -- 正常模式（连续测量，低功耗）
local MODE_SINGLE     = 0x02   -- 单次模式（测量 1 次后回到挂起模式）
local MODE_CONTINUOUS = 0x03   -- 连续模式（不间断运行，最大 ODR）

-- ODR 输出数据速率
local ODR_10HZ  = 0x00  -- 10 Hz
local ODR_50HZ  = 0x01  -- 50 Hz
local ODR_100HZ = 0x02  -- 100 Hz
local ODR_200HZ = 0x03  -- 200 Hz

-- OSR1 过采样率（编码与数值反序，00 最大为 8）
local OSR1_8 = 0x00  -- 过采样 8 次，噪声最低
local OSR1_4 = 0x01  -- 过采样 4 次
local OSR1_2 = 0x02  -- 过采样 2 次
local OSR1_1 = 0x03  -- 过采样 1 次

-- OSR2 降采样率（数值与编码一致，11 最大为 8）
local OSR2_1 = 0x00  -- 降采样 1（不降采样）
local OSR2_2 = 0x01  -- 降采样 2
local OSR2_4 = 0x02  -- 降采样 4
local OSR2_8 = 0x03  -- 降采样 8，滤波最强

-- 控制寄存器2 (0x0B) 位域
local CTRL2_SOFT_RST  = 0x80   -- 软复位位
local CTRL2_SELF_TEST = 0x40   -- 自检使能位
local CTRL2_RNG_SHIFT = 2      -- 量程位偏移

-- RNG 量程配置（数值编码与量程反序）
local RNG_30G = 0x00  -- ±30 高斯（最宽量程，抗干扰最强）
local RNG_12G = 0x01  -- ±12 高斯
local RNG_8G  = 0x02  -- ±8 高斯
local RNG_2G  = 0x03  -- ±2 高斯（最高灵敏度）

-- SET/RESET 偏移消除模式
local SETRESET_ON  = 0x00  -- SET 和 RESET 都开（默认，测量中持续消除偏移）
local SETRESET_SET = 0x01  -- 仅 SET 开
local SETRESET_OFF = 0x02  -- SET 和 RESET 都关

-- 灵敏度（LSB/Gauss，来自数据手册）
local SENS_2G  = 15000  -- ±2G 量程灵敏度
local SENS_8G  = 3750   -- ±8G 量程灵敏度
local SENS_12G = 2500   -- ±12G 量程灵敏度
local SENS_30G = 1000   -- ±30G 量程灵敏度

-- ==================== 内部状态 ====================

-- I2C 配置
local g_i2c_bus   = 0     -- I2C 总线对象（硬件 I2C 为数字 id，软件 I2C 为 userdata）
local g_dev_addr  = DEV_ADDR_DEFAULT  -- I2C 设备地址
local g_is_soft   = false -- 是否为软件 I2C
local g_scl_pin   = nil   -- SCL 引脚号（用于总线恢复）
local g_sda_pin   = nil   -- SDA 引脚号（用于总线恢复）

-- 当前配置
local g_range       = "8G"  -- 当前量程
local g_odr         = 10    -- 当前输出速率 (Hz)
local g_osr         = 8     -- 当前过采样率 OSR1
local g_osr2        = 8     -- 当前降采样率 OSR2
local g_set_reset   = "on"  -- 当前 SET/RESET 模式
local g_sensitivity = SENS_8G  -- 当前灵敏度
local g_ready       = false -- 初始化完成标志
local g_first_read  = true  -- 首次读取标志（真机调试时打印原始字节）

-- ==================== I2C 总线恢复 ====================

-- 对 SCL 引脚产生最多 9 个时钟脉冲，强制锁死 SDA 的从机释放总线
-- 每发一个脉冲检测 SDA 是否释放，提前结束
-- 适用于软件 I2C 和硬件 I2C 两种模式（有引脚号就可以操作）
-- 硬件 I2C 场景恢复后需重新 i2c.setup()
local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then
        return false
    end
    -- 先把引脚设为 GPIO 输出高电平
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)     -- 等待电平稳定，1ms

    -- 产生最多 9 个 SCL 时钟脉冲，每发一个检查 SDA 是否释放
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0)
        sys.wait(1)                     -- SCL 低电平保持，1ms
        -- 在 SCL 低电平期间检查 SDA
        gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
        sys.wait(1)                     -- 电平稳定，1ms
        if gpio.get(g_sda_pin) == 1 then
            -- SDA 已释放，提前结束
            gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
            break
        end
        gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
        gpio.set(g_scl_pin, 1)
    end

    -- 产生 STOP 条件：SDA 低→高，SCL 高
    gpio.set(g_sda_pin, 0)
    sys.wait(1)     -- STOP 条件前半段，1ms
    gpio.set(g_scl_pin, 1)
    sys.wait(1)     -- SCL 拉高，1ms
    gpio.set(g_sda_pin, 1)
    sys.wait(1)     -- STOP 条件后半段，1ms

    log.info("exs_qmc5883p", "I2C总线恢复完成")
    return true
end

-- ==================== I2C 底层操作 ====================

-- I2C 总线卡死自动检测与恢复（内部函数）
-- 通信失败后检查 SDA/SCL 电平，确认死锁后自动恢复并重试
-- 锁死判据：SDA=0、SCL=1（从机锁死 SDA）
local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then
        return false
    end
    -- 切 SDA/SCL 为输入模式读取电平
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP)
    sys.wait(1)     -- 等待电平稳定，1ms
    local sda_level = gpio.get(g_sda_pin)
    local scl_level = gpio.get(g_scl_pin)
    local is_stall = (sda_level == 0 and scl_level == 1)
    -- 恢复为输出高电平（总线恢复需要）
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)

    if not is_stall then
        -- 不是典型的 SDA低+SCL高 死锁状态，不执行恢复
        return false
    end

    log.warn("exs_qmc5883p", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()

    -- 硬件 I2C 需要重新初始化外设
    if not g_is_soft then
        i2c.setup(g_i2c_bus, i2c.SLOW)
    end
    return true
end

-- I2C 写寄存器（带自动卡死检测恢复）
-- @return boolean 成功返回 true
local function i2c_write(reg, val)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val})
    if not ok then
        -- 自动检测并恢复总线卡死，重试一次
        if try_bus_recovery() then
            ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val})
        end
    end
    return ok
end

-- I2C 读寄存器（指定寄存器地址，读取指定长度，带自动卡死检测恢复）
-- @return table or nil 返回字节数组，失败返回 nil
local function i2c_read(reg, len)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
    if not ok then
        -- 自动检测并恢复总线卡死，重试一次
        if try_bus_recovery() then
            ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
        end
        if not ok then
            return nil
        end
    end
    local data = i2c.recv(g_i2c_bus, g_dev_addr, len)
    if not data then
        return nil
    end
    -- LuatOS i2c.recv 返回 string，转成字节数组
    local t = {}
    for i = 1, #data do
        t[i] = data:byte(i)
    end
    return t
end

-- ==================== 内部辅助函数 ====================

-- 16 位补码转有符号数（数据寄存器为 2's complement）
local function to_signed(v)
    if v >= 0x8000 then
        return v - 0x10000
    end
    return v
end

-- 解析 6 字节数据寄存器（LSB first），返回 x/y/z 有符号原始值
local function parse_data_bytes(t)
    local x = to_signed((t[2] << 8) | t[1])
    local y = to_signed((t[4] << 8) | t[3])
    local z = to_signed((t[6] << 8) | t[5])
    return x, y, z
end

-- 将量程字符串转换为寄存器值和灵敏度（LSB/G）
-- 规格书页码：Datasheet Rev.E Table 2（Page 4）灵敏度表
local function range_to_params(range_str)
    if range_str == "2G" then
        return RNG_2G, SENS_2G
    elseif range_str == "12G" then
        return RNG_12G, SENS_12G
    elseif range_str == "30G" then
        return RNG_30G, SENS_30G
    else
        return RNG_8G, SENS_8G
    end
end

-- 将输出速率数值转换为寄存器值
local function odr_to_params(hz)
    if hz >= 200 then
        return ODR_200HZ, 200
    elseif hz >= 100 then
        return ODR_100HZ, 100
    elseif hz >= 50 then
        return ODR_50HZ, 50
    else
        return ODR_10HZ, 10
    end
end

-- 将过采样率数值转换为 OSR1 寄存器值（8/4/2/1）
local function osr1_to_params(v)
    if v <= 1 then
        return OSR1_1, 1
    elseif v <= 2 then
        return OSR1_2, 2
    elseif v <= 4 then
        return OSR1_4, 4
    else
        return OSR1_8, 8
    end
end

-- 将降采样率数值转换为 OSR2 寄存器值（1/2/4/8）
local function osr2_to_params(v)
    if v <= 1 then
        return OSR2_1, 1
    elseif v <= 2 then
        return OSR2_2, 2
    elseif v <= 4 then
        return OSR2_4, 4
    else
        return OSR2_8, 8
    end
end

-- 将 SET/RESET 模式字符串转换为寄存器值
local function setreset_to_params(s)
    if s == "set" then
        return SETRESET_SET
    elseif s == "off" then
        return SETRESET_OFF
    else
        return SETRESET_ON
    end
end

-- 构建控制寄存器 1 字节值
local function build_ctrl1(osr2_reg, osr1_reg, odr_reg, mode)
    return (osr2_reg << CTRL1_OSR2_SHIFT) |
           (osr1_reg << CTRL1_OSR1_SHIFT) |
           (odr_reg << CTRL1_ODR_SHIFT) |
           (mode << CTRL1_MODE_SHIFT)
end

-- 构建控制寄存器 2 字节值（量程 + SET/RESET 模式）
local function build_ctrl2(rng_reg, sr_reg)
    return (rng_reg << CTRL2_RNG_SHIFT) | sr_reg
end

-- 写入芯片厂商要求的固定寄存器配置
-- 0x29=0x06：定义 X/Y/Z 轴符号（数据手册 7.1 应用示例）
-- 0x0D=0x40：厂商保留寄存器（官方驱动与应用指南初始化流程要求写入）
local function apply_vendor_registers()
    if not i2c_write(REG_VENDOR_0D, 0x40) then
        log.error("exs_qmc5883p", "写厂商寄存器 0x0D 失败，I2C 通信异常")
        return false
    end
    if not i2c_write(REG_AXIS_SIGN, 0x06) then
        log.error("exs_qmc5883p", "写轴符号寄存器 0x29 失败，I2C 通信异常")
        return false
    end
    return true
end

-- 应用完整配置（量程/ODR/OSR/降采样/SET-RESET）
-- QMC5883P 模式切换需经过挂起（suspend）模式，见数据手册 6.1 模式转换
-- @return boolean 全部写入成功返回 true
local function apply_config(range_str, odr_hz, osr1_val, osr2_val, setreset_str)
    local rng_reg, sens = range_to_params(range_str)
    local odr_reg, actual_odr = odr_to_params(odr_hz)
    local osr1_reg, actual_osr1 = osr1_to_params(osr1_val)
    local osr2_reg, actual_osr2 = osr2_to_params(osr2_val)
    local sr_reg = setreset_to_params(setreset_str)

    -- 第一步：写入含新参数的挂起模式（模式切换必须经过 suspend）
    local suspend = build_ctrl1(osr2_reg, osr1_reg, odr_reg, MODE_SUSPEND)
    if not i2c_write(REG_CTRL1, suspend) then
        log.error("exs_qmc5883p", "写 CTRL1(suspend) 失败，I2C 通信异常")
        return false
    end
    sys.wait(1)     -- 等待模式切换完成，1ms

    -- 第二步：写入控制寄存器 2（量程 + SET/RESET 模式）
    local ctrl2 = build_ctrl2(rng_reg, sr_reg)
    if not i2c_write(REG_CTRL2, ctrl2) then
        log.error("exs_qmc5883p", "写 CTRL2 失败，I2C 通信异常")
        return false
    end

    -- 第三步：写入最终配置并进入正常模式
    local ctrl1 = build_ctrl1(osr2_reg, osr1_reg, odr_reg, MODE_NORMAL)
    if not i2c_write(REG_CTRL1, ctrl1) then
        log.error("exs_qmc5883p", "写 CTRL1(normal) 失败，I2C 通信异常")
        return false
    end

    -- 更新内部状态
    g_range = range_str
    g_sensitivity = sens
    g_odr = actual_odr
    g_osr = actual_osr1
    g_osr2 = actual_osr2
    g_set_reset = setreset_str

    return true
end

-- ==================== 对外 API ====================

--[[
初始化 QMC5883P 地磁传感器，配置 I2C 引脚和采样参数

@api exs_qmc5883p.setup(config)

@table config
初始化配置表，包含以下键：

scl
SCL 时钟引脚 GPIO 编号；
与 sda 一起传入时，无论软硬件 I2C 模式都会用于总线恢复；
无 i2c_id 时自动创建软件 I2C（任意 GPIO 均可）；
有 i2c_id 时走硬件 I2C 通信 + GPIO 脉冲恢复总线；
数据类型：number
是否必选：与 sda 一起可选

sda
SDA 数据引脚 GPIO 编号；
数据类型：number
是否必选：与 scl 一起可选

i2c_id
硬件 I2C 总线 ID，例如 i2c1 为 1，i2c2 为 2；
与 scl/sda 一起传时使用硬件 I2C 通信 + 引脚恢复总线；
不传 scl/sda 时使用硬件 I2C，但无总线恢复能力；
数据类型：number
是否必选：可选（默认 0）

addr
I2C 设备地址（7 位地址）；
数据类型：number
是否必选：可选（默认 0x2C）

range
量程，可选 "2G"/"8G"/"12G"/"30G"，默认 "8G"；
±2G 灵敏度 15000 LSB/G，±8G 灵敏度 3750 LSB/G，±12G 灵敏度 2500 LSB/G，±30G 灵敏度 1000 LSB/G；
数据类型：string
是否必选：可选

odr
输出数据速率，可选 10、50、100、200，单位 Hz，默认 10；
数据类型：number
是否必选：可选

osr
过采样率（OSR1），可选 8、4、2、1，默认 8（最高）；
OSR 越大噪声越低、功耗越高；
数据类型：number
是否必选：可选

osr2
降采样率（OSR2），可选 1、2、4、8，默认 8（最高）；
OSR2 越大数字滤波越强、噪声越低；
数据类型：number
是否必选：可选

set_reset
SET/RESET 偏移消除模式，可选 "on"/"set"/"off"，默认 "on"；
"on"：SET 和 RESET 都开，测量中持续消除传感器偏移，推荐；
"set"：仅 SET 开，测量中偏移不更新；
"off"：SET 和 RESET 都关，功耗最低但偏移不消除；
数据类型：string
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 方式一：软件 I2C 模式，指定任意 GPIO 引脚
local result = exs_qmc5883p.setup({
    scl = 31,
    sda = 30,
})

-- 方式二：硬件 I2C 模式 + 总线恢复，传 i2c_id + I2C对应GPIO 引脚
local result = exs_qmc5883p.setup({
    i2c_id = 0,
    scl = 31,
    sda = 30,
})

-- 方式三：硬件 I2C 模式（无总线恢复），仅传 i2c_id
local result = exs_qmc5883p.setup({
    i2c_id = 0,
})
]]
function exs_qmc5883p.setup(config)
    -- 参数检查
    if type(config) ~= "table" then
        log.error("exs_qmc5883p.setup 参数错误：config 应为 table 类型")
        return false
    end

    -- 初始化 I2C 总线
    if config.scl and config.sda then
        -- 先保存引脚号用于总线恢复（软硬件 I2C 均可用）
        g_scl_pin = config.scl
        g_sda_pin = config.sda

        if config.i2c_id then
            -- 硬件 I2C 模式 + 引脚恢复：先恢复总线再初始化硬件 I2C
            i2c_bus_recovery()
            local ok = i2c.setup(config.i2c_id, i2c.SLOW)
            if ok == 0 then
                log.error("exs_qmc5883p.setup 硬件 I2C 初始化失败, id=" .. config.i2c_id)
                return false
            end
            g_i2c_bus = config.i2c_id
            g_is_soft = false
        else
            -- 软件 I2C 模式：先恢复总线再创建软件 I2C
            i2c_bus_recovery()
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then
                log.error("exs_qmc5883p.setup 软件 I2C 创建失败")
                return false
            end
            g_is_soft = true
        end
    else
        -- 硬件 I2C 模式：无引脚信息，跳过总线恢复
        local i2c_id = config.i2c_id or 0
        local ok = i2c.setup(i2c_id, i2c.SLOW)
        if ok == 0 then
            log.error("exs_qmc5883p.setup 硬件 I2C 初始化失败, id=" .. i2c_id)
            return false
        end
        g_i2c_bus = i2c_id
        g_is_soft = false
        g_scl_pin = nil
        g_sda_pin = nil
    end

    g_dev_addr = config.addr or DEV_ADDR_DEFAULT

    -- 芯片校验：读 CHIP ID（0x00 寄存器），期望 0x80，失败必须 return false
    local id_ok = false
    for i = 1, 5 do
        local id = i2c_read(REG_CHIP_ID, 1)
        if id and id[1] == CHIP_ID_EXPECTED then
            id_ok = true
            break
        end
        if id then
            -- 通信成功但值不对，打印实际值便于排查（如模块实际为其他芯片）
            log.warn("exs_qmc5883p", string.format("第%d次读芯片ID=0x%02X，期望 0x%02X",
                i, id[1], CHIP_ID_EXPECTED))
        else
            -- 通信无应答：地址不对、供电或接线问题
            log.warn("exs_qmc5883p", string.format("第%d次读芯片ID失败（I2C 无应答），检查接线与地址 0x%02X",
                i, g_dev_addr))
        end
        sys.wait(1)     -- 重试间隔 1ms，等待芯片就绪
    end
    if not id_ok then
        log.error("exs_qmc5883p", string.format("芯片识别失败：期望 0x%02X", CHIP_ID_EXPECTED))
        return false
    end

    -- 写入厂商要求的固定寄存器配置
    if not apply_vendor_registers() then
        return false
    end

    -- 写入控制寄存器，进入正常模式
    local range_str = config.range or "8G"
    local odr_hz = config.odr or 10
    local osr_val = config.osr or 8
    local osr2_val = config.osr2 or 8
    local setreset_str = config.set_reset or "on"

    if not apply_config(range_str, odr_hz, osr_val, osr2_val, setreset_str) then
        log.error("exs_qmc5883p.setup 配置写入失败，传感器可能未连接")
        return false
    end

    g_ready = true
    g_first_read = true

    log.info("exs_qmc5883p",
        string.format("初始化完成, range=%s odr=%dHz osr=%d osr2=%d set_reset=%s",
            g_range, g_odr, g_osr, g_osr2, g_set_reset))

    return true
end

--[[
读取 QMC5883P 三轴磁场数据

从 0x01~0x06 寄存器读取 6 字节（X/Y/Z 各 2 字节，LSB first，2's complement），
根据当前量程灵敏度自动计算 μT 值。
转换公式：μT = raw / sensitivity * 100（1 Gauss = 100 μT）
同时读取状态寄存器（0x09）判断 OVFL 溢出标志。

@api exs_qmc5883p.get_data()

@return table or nil
成功返回包含 x/y/z/overflow 字段的 table，x/y/z 单位 μT（微特斯拉），overflow 为 boolean 溢出标志；
失败返回 nil。

@usage
local data = exs_qmc5883p.get_data()
if data then
    log.info("exs_qmc5883p", string.format("X=%.1f Y=%.1f Z=%.1f uT overflow=%s",
        data.x, data.y, data.z, tostring(data.overflow)))
end
]]
function exs_qmc5883p.get_data()
    if not g_ready then
        log.error("exs_qmc5883p.get_data 请先调用 setup()")
        return nil
    end

    -- 读取 6 字节数据（0x01~0x06）
    local data = i2c_read(REG_DATA_X_LSB, 6)
    if not data or #data < 6 then
        return nil
    end

    -- 首次读取时打印原始字节，便于真机比对
    if g_first_read then
        log.info("exs_qmc5883p", string.format("首次读取原始字节: %02X %02X %02X %02X %02X %02X",
            data[1], data[2], data[3], data[4], data[5], data[6]))
        g_first_read = false
    end

    -- 解析三轴原始值（2's complement, LSB first）
    local x_raw, y_raw, z_raw = parse_data_bytes(data)

    -- 读取状态寄存器判断溢出标志（bit1=OVFL）
    local overflow = false
    local st = i2c_read(REG_STATUS, 1)
    if st and st[1] and (st[1] & 0x02) ~= 0 then
        overflow = true
    end

    -- 转换为 μT：raw * 100 / sensitivity
    local x = x_raw * 100 / g_sensitivity
    local y = y_raw * 100 / g_sensitivity
    local z = z_raw * 100 / g_sensitivity

    return {x = x, y = y, z = z, overflow = overflow}
end

--[[
切换量程

@api exs_qmc5883p.set_range(range)

range
参数含义：目标量程
数据类型：string
取值范围："2G"（±2G，15000 LSB/G，精度最高，适合弱磁场检测）
         "8G"（±8G，3750 LSB/G，适合通用电子罗盘，默认）
         "12G"（±12G，2500 LSB/G，适合较强磁场环境）
         "30G"（±30G，1000 LSB/G，量程最宽，抗干扰最强，适合工业/车载）
是否必选：必选

@return boolean
切换成功返回 true，失败返回 false

@usage
exs_qmc5883p.set_range("2G")
]]
function exs_qmc5883p.set_range(range_str)
    if not g_ready then
        log.error("exs_qmc5883p.set_range 请先调用 setup()")
        return false
    end
    if range_str ~= "2G" and range_str ~= "8G" and range_str ~= "12G" and range_str ~= "30G" then
        log.error("exs_qmc5883p.set_range 参数错误：%s", range_str)
        return false
    end

    if not apply_config(range_str, g_odr, g_osr, g_osr2, g_set_reset) then
        return false
    end

    log.info("exs_qmc5883p", string.format("量程切换为 %s", g_range))
    return true
end

--[[
切换输出数据速率

@api exs_qmc5883p.set_odr(hz)

hz
参数含义：目标输出速率
数据类型：number
取值范围：10、50、100、200（单位 Hz）
是否必选：必选

@return boolean
切换成功返回 true，失败返回 false

@usage
exs_qmc5883p.set_odr(100)
]]
function exs_qmc5883p.set_odr(hz)
    if not g_ready then
        log.error("exs_qmc5883p.set_odr 请先调用 setup()")
        return false
    end
    hz = hz or 10
    if hz <= 0 then hz = 10 end

    if not apply_config(g_range, hz, g_osr, g_osr2, g_set_reset) then
        return false
    end

    log.info("exs_qmc5883p", string.format("输出速率切换为 %dHz", g_odr))
    return true
end

--[[
配置过采样率（OSR1）与降采样率（OSR2）

@api exs_qmc5883p.set_osr(osr, osr2)

osr
参数含义：过采样率 OSR1
数据类型：number
取值范围：8（噪声最低，默认）、4、2、1
是否必选：可选（缺省保持当前值）

osr2
参数含义：降采样率 OSR2
数据类型：number
取值范围：8（滤波最强，默认）、4、2、1
是否必选：可选（缺省保持当前值）

@return boolean
配置成功返回 true，失败返回 false

@usage
-- 最高滤波：OSR1=8, OSR2=8
exs_qmc5883p.set_osr(8, 8)

-- 最低功耗：OSR1=1, OSR2=1
exs_qmc5883p.set_osr(1, 1)
]]
function exs_qmc5883p.set_osr(osr, osr2)
    if not g_ready then
        log.error("exs_qmc5883p.set_osr 请先调用 setup()")
        return false
    end
    local osr1_val = osr or g_osr
    local osr2_val = osr2 or g_osr2

    if not apply_config(g_range, g_odr, osr1_val, osr2_val, g_set_reset) then
        return false
    end

    log.info("exs_qmc5883p", string.format("过采样/降采样配置为 osr=%d osr2=%d", g_osr, g_osr2))
    return true
end

--[[
软复位

将芯片恢复到出厂默认状态（挂起模式、默认寄存器值），
复位完成后自动重新应用当前配置（量程/ODR/OSR 等）。
复位过程中所有寄存器回到默认值，所以复位后必须重新配置。

⚠️ 协程限制：必须在 sys.taskInit 创建的协程中调用
原因：内部使用 sys.wait 等待复位完成
最长等待：约 6ms

@api exs_qmc5883p.soft_reset()

@return boolean
复位并重新配置成功返回 true，失败返回 false

@usage
exs_qmc5883p.soft_reset()
]]
function exs_qmc5883p.soft_reset()
    if not g_ready then
        log.error("exs_qmc5883p.soft_reset 请先调用 setup()")
        return false
    end
    -- 写入软复位命令（0x0B bit7=1）
    if not i2c_write(REG_CTRL2, CTRL2_SOFT_RST) then
        log.error("exs_qmc5883p.soft_reset 软复位命令写入失败")
        return false
    end
    sys.wait(5)     -- 等待复位完成，5ms

    -- 复位后重新写入厂商固定寄存器并应用配置
    if not apply_vendor_registers() then
        return false
    end
    if not apply_config(g_range, g_odr, g_osr, g_osr2, g_set_reset) then
        return false
    end

    log.info("exs_qmc5883p", "软复位完成，配置已恢复")
    return true
end

--[[
芯片自检（SELF_TEST）

利用芯片内置自检激励信号验证信号链路是否正常。
原理：使能自检后芯片内部注入已知磁场信号，比较自检前后的三轴输出增量。
流程（对应数据手册 7.3 自检示例）：
1、切换到连续模式（自检只能在连续模式使能）
2、读取基线数据（自检前）
3、使能自检位（0x0B bit6）
4、等待测量完成，读取自检后数据
5、计算三轴增量，恢复原配置

⚠️ 协程限制：必须在 sys.taskInit 创建的协程中调用
原因：内部使用 sys.wait 等待测量完成
最长等待：约 200ms

@api exs_qmc5883p.self_test()

@return table or nil
成功返回自检前后增量表 {dx, dy, dz}，单位 LSB（原始 ADC 计数）；
失败返回 nil。
说明：数据手册未给出判定阈值，增量明显大于正常噪声表示信号链路正常；
各轴增量方向因安装方向而异。

@usage
local delta = exs_qmc5883p.self_test()
if delta then
    log.info("exs_qmc5883p", string.format("自检增量 dx=%d dy=%d dz=%d", delta.dx, delta.dy, delta.dz))
end
]]
function exs_qmc5883p.self_test()
    if not g_ready then
        log.error("exs_qmc5883p.self_test 请先调用 setup()")
        return nil
    end

    -- 保存当前控制寄存器值，自检结束后恢复
    local saved_ctrl1 = i2c_read(REG_CTRL1, 1)
    local saved_ctrl2 = i2c_read(REG_CTRL2, 1)
    if not saved_ctrl1 or not saved_ctrl2 then
        log.error("exs_qmc5883p.self_test 读取控制寄存器失败")
        return nil
    end

    -- 恢复到指定配置（失败时恢复原寄存器值）
    local function restore_regs()
        i2c_write(REG_CTRL2, saved_ctrl2[1])
        i2c_write(REG_CTRL1, saved_ctrl1[1])
    end

    -- 1、切换到连续模式（保持 OSR/ODR 不变）
    local continuous = (saved_ctrl1[1] & 0xFC) | MODE_CONTINUOUS
    if not i2c_write(REG_CTRL1, continuous) then
        restore_regs()
        return nil
    end

    -- 2、等待首次测量完成（连续模式下 ODR 最快 10Hz 周期 100ms，留余量）
    sys.wait(150)   -- 等待首次测量完成，150ms

    -- 3、读取自检前基线数据
    local d1 = i2c_read(REG_DATA_X_LSB, 6)
    if not d1 or #d1 < 6 then
        restore_regs()
        return nil
    end
    local x1, y1, z1 = parse_data_bytes(d1)

    -- 4、使能自检（保持量程/SET-RESET 等其他位不变）
    if not i2c_write(REG_CTRL2, saved_ctrl2[1] | CTRL2_SELF_TEST) then
        restore_regs()
        return nil
    end

    -- 5、等待自检数据更新（数据手册：约 5ms，留余量）
    sys.wait(50)    -- 等待自检测量完成，50ms

    -- 6、读取自检后数据
    local d2 = i2c_read(REG_DATA_X_LSB, 6)
    if not d2 or #d2 < 6 then
        restore_regs()
        return nil
    end
    local x2, y2, z2 = parse_data_bytes(d2)

    -- 7、计算增量（LSB）
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1

    -- 8、恢复原始配置
    restore_regs()

    log.info("exs_qmc5883p", string.format("自检完成, 增量 dx=%d dy=%d dz=%d", dx, dy, dz))
    return {dx = dx, dy = dy, dz = dz}
end

--[[
进入挂起模式（低功耗）

将传感器切换到挂起模式，保持内部配置状态。
调用 wakeup() 可快速恢复工作，无需重新 setup()。
挂起模式功耗约 22μA。

@api exs_qmc5883p.sleep()

@return nil

@usage
exs_qmc5883p.sleep()
]]
function exs_qmc5883p.sleep()
    if not g_ready then
        log.error("exs_qmc5883p.sleep 请先调用 setup()")
        return
    end
    local osr2_reg = osr2_to_params(g_osr2)
    local osr1_reg = osr1_to_params(g_osr)
    local odr_reg = odr_to_params(g_odr)
    local suspend = build_ctrl1(osr2_reg, osr1_reg, odr_reg, MODE_SUSPEND)
    i2c_write(REG_CTRL1, suspend)
    log.info("exs_qmc5883p", "已进入挂起模式")
end

--[[
从挂起模式唤醒

恢复传感器到正常测量模式，配置保持休眠前的参数。
无需重新调用 setup()。

@api exs_qmc5883p.wakeup()

@return nil

@usage
exs_qmc5883p.wakeup()
]]
function exs_qmc5883p.wakeup()
    if not g_ready then
        log.error("exs_qmc5883p.wakeup 请先调用 setup()")
        return
    end
    local osr2_reg = osr2_to_params(g_osr2)
    local osr1_reg = osr1_to_params(g_osr)
    local odr_reg = odr_to_params(g_odr)
    local ctrl1 = build_ctrl1(osr2_reg, osr1_reg, odr_reg, MODE_NORMAL)
    i2c_write(REG_CTRL1, ctrl1)
    log.info("exs_qmc5883p", "已从挂起模式唤醒")
end

--[[
关闭 QMC5883P 传感器

将传感器切换到挂起模式，重置内部状态。
close 后需要重新调用 setup() 才能再次使用。

@api exs_qmc5883p.close()

@return nil

@usage
exs_qmc5883p.close()
]]
function exs_qmc5883p.close()
    if not g_ready then
        return
    end
    -- 切回挂起模式
    local osr2_reg = osr2_to_params(g_osr2)
    local osr1_reg = osr1_to_params(g_osr)
    local odr_reg = odr_to_params(g_odr)
    local suspend = build_ctrl1(osr2_reg, osr1_reg, odr_reg, MODE_SUSPEND)
    i2c_write(REG_CTRL1, suspend)

    -- 重置内部状态
    g_ready = false
    g_i2c_bus = 0
    g_dev_addr = DEV_ADDR_DEFAULT
    g_is_soft = false
    g_scl_pin = nil
    g_sda_pin = nil
    g_first_read = true

    log.info("exs_qmc5883p", "传感器已关闭")
end

--[[
获取 exs_qmc5883p 库的版本号

@api exs_qmc5883p.version()

@return string

@usage
local ver = exs_qmc5883p.version()
]]
function exs_qmc5883p.version()
    return "202608050000"
end

log.debug("exs_qmc5883p", "version -> " .. exs_qmc5883p.version())

return exs_qmc5883p
