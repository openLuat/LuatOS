--[[
@module  exs_mpu6050
@summary MPU6050 六轴姿态传感器扩展库
@version 1.0
@date    2026.07.23
@author  王城钧
@usage
本文件为 MPU6050 六轴传感器（InvenSense 出品）的 LuatOS 扩展库，核心功能为：
1、初始化 MPU6050，配置 I2C 通信和传感器量程
2、读取加速度/陀螺仪/温度原始数据，自动转换为物理单位
3、传感器零偏校准（支持 KV 持久化）
4、姿态解算（加速度倾角 / 互补滤波 / DMP 硬件姿态）
5、事件检测（碰撞 / 自由落体）
6、关闭传感器

本文件的对外接口有 12 个：
1、exs_mpu6050.setup(config)：初始化 MPU6050
2、exs_mpu6050.get_data()：读取加速度+陀螺仪+温度
3、exs_mpu6050.get_tilt()：读取倾角（加速度直接计算）
4、exs_mpu6050.get_attitude()：读取姿态角（互补滤波）
5、exs_mpu6050.detect_tap(threshold, debounce_ms)：碰撞检测
6、exs_mpu6050.detect_freefall(threshold)：自由落体检测
7、exs_mpu6050.calibrate()：手动校准零偏
8、exs_mpu6050.is_calibrated()：查询校准状态
9、exs_mpu6050.dmp_init()：DMP 硬件姿态解算初始化（需 dmp_firmware.lua）
10、exs_mpu6050.dmp_get_euler()：读取 DMP 欧拉角
11、exs_mpu6050.close()：关闭传感器
12、exs_mpu6050.version()：获取版本号

-- 版本更新说明
-- 版本号：202607231800
-- 1、更新时间：2026-07-23
-- 2、更新内容
--    初版，实现 MPU6050 驱动所有基础功能
--    遵循 exs_ 扩展库设计规范
--    支持加速度/陀螺仪/温度读取，支持零偏校准（KV 持久化）
--    支持姿态解算（加速度倾角 / 互补滤波 / DMP 硬件）
--    支持事件检测（碰撞 / 自由落体）
--    支持关闭模式
--    支持 DMP 硬件姿态解算（需额外 dmp_firmware.lua）
--    支持 I2C 地址自动检测（0x68/0x69）
]]

local exs_mpu6050 = {}
local sys = require "sys"

-- ==================== 模块常量 ====================

local MPU_ADDR_LOW      = 0x68
local MPU_ADDR_HIGH     = 0x69
local MPU_WHO_AM_I      = 0x68

-- 寄存器地址
local REG_WHO_AM_I      = 0x75
local REG_PWR_MGMT_1    = 0x6B
local REG_PWR_MGMT_2    = 0x6C
local REG_SMPLRT_DIV    = 0x19
local REG_CONFIG        = 0x1A
local REG_GYRO_CONFIG   = 0x1B
local REG_ACCEL_CONFIG  = 0x1C
local REG_ACCEL_H       = 0x3B
local REG_TEMP_H        = 0x41
local REG_GYRO_H        = 0x43
local REG_INT_ENABLE    = 0x38
local REG_USER_CTRL     = 0x6A
local REG_FIFO_EN       = 0x23
local REG_FIFO_COUNT    = 0x72
local REG_FIFO_RW       = 0x74
local REG_MEM_BANK      = 0x6D
local REG_MEM_ADDR      = 0x6E
local REG_MEM_DATA      = 0x6F

-- 灵敏度（量程 ±2g, ±250°/s）
local ACCEL_SEN         = 16384.0
local GYRO_SEN          = 131.0
local TEMP_SEN          = 340.0
local TEMP_OFF          = 36.53

-- ==================== 内部状态 ====================

local g_i2c_id      = nil        -- I2C 总线编号
local g_i2c_addr    = nil        -- I2C 设备地址
local g_ready       = false      -- 初始化完成标志

-- 校准数据
local g_calib = { ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0, ready = false }

-- 互补滤波状态
local g_cf_pitch   = 0
local g_cf_roll    = 0
local g_cf_t       = nil

-- 碰撞去抖
local g_tap_t      = 0

-- ==================== I2C 底层操作 ====================

local function w8(reg, val)
    i2c.send(g_i2c_id, g_i2c_addr, {reg, val})
end

local function r8(reg)
    i2c.send(g_i2c_id, g_i2c_addr, reg)
    local b = i2c.recv(g_i2c_id, g_i2c_addr, 1)
    return b and b:byte() or 0
end

local function rN(reg, n)
    i2c.send(g_i2c_id, g_i2c_addr, reg)
    return i2c.recv(g_i2c_id, g_i2c_addr, n)
end

-- 读16位有符号（大端序）
local function s16(reg_h)
    local d = rN(reg_h, 2)
    if not d or #d < 2 then return 0 end
    local v = (d:byte(1) << 8) | d:byte(2)
    return v >= 0x8000 and v - 0x10000 or v
end

-- ==================== 原始数据读取 ====================

local function raw_accel()
    return { x = s16(REG_ACCEL_H), y = s16(REG_ACCEL_H + 2), z = s16(REG_ACCEL_H + 4) }
end

local function raw_gyro()
    return { x = s16(REG_GYRO_H), y = s16(REG_GYRO_H + 2), z = s16(REG_GYRO_H + 4) }
end

-- 应用校准
local function apply(a, g)
    if not g_calib.ready then return a, g end
    return { x = a.x - g_calib.ax, y = a.y - g_calib.ay, z = a.z - g_calib.az },
           { x = g.x - g_calib.gx, y = g.y - g_calib.gy, z = g.z - g_calib.gz }
end

-- 静止判断
local function stationary(last, curr)
    if not last then return false end
    local th = 200
    return math.abs(curr.x - last.x) < th
       and math.abs(curr.y - last.y) < th
       and math.abs(curr.z - last.z) < th
end

-- ==================== 校准 KV 存储 ====================

local CALIB_PATH = "/mpu6050_calib.txt"

local function calib_save()
    local s = string.format("%d,%d,%d,%d,%d,%d",
        g_calib.ax, g_calib.ay, g_calib.az, g_calib.gx, g_calib.gy, g_calib.gz)
    io.writeFile(CALIB_PATH, s)
    log.info("exs_mpu6050", "校准已保存")
end

local function calib_load()
    local s = io.readFile(CALIB_PATH)
    if not s or #s == 0 then return false end
    local nums = {}
    for n in string.gmatch(s, "([%-%d]+)") do table.insert(nums, tonumber(n)) end
    if #nums ~= 6 then return false end
    g_calib.ax, g_calib.ay, g_calib.az = nums[1], nums[2], nums[3]
    g_calib.gx, g_calib.gy, g_calib.gz = nums[4], nums[5], nums[6]
    g_calib.ready = true
    log.info("exs_mpu6050", "已加载校准",
        string.format("g:(%d,%d,%d) a:(%d,%d,%d)", g_calib.gx,g_calib.gy,g_calib.gz, g_calib.ax,g_calib.ay,g_calib.az))
    return true
end

-- ==================== 器件检测 ====================

local function chip_detect()
    -- 先测 0x68
    i2c.send(g_i2c_id, MPU_ADDR_LOW, REG_WHO_AM_I)
    sys.wait(30)
    local r = i2c.recv(g_i2c_id, MPU_ADDR_LOW, 1)
    if r and r:byte() == MPU_WHO_AM_I then
        g_i2c_addr = MPU_ADDR_LOW
        return true
    end
    -- 再测 0x69
    i2c.send(g_i2c_id, MPU_ADDR_HIGH, REG_WHO_AM_I)
    sys.wait(30)
    r = i2c.recv(g_i2c_id, MPU_ADDR_HIGH, 1)
    if r and r:byte() == MPU_WHO_AM_I then
        g_i2c_addr = MPU_ADDR_HIGH
        return true
    end
    return false
end

-- ==================== 外部 API ====================

--[[
初始化 MPU6050 传感器

@api exs_mpu6050.setup(config)

@table config
i2c_id
参数含义：硬件 I2C 总线 ID，例如 i2c1 为 1
数据类型：number
是否必选：必选

addr
参数含义：I2C 设备地址（7 位），默认自动检测 0x68/0x69
数据类型：number
是否必选：可选

gyro_range
参数含义：陀螺仪量程（°/s），可选 250/500/1000/2000，默认 250
数据类型：number
是否必选：可选

accel_range
参数含义：加速度量程（g），可选 2/4/8/16，默认 2
数据类型：number
是否必选：可选

@return boolean 初始化成功返回 true

@usage
-- 硬件 I2C 模式
i2c.setup(1, i2c.FAST)
local result = exs_mpu6050.setup({ i2c_id = 1 })

-- 指定地址 + 量程
local result = exs_mpu6050.setup({ i2c_id = 1, addr = 0x68, gyro_range = 2000 })
]]
function exs_mpu6050.setup(config)
    if type(config) ~= "table" then
        log.error("exs_mpu6050.setup 参数错误：config 应为 table 类型")
        return false
    end
    if not config.i2c_id then
        log.error("exs_mpu6050.setup 参数错误：i2c_id 为必填")
        return false
    end

    g_i2c_id = config.i2c_id
    sys.wait(20)

    -- 自动检测或使用指定地址
    if config.addr then
        g_i2c_addr = config.addr
    elseif not chip_detect() then
        log.error("exs_mpu6050.setup 未检测到设备，请检查接线")
        return false
    end

    -- 验证 WHO_AM_I
    local who = r8(REG_WHO_AM_I)
    log.info("exs_mpu6050", "WHO_AM_I", string.format("0x%02X", who),
        "addr", string.format("0x%02X", g_i2c_addr))
    if who ~= MPU_WHO_AM_I then
        log.error("exs_mpu6050.setup 设备ID不匹配")
        return false
    end

    -- 复位并唤醒
    w8(REG_PWR_MGMT_1, 0x80); sys.wait(100)
    w8(REG_PWR_MGMT_1, 0x00); sys.wait(100)

    -- 配置量程
    local gyro_range  = config.gyro_range  or 250
    local accel_range = config.accel_range or 2
    local gyro_cfg  = ({ [250]=0, [500]=0x08, [1000]=0x10, [2000]=0x18 })[gyro_range] or 0
    local accel_cfg = ({ [2]=0, [4]=0x08, [8]=0x10, [16]=0x18 })[accel_range] or 0

    w8(REG_SMPLRT_DIV, 0x07)     -- 125Hz
    w8(REG_CONFIG, 0x06)         -- 低通 5Hz
    w8(REG_GYRO_CONFIG, gyro_cfg)
    w8(REG_ACCEL_CONFIG, accel_cfg)
    w8(REG_PWR_MGMT_1, 0x01)     -- PLL X轴
    w8(REG_PWR_MGMT_2, 0x00)     -- 全部使能
    sys.wait(50)

    -- 加载校准
    if not calib_load() then
        log.info("exs_mpu6050", "未找到校准数据，如需校准请调用 calibrate()")
    end

    g_cf_t = os.clock()
    g_ready = true
    log.info("exs_mpu6050", string.format("初始化完成, gyro=%d accel=%dg", gyro_range, accel_range))
    return true
end

--[[
读取加速度、陀螺仪、温度数据

@api exs_mpu6050.get_data()

@return table or nil
成功返回 {accel={x,y,z} 单位g, gyro={x,y,z} 单位°/s, temp 单位°C}
失败返回 nil

@usage
local data = exs_mpu6050.get_data()
if data then
    log.info("mpu6050", data.accel.x, data.accel.y, data.accel.z)
end
]]
function exs_mpu6050.get_data()
    if not g_ready then
        log.error("exs_mpu6050.get_data 请先调用 setup()")
        return nil
    end
    local ra = raw_accel()
    local rg = raw_gyro()
    local a, g = apply(ra, rg)
    return {
        accel = { x = a.x / ACCEL_SEN, y = a.y / ACCEL_SEN, z = a.z / ACCEL_SEN },
        gyro  = { x = g.x / GYRO_SEN,  y = g.y / GYRO_SEN,  z = g.z / GYRO_SEN },
        temp  = s16(REG_TEMP_H) / TEMP_SEN + TEMP_OFF,
    }
end

--[[
读取倾角（加速度计直接计算，静态准，动态有噪声）

@api exs_mpu6050.get_tilt()

@return number,number pitch(俯仰°), roll(横滚°)

@usage
local pitch, roll = exs_mpu6050.get_tilt()
]]
function exs_mpu6050.get_tilt()
    if not g_ready then
        log.error("exs_mpu6050.get_tilt 请先调用 setup()")
        return nil, nil
    end
    local ra = raw_accel()
    local a, _ = apply(ra, { x = 0, y = 0, z = 0 })
    local ax, ay, az = a.x / ACCEL_SEN, a.y / ACCEL_SEN, a.z / ACCEL_SEN
    local pitch = math.deg(math.atan2(ay, math.sqrt(ax * ax + az * az)))
    local roll  = math.deg(math.atan2(ax, math.sqrt(ay * ay + az * az)))
    return pitch, roll
end

--[[
读取姿态角（互补滤波，需在循环中持续调用以保持积分状态）

@api exs_mpu6050.get_attitude()

@return number,number pitch(俯仰°), roll(横滚°)

@usage
while true do
    local p, r = exs_mpu6050.get_attitude()
    sys.wait(10)
end
]]
function exs_mpu6050.get_attitude()
    if not g_ready then
        log.error("exs_mpu6050.get_attitude 请先调用 setup()")
        return nil, nil
    end
    local ra = raw_accel()
    local rg = raw_gyro()
    local a, g = apply(ra, rg)

    local ax, ay, az = a.x / ACCEL_SEN, a.y / ACCEL_SEN, a.z / ACCEL_SEN
    local gx, gy     = g.x / GYRO_SEN,  g.y / GYRO_SEN

    local acc_p = math.deg(math.atan2(ay, math.sqrt(ax * ax + az * az)))
    local acc_r = math.deg(math.atan2(ax, math.sqrt(ay * ay + az * az)))

    local now = os.clock()
    local dt  = now - g_cf_t
    if dt <= 0 or dt > 1 then dt = 0.01 end
    g_cf_t = now

    local alpha = 0.96
    g_cf_pitch = alpha * (g_cf_pitch + gx * dt) + (1 - alpha) * acc_p
    g_cf_roll  = alpha * (g_cf_roll  + gy * dt) + (1 - alpha) * acc_r

    return g_cf_pitch, g_cf_roll
end

--[[
碰撞/敲击检测

@api exs_mpu6050.detect_tap(threshold, debounce_ms)

@number threshold  加速度阈值(g)，默认 2.0
@number debounce_ms 去抖时间(ms)，默认 500

@return boolean 检测到碰撞返回 true

@usage
if exs_mpu6050.detect_tap(2.0, 500) then
    log.info("碰撞!")
end
]]
function exs_mpu6050.detect_tap(threshold, debounce_ms)
    if not g_ready then return false end
    threshold = threshold or 2.0
    debounce_ms = debounce_ms or 500
    local ra = raw_accel()
    local a, _ = apply(ra, { x = 0, y = 0, z = 0 })
    local ax, ay, az = a.x / ACCEL_SEN, a.y / ACCEL_SEN, a.z / ACCEL_SEN
    local m = math.sqrt(ax * ax + ay * ay + az * az)
    if m > threshold then
        local now = os.clock() * 1000
        if now - g_tap_t > debounce_ms then
            g_tap_t = now
            return true
        end
    end
    return false
end

--[[
自由落体/失重检测

@api exs_mpu6050.detect_freefall(threshold)

@number threshold 加速度矢量和阈值(g)，默认 0.3

@return boolean 疑似自由落体返回 true

@usage
if exs_mpu6050.detect_freefall(0.3) then
    log.warn("自由落体!")
end
]]
function exs_mpu6050.detect_freefall(threshold)
    if not g_ready then return false end
    threshold = threshold or 0.3
    local ra = raw_accel()
    local a, _ = apply(ra, { x = 0, y = 0, z = 0 })
    local ax, ay, az = a.x / ACCEL_SEN, a.y / ACCEL_SEN, a.z / ACCEL_SEN
    return math.sqrt(ax * ax + ay * ay + az * az) < threshold
end

--[[
手动校准零偏（设备必须水平静止）

采集 200 组数据取平均值，自动过滤振动，校准结果保存到 KV 存储，
后续 get_data/get_tilt/get_attitude 自动应用校准。

@api exs_mpu6050.calibrate()

@return boolean 成功返回 true

@usage
local ok = exs_mpu6050.calibrate()
if ok then log.info("校准完成") end
]]
function exs_mpu6050.calibrate()
    if not g_ready then
        log.error("exs_mpu6050.calibrate 请先调用 setup()")
        return false
    end

    local N       = 200
    local MIN_S   = 50
    local last    = nil
    local s_cnt   = 0
    local valid   = 0
    local sx, sy, sz     = 0, 0, 0
    local sgx, sgy, sgz  = 0, 0, 0

    log.info("exs_mpu6050", "校准开始，请保持静止...")

    for i = 1, N do
        local a = raw_accel()
        local g = raw_gyro()

        if stationary(last, a) then
            s_cnt = s_cnt + 1
        else
            if s_cnt > 10 then log.warn("exs_mpu6050", "检测到振动，重新等待静止") end
            s_cnt = 0
            last = a
            sys.wait(10)
            goto next
        end
        last = a

        if s_cnt < 20 then sys.wait(10); goto next end

        sx  = sx  + a.x;  sy  = sy  + a.y;  sz  = sz  + a.z
        sgx = sgx + g.x;  sgy = sgy + g.y;  sgz = sgz + g.z
        valid = valid + 1

        ::next::
        sys.wait(10)
    end

    if valid < MIN_S then
        log.error("exs_mpu6050", string.format("有效采样不足(%d/%d)，校准失败", valid, MIN_S))
        return false
    end

    g_calib.gx = math.floor(sgx / valid)
    g_calib.gy = math.floor(sgy / valid)
    g_calib.gz = math.floor(sgz / valid)
    g_calib.ax = math.floor(sx  / valid)
    g_calib.ay = math.floor(sy  / valid)
    g_calib.az = math.floor(sz  / valid) - 16384

    g_calib.ready = true
    calib_save()

    log.info("exs_mpu6050", string.format("校准完成 有效:%d g:(%d,%d,%d) a:(%d,%d,%d)",
        valid, g_calib.gx,g_calib.gy,g_calib.gz, g_calib.ax,g_calib.ay,g_calib.az))
    return true
end

--[[
查询校准状态

@api exs_mpu6050.is_calibrated()

@return boolean 已校准返回 true
]]
function exs_mpu6050.is_calibrated()
    return g_calib.ready
end

-- ==================== DMP（需 dmp_firmware.lua） ====================

--[[
DMP 硬件姿态解算初始化

需将 DMP 固件（InvenSense MotionApps v20）放入 lib/dmp_firmware.lua。
固件获取：GitHub jrowberg/i2cdevlib → MPU6050_6Axis_MotionApps20.cpp → dmpMemory 数组

@api exs_mpu6050.dmp_init()

@return boolean 成功返回 true，未找到固件返回 false

@usage
if exs_mpu6050.dmp_init() then
    while true do
        local r, p, y = exs_mpu6050.dmp_get_euler()
        sys.wait(20)
    end
end
]]
function exs_mpu6050.dmp_init()
    if not g_ready then
        log.error("exs_mpu6050.dmp_init 请先调用 setup()")
        return false
    end

    local ok, fw = pcall(require, "dmp_firmware")
    if not ok or type(fw) ~= "table" or #fw < 250 then
        log.error("exs_mpu6050", "dmp_firmware.lua 未找到或格式错误")
        log.error("exs_mpu6050", "获取: GitHub i2cdevlib > MotionApps20.cpp > dmpMemory[] 转为 Lua table")
        return false
    end

    log.info("exs_mpu6050", "DMP固件加载中, " .. tostring(#fw) .. "字节")

    -- 复位
    w8(REG_PWR_MGMT_1, 0x80); sys.wait(100)
    w8(REG_PWR_MGMT_1, 0x00); sys.wait(100)

    -- 传感器配置
    w8(REG_GYRO_CONFIG, 0x18)    -- ±2000°/s
    w8(REG_ACCEL_CONFIG, 0x00)   -- ±2g
    w8(REG_SMPLRT_DIV, 0x04)     -- 200Hz
    w8(REG_CONFIG, 0x02)         -- DLPF 98Hz

    -- 写入固件
    local fw_s = string.char(table.unpack(fw))
    local addr, pos = 0, 1
    while pos <= #fw_s do
        local chunk = fw_s:sub(pos, pos + 255)
        w8(REG_MEM_BANK, (addr >> 8) & 0x1F)
        w8(REG_MEM_ADDR, addr & 0xFF)
        local cp = 1
        while cp <= #chunk do
            local cl = math.min(32, #chunk - cp + 1)
            local buf = { REG_MEM_DATA }
            for i = 0, cl - 1 do buf[#buf + 1] = chunk:byte(cp + i) end
            i2c.send(g_i2c_id, g_i2c_addr, buf)
            cp = cp + cl
        end
        addr = addr + #chunk; pos = pos + #chunk
    end
    log.info("exs_mpu6050", "固件写入完成")

    -- FIFO Rate Divisor
    w8(REG_MEM_BANK, 0x02)
    w8(REG_MEM_ADDR, 0x16)
    i2c.send(g_i2c_id, g_i2c_addr, { REG_MEM_DATA, 0x00, 0x01 })

    -- DMP 配置寄存器
    i2c.send(g_i2c_id, g_i2c_addr, {0x71, 0x03}); sys.wait(10)
    i2c.send(g_i2c_id, g_i2c_addr, {0x72, 0x00}); sys.wait(10)

    -- 时钟 + 中断
    w8(REG_PWR_MGMT_1, 0x03)
    w8(0x37, 0x00)
    w8(REG_INT_ENABLE, 0x32)
    sys.wait(50)

    -- 复位 FIFO + 使能 DMP
    w8(REG_USER_CTRL, 0x44); sys.wait(15)
    w8(REG_USER_CTRL, 0x40); sys.wait(15)
    w8(REG_FIFO_EN, 0xF8)
    w8(REG_USER_CTRL, 0x48)
    sys.wait(100)

    log.info("exs_mpu6050", "DMP 就绪")
    return true
end

local function dmp_read_fifo(n)
    if not n or n < 42 then return nil end
    local buf = rN(REG_FIFO_RW, n)
    if not buf or #buf < 42 then return nil end
    local function q16(o)
        local v = (buf:byte(o) << 8) | buf:byte(o + 1)
        if v >= 0x8000 then v = v - 0x10000 end
        return v / 16384.0
    end
    return { w = q16(1), x = q16(5), y = q16(9), z = q16(13) }
end

--[[
读取 DMP 四元数

@api exs_mpu6050.dmp_get_quaternion()

@return table or nil {w,x,y,z}
]]
function exs_mpu6050.dmp_get_quaternion()
    if not g_ready then return nil end
    local d = rN(REG_FIFO_COUNT, 2)
    if not d or #d < 2 then return nil end
    local n = (d:byte(1) << 8) | d:byte(2)
    return dmp_read_fifo(n)
end

--[[
读取 DMP 欧拉角

@api exs_mpu6050.dmp_get_euler()

@return number,number,number roll, pitch, yaw（度），失败返回 nil

@usage
local r, p, y = exs_mpu6050.dmp_get_euler()
]]
function exs_mpu6050.dmp_get_euler()
    local q = exs_mpu6050.dmp_get_quaternion()
    if not q then return nil, nil, nil end
    local r = math.deg(math.atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)))
    local asin_v = 2 * (q.w * q.y - q.z * q.x)
    if asin_v > 1 then asin_v = 1 elseif asin_v < -1 then asin_v = -1 end
    local p = math.deg(math.asin(asin_v))
    local y = math.deg(math.atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)))
    return r, p, y
end


--[[
关闭传感器（进入待机模式），关闭后需重新 setup() 才能使用

@api exs_mpu6050.close()

@return nil

@usage
exs_mpu6050.close()
]]
function exs_mpu6050.close()
    if not g_ready then return end
    w8(REG_PWR_MGMT_1, 0x40)   -- 休眠模式
    g_ready = false
    g_i2c_id = nil
    g_i2c_addr = nil
    log.info("exs_mpu6050", "传感器已关闭")
end

-- ==================== 版本号 ====================

--[[
获取 exs_mpu6050 库的版本号

@api exs_mpu6050.version()

@return string 版本号字符串，格式 "yyyymmddhhmm"

@usage
local ver = exs_mpu6050.version()
]]
function exs_mpu6050.version()
    return "202607231800"
end

log.debug("exs_mpu6050", "version -> " .. exs_mpu6050.version())

return exs_mpu6050