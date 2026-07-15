--[[
@module  exs_qmc5883l
@summary QMC5883L 三轴地磁传感器扩展库
@version 202607131200
@date    2026.07.13
@author  江访
@usage
本文件为 QMC5883L 地磁传感器（QST 出品）的 LuatOS 扩展库，核心功能为：
1、初始化 QMC5883L，配置 I2C 引脚和采样参数（量程、输出速率、过采样）
2、读取三轴磁场数据（X/Y/Z），自动转换为微特斯拉（μT）单位
3、量程动态切换（±2G / ±8G）
4、输出速率动态切换（10Hz / 50Hz / 100Hz / 200Hz）
5、软件复位

本文件的对外接口有 6 个：
1、exs_qmc5883l.setup(config)：初始化 QMC5883L
2、exs_qmc5883l.get_data()：读取三轴磁场数据
3、exs_qmc5883l.set_range(range)：切换量程
4、exs_qmc5883l.set_odr(hz)：切换输出速率
5、exs_qmc5883l.soft_reset()：软件复位
6、exs_qmc5883l.version()：获取版本号

-- 版本更新说明
-- 版本号：202607131200
-- 1、更新时间：2026-07-13 12:00
-- 2、更新内容
  - 初版，实现 QMC5883L 驱动所有基础功能
  - 初始化接口使用 setup 命名，统一 TM16xx 系列命名规范
  - 支持软件 I2C 和硬件 I2C 两种模式
  - 支持量程切换（±2G / ±8G）
  - 支持输出速率切换（10Hz / 50Hz / 100Hz / 200Hz）
  - 支持过采样率配置（64 / 128 / 256 / 512）
  - 支持软件复位
]]

local exs_qmc5883l = {}

-- ==================== 模块常量 ====================

-- I2C 设备地址（7 位地址 0x0D，写 0x1A，读 0x1B，SI=VDD 默认）
local DEV_ADDR = 0x0D

-- 寄存器地址
local REG_DATA_X_LSB  = 0x00  -- X 轴数据低字节
local REG_DATA_X_MSB  = 0x01  -- X 轴数据高字节
local REG_DATA_Y_LSB  = 0x02  -- Y 轴数据低字节
local REG_DATA_Y_MSB  = 0x03  -- Y 轴数据高字节
local REG_DATA_Z_LSB  = 0x04  -- Z 轴数据低字节
local REG_DATA_Z_MSB  = 0x05  -- Z 轴数据高字节
local REG_STATUS       = 0x06  -- 状态寄存器
local REG_TEMP_LSB     = 0x07  -- 温度数据低字节
local REG_TEMP_MSB     = 0x08  -- 温度数据高字节
local REG_CTRL1        = 0x09  -- 控制寄存器 1
local REG_CTRL2        = 0x0A  -- 控制寄存器 2
local REG_SET_RESET_PERIOD = 0x0B  -- SET/RESET Period 寄存器

-- 控制寄存器 1 (0x09) 位域
local CTRL1_OSR_SHIFT  = 6     -- OSR 位偏移
local CTRL1_RNG_SHIFT  = 4     -- RNG 位偏移
local CTRL1_ODR_SHIFT  = 2     -- ODR 位偏移
local CTRL1_MODE_SHIFT = 0     -- MODE 位偏移

-- OSR 过采样率配置
local OSR_512  = 0x00  -- 512 次采样，最高精度
local OSR_256  = 0x01  -- 256 次采样
local OSR_128  = 0x02  -- 128 次采样
local OSR_64   = 0x03  -- 64 次采样，最低精度

-- RNG 量程配置
local RNG_2G   = 0x00  -- ±2 高斯
local RNG_8G   = 0x01  -- ±8 高斯

-- ODR 输出数据速率
local ODR_10HZ   = 0x00  -- 10 Hz
local ODR_50HZ   = 0x01  -- 50 Hz
local ODR_100HZ  = 0x02  -- 100 Hz
local ODR_200HZ  = 0x03  -- 200 Hz

-- MODE 工作模式
local MODE_STANDBY     = 0x00  -- 待机模式
local MODE_CONTINUOUS  = 0x01  -- 连续测量模式

-- 控制寄存器 2 (0x0A) 位域
local CTRL2_SOFT_RST = 0x80   -- 软件复位位

-- 灵敏度（LSB/Gauss）
local SENSITIVITY_2G = 12000  -- ±2G 量程灵敏度
local SENSITIVITY_8G = 3000   -- ±8G 量程灵敏度

-- ==================== 内部状态 ====================

-- I2C 配置
local g_i2c_bus   = 0     -- I2C 总线对象（硬件 I2C 为数字 id，软件 I2C 为 userdata）
local g_is_soft   = false -- 是否为软件 I2C
local g_scl_pin   = nil   -- SCL 引脚号（软件 I2C 才有，用于总线恢复）
local g_sda_pin   = nil   -- SDA 引脚号（软件 I2C 才有，用于总线恢复）

-- 当前配置
local g_range = "8G"       -- 当前量程
local g_odr   = 10         -- 当前输出速率 (Hz)
local g_osr   = 512        -- 当前过采样率
local g_sensitivity = SENSITIVITY_8G  -- 当前灵敏度
local g_ready = false      -- 初始化完成标志

-- ==================== I2C 总线恢复 ====================

-- 对 SCL 引脚产生 9 个时钟脉冲，强制锁死 SDA 的从机释放总线
-- 仅软件 I2C 模式下可用（有引脚号才能用 GPIO 直接操作）
local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then
        return
    end
    -- 软件 I2C 用 GPIO 模拟，直接操作引脚产生 9 个 SCL 脉冲
    -- 先把引脚设为 GPIO 输出高电平
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)
    -- 产生 9 个 SCL 时钟脉冲
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0)
        sys.wait(1)
        gpio.set(g_scl_pin, 1)
        sys.wait(1)
    end
    -- 产生 STOP 条件：SDA 低→高，SCL 高
    gpio.set(g_sda_pin, 0)
    sys.wait(1)
    gpio.set(g_scl_pin, 1)
    sys.wait(1)
    gpio.set(g_sda_pin, 1)
    sys.wait(1)
    log.info("exs_qmc5883l", "传感器复位完成")
end

-- ==================== I2C 底层操作 ====================

-- I2C 写寄存器
-- @return boolean 成功返回 true
local function i2c_write(reg, val)
    return i2c.send(g_i2c_bus, DEV_ADDR, {reg, val})
end

-- I2C 读寄存器（指定寄存器地址，读取指定长度）
-- @return table or nil 返回字节数组，失败返回 nil
local function i2c_read(reg, len)
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, {reg})
    if not ok then
        return nil
    end
    local data = i2c.recv(g_i2c_bus, DEV_ADDR, len)
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

-- 将量程字符串转换为寄存器值和灵敏度
local function range_to_params(range_str)
    if range_str == "2G" then
        return RNG_2G, SENSITIVITY_2G
    else
        return RNG_8G, SENSITIVITY_8G
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

-- 将过采样率数值转换为寄存器值
local function osr_to_params(osr_val)
    if osr_val >= 512 then
        return OSR_512, 512
    elseif osr_val >= 256 then
        return OSR_256, 256
    elseif osr_val >= 128 then
        return OSR_128, 128
    else
        return OSR_64, 64
    end
end

-- 构建控制寄存器 1 的字节值
local function build_ctrl1(osr, rng, odr, mode)
    return (osr << CTRL1_OSR_SHIFT) |
           (rng << CTRL1_RNG_SHIFT) |
           (odr << CTRL1_ODR_SHIFT) |
           (mode << CTRL1_MODE_SHIFT)
end

-- 写入控制寄存器 1（先切待机，改完再切回连续模式）
-- QMC5883L 要求在待机模式下修改控制寄存器，否则可能锁死
-- @return boolean 两步写入均成功返回 true，否则返回 false
local function write_ctrl1(range_str, odr_hz, osr_val)
    local osr_reg, actual_osr = osr_to_params(osr_val)
    local rng_reg, sensitivity = range_to_params(range_str)
    local odr_reg, actual_odr = odr_to_params(odr_hz)

    -- 第一步：先切换到待机模式
    local standby = build_ctrl1(osr_reg, rng_reg, odr_reg, MODE_STANDBY)
    if not i2c_write(REG_CTRL1, standby) then
        log.error("exs_qmc5883l", "写 CTRL1(standby) 失败，I2C 通信异常")
        return false
    end
    sys.wait(5)

    -- 第二步：写入新的配置并切回连续模式
    local ctrl1 = build_ctrl1(osr_reg, rng_reg, odr_reg, MODE_CONTINUOUS)
    if not i2c_write(REG_CTRL1, ctrl1) then
        log.error("exs_qmc5883l", "写 CTRL1(continuous) 失败，I2C 通信异常")
        return false
    end
    sys.wait(10)

    -- 更新内部状态
    g_range = range_str
    g_odr = actual_odr
    g_osr = actual_osr
    g_sensitivity = sensitivity

    return true
end

-- ==================== 外部 API ====================

--[[
初始化 QMC5883L 地磁传感器，配置 I2C 引脚和采样参数

@api exs_qmc5883l.setup(config)

@table config
初始化配置表，包含以下键：

scl
SCL 时钟引脚 GPIO 编号；
与 sda 一起传入时，无论软硬件 I2C 模式都会用于 SDA 总线异常恢复；
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

range
量程，可选 "2G"（±2 高斯）或 "8G"（±8 高斯），默认 "8G"；
±2G 灵敏度 12000 LSB/G，±8G 灵敏度 3000 LSB/G；
数据类型：string
是否必选：可选

odr
输出数据速率，可选 10、50、100、200，单位 Hz，默认 10；
数据类型：number
是否必选：可选

osr
过采样率，可选 64、128、256、512，默认 512（最高精度）；
数据类型：number
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 方式一：软件 I2C 模式，指定任意 GPIO 引脚
local result = exs_qmc5883l.setup({
    scl = 27,
    sda = 26,
})

-- 方式二：硬件 I2C 模式 + 传感器复位，传 i2c_id + I2C对应GPIO 引脚
local result = exs_qmc5883l.setup({
    i2c_id = 0,
    scl = 27,
    sda = 26,
})

-- 方式三：硬件 I2C 模式（无传感器复位），仅传 i2c_id
local result = exs_qmc5883l.setup({
    i2c_id = 0,
})
]]
function exs_qmc5883l.setup(config)
    -- 参数检查
    if type(config) ~= "table" then
        log.error("exs_qmc5883l.setup 参数错误：config 应为 table 类型")
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
                log.error("exs_qmc5883l.setup 硬件 I2C 初始化失败, id=" .. config.i2c_id)
                return false
            end
            g_i2c_bus = config.i2c_id
            g_is_soft = false
        else
            -- 软件 I2C 模式：先恢复总线再创建软件 I2C
            i2c_bus_recovery()
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then
                log.error("exs_qmc5883l.setup 软件 I2C 创建失败")
                return false
            end
            g_is_soft = true
        end
    else
        -- 硬件 I2C 模式：无引脚信息，跳过总线恢复
        local i2c_id = config.i2c_id or 0
        local ok = i2c.setup(i2c_id, i2c.SLOW)
        if ok == 0 then
            log.error("exs_qmc5883l.setup 硬件 I2C 初始化失败, id=" .. i2c_id)
            return false
        end
        g_i2c_bus = i2c_id
        g_is_soft = false
        g_scl_pin = nil
        g_sda_pin = nil
    end
    sys.wait(10)

    -- QMC5883L 在异常断电或 I2C 通信中断后可能锁死总线（拉低 SDA）。
    -- 先发软复位让传感器恢复到默认状态，避免总线死锁导致后续配置全部失败。
    i2c_write(REG_CTRL2, CTRL2_SOFT_RST)
    sys.wait(50)

    -- 设置默认参数
    local range_str = config.range or "8G"
    local odr_hz = config.odr or 10
    local osr_val = config.osr or 512

    -- 配置厂商保留寄存器（两个参考程序均写入此值，保证芯片正常工作）
    i2c_write(0x20, 0x40)
    sys.wait(1)
    i2c_write(0x21, 0x01)
    sys.wait(1)

    -- 配置 SET/RESET Period 寄存器（默认值 0x01，显式写入确保稳定）
    i2c_write(REG_SET_RESET_PERIOD, 0x01)
    sys.wait(10)

    -- 写入控制寄存器，启动连续模式
    if not write_ctrl1(range_str, odr_hz, osr_val) then
        log.error("exs_qmc5883l.setup CTRL1 配置失败，传感器可能未连接")
        return false
    end
    sys.wait(20)

    g_ready = true

    log.info("exs_qmc5883l",
        string.format("初始化完成, range=%s odr=%dHz osr=%d",
            g_range, g_odr, g_osr))

    return true
end

--[[
读取 QMC5883L 三轴磁场数据

从 0x00~0x05 寄存器读取 6 字节（X/Y/Z 各 2 字节，LSB first，2's complement），
根据当前量程自动计算 μT 值。
转换公式：μT = raw_value / sensitivity * 100（1 Gauss = 100 μT）

不检查 Status 寄存器（0x06）的 OVL/DOR 标志——51 参考程序验证了 OVL 为锁存标志，
上电/模式切换后即置位，不影响数据寄存器有效值，直接读取即可。

@api exs_qmc5883l.get_data()

@return table or nil
成功返回包含 x/y/z 三轴数据的 table，单位 μT（微特斯拉）；
失败返回 nil。

@usage
local data = exs_qmc5883l.get_data()
if data then
    log.info("exs_qmc5883l", string.format("X=%.1f Y=%.1f Z=%.1f uT", data.x, data.y, data.z))
end
]]
function exs_qmc5883l.get_data()
    if not g_ready then
        log.error("exs_qmc5883l.get_data 请先调用 setup()")
        return nil
    end

    -- 读取 6 字节数据（0x00~0x05）
    local data = i2c_read(REG_DATA_X_LSB, 6)
    if not data or #data < 6 then
        return nil
    end

    -- 解析三轴数据（2's complement, LSB first）
    local x_raw = (data[2] << 8) | data[1]
    local y_raw = (data[4] << 8) | data[3]
    local z_raw = (data[6] << 8) | data[5]

    -- 符号扩展
    if x_raw >= 0x8000 then x_raw = x_raw - 0x10000 end
    if y_raw >= 0x8000 then y_raw = y_raw - 0x10000 end
    if z_raw >= 0x8000 then z_raw = z_raw - 0x10000 end

    -- 转换为 μT：raw * 100 / sensitivity
    local x = x_raw * 100 / g_sensitivity
    local y = y_raw * 100 / g_sensitivity
    local z = z_raw * 100 / g_sensitivity

    return {x = x, y = y, z = z}
end

--[[
切换量程

@api exs_qmc5883l.set_range(range)

range
参数含义：目标量程
数据类型：string
取值范围："2G" 或 "8G"
是否必选：必选

@return nil

@usage
exs_qmc5883l.set_range("2G")
]]
function exs_qmc5883l.set_range(range_str)
    if not g_ready then
        log.error("exs_qmc5883l.set_range 请先调用 setup()")
        return
    end
    if range_str ~= "2G" and range_str ~= "8G" then
        log.error("exs_qmc5883l.set_range 参数错误：%s", range_str)
        return
    end

    if not write_ctrl1(range_str, g_odr, g_osr) then
        return
    end
    sys.wait(15)

    log.info("exs_qmc5883l", string.format("量程切换为 %s", range_str))
end

--[[
切换输出数据速率

@api exs_qmc5883l.set_odr(hz)

hz
参数含义：目标输出速率
数据类型：number
取值范围：10、50、100、200（单位 Hz）
是否必选：必选

@return nil

@usage
exs_qmc5883l.set_odr(100)
]]
function exs_qmc5883l.set_odr(hz)
    if not g_ready then
        log.error("exs_qmc5883l.set_odr 请先调用 setup()")
        return
    end
    hz = hz or 10
    if hz <= 0 then hz = 10 end

    if not write_ctrl1(g_range, hz, g_osr) then
        return
    end
    sys.wait(15)

    log.info("exs_qmc5883l", string.format("输出速率切换为 %dHz", g_odr))
end

--[[
软件复位 QMC5883L

@api exs_qmc5883l.soft_reset()

@return nil

@usage
exs_qmc5883l.soft_reset()
]]
function exs_qmc5883l.soft_reset()
    if not g_ready then
        log.error("exs_qmc5883l.soft_reset 请先调用 setup()")
        return
    end
    i2c_write(REG_CTRL2, CTRL2_SOFT_RST)
    sys.wait(10)
    g_ready = false
    log.info("exs_qmc5883l", "软件复位完成")
end

--[[
获取 exs_qmc5883l 库的版本号

@api exs_qmc5883l.version()

@return string

@usage
local ver = exs_qmc5883l.version()
]]
function exs_qmc5883l.version()
    return "202607131200"
end

log.debug("exs_qmc5883l", "version -> " .. exs_qmc5883l.version())

return exs_qmc5883l
