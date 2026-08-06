--[[
@module  exs_bmi270
@summary BMI270 六轴惯性传感器（3轴加速度计+3轴陀螺仪）扩展库
@version 1.0
@date    2026.08.03
@author  江访
@usage
本文件为 Bosch BMI270 六轴惯性传感器（3 轴加速度计 + 3 轴陀螺仪）的 LuatOS 扩展库。
支持 I2C 与 SPI 两种通信接口，内置 Mahony 互补滤波姿态解算。

-- 加载扩展库
local exs_bmi270 = require "exs_bmi270"

-- 软件 I2C 方式初始化（scl/sda 引脚号按硬件连接填写）
local ok = exs_bmi270.setup("I2C", {scl = 31, sda = 30})
if not ok then return end

-- 读取三轴加速度（单位 g，静止水平时 Z≈1g）
local acc = exs_bmi270.get_accel()
log.info("exs_bmi270", string.format("acc:(%.3f,%.3f,%.3f)g", acc.x, acc.y, acc.z))

-- 读取姿态角（roll/pitch/yaw，需循环持续调用）
local roll, pitch, yaw = exs_bmi270.get_attitude()
log.info("exs_bmi270", string.format("r:%.1f p:%.1f y:%.1f", roll, pitch, yaw))

对外接口 19 个：
- exs_bmi270.setup(model, config)：初始化（I2C/SPI），支持 int1/int2 中断配置
- exs_bmi270.get_data()：读取加速度+角速度+温度
- exs_bmi270.get_raw()：读取原始 ADC 值
- exs_bmi270.get_accel()：读取三轴加速度（g）
- exs_bmi270.get_gyro()：读取三轴角速度（°/s）
- exs_bmi270.get_temp()：读取温度（°C）
- exs_bmi270.get_attitude()：Mahony 姿态解算（roll/pitch/yaw）
- exs_bmi270.set_acc_range()：切换加速度量程
- exs_bmi270.set_gyro_range()：切换陀螺仪量程
- exs_bmi270.calibrate_gyro()：陀螺零偏标定（需保持静止）
- exs_bmi270.int_config()：配置中断事件（int1/int2）
- exs_bmi270.get_int_status()：读取中断状态（读后清除）
- exs_bmi270.get_step_count()：读取累计步数（32 位）
- exs_bmi270.reset_step_count()：清零步数计数器
- exs_bmi270.reset()：软复位并重新初始化
- exs_bmi270.sleep()：进入休眠
- exs_bmi270.wakeup()：从休眠唤醒
- exs_bmi270.close()：释放资源
- exs_bmi270.version()：获取版本号

=== 版本更新说明 ===
-- 版本号：202608051200
-- 1、更新时间：2026-08-05 12:00
-- 2、更新内容：第一版发布，实现功能如下：
--   - 支持 I2C（软件/硬件）与 SPI 两种通信接口初始化，自动完成芯片 ID 校验、微程序加载、量程/采样率配置
--   - 数据读取：三轴加速度（g）、三轴角速度（°/s）、温度（°C）、原始 ADC 值、组合数据 get_data()
--   - Mahony 互补滤波姿态解算 get_attitude()，输出 roll/pitch/yaw，陀螺零偏标定 calibrate_gyro()
--   - 运行时量程/采样率切换 set_acc_range()/set_gyro_range()，软复位 reset()，休眠/唤醒 sleep()/wakeup()，关闭 close()
--   - 中断功能：data_ready 数据就绪 + any_motion/no_motion/sig_motion/step 特征中断，
--     支持阈值/时长/计步间隔参数可调，topic 或 cb 两种回调方式，get_int_status() 查询触发事件
--   - 计步功能：get_step_count() 读取 32 位累计步数，reset_step_count() 清零，step_watermark_steps 控制刷新间隔
--   - I2C 总线卡死自动恢复、软复位后中断配置自动重应用
--   - 修复：特征中断使能时 enable 位未置 1 的问题（any_motion/no_motion/sig_motion 此前仅写映射未真正使能）

]]

local exs_bmi270                          = {}

-- ==================== 寄存器地址 ====================

local REG_CHIP_ID                         = 0x00      -- 芯片 ID 寄存器（BMI270 固定 0x24）
local REG_ACC_X_LSB                       = 0x0C      -- 加速度 X 低字节（0x0C~0x11 连续 6 字节，LSB 先）
local REG_GYRO_X_LSB                      = 0x12      -- 陀螺仪 X 低字节（0x12~0x17 连续 6 字节，LSB 先）
local REG_SC_OUT_0                        = 0x1E      -- 步数低 16 位主寄存器（0x1E~0x1F，备用；get_step_count 改用特征页0 读完整 32 位）
local REG_INTERNAL_STATUS                 = 0x21      -- 内部状态（非零即配置加载成功）
local REG_TEMP_LSB                        = 0x22      -- 温度低字节（0x22~0x23 连续 2 字节，LSB 先）
local REG_ACC_CONF                        = 0x40      -- 加速度配置（ODR bit[3:0]，BWP bit[6:4]，filter_perf bit7）
local REG_ACC_RANGE                       = 0x41      -- 加速度量程（bit[1:0]）
local REG_GYR_CONF                        = 0x42      -- 陀螺仪配置（ODR bit[3:0]，BWP bit[5:4]，filter_perf bit7）
local REG_GYR_RANGE                       = 0x43      -- 陀螺仪量程（bit[2:0]）
local REG_INIT_CTRL                       = 0x59      -- 初始化控制（写 0 使能加载，写 1 禁止加载）
local REG_INIT_ADDR_0                     = 0x5B      -- 配置基址低4位（字地址 bit[3:0]，分块加载定位用）
local REG_INIT_ADDR_1                     = 0x5C      -- 配置基址高8位（字地址 bit[11:4]）
local REG_INIT_DATA                       = 0x5E      -- 初始化数据端口（突发写，地址由 INIT_ADDR 定位，不自增）
local REG_IF_CONF                         = 0x6B      -- 接口配置（bit7=0 四线 SPI / I2C）
local REG_NV_CONF                         = 0x70      -- 非易失配置（bit0=1 SPI 模式，NVM 寄存器写入次数有限）
local REG_PWR_CONF                        = 0x7C      -- 电源配置（bit0=0 关闭省电模式）
local REG_PWR_CTRL                        = 0x7D      -- 电源控制（aux_en bit0，gyr_en bit1，acc_en bit2，temp_en bit3）
local REG_CMD                             = 0x7E      -- 命令寄存器（0xB6=软复位，0x02=ACC正常模式，0x03=GYR正常模式）

-- ==================== 中断寄存器地址 ====================
-- 来源：Bosch 官方 bmi2_defs.h v2.113.0 + bmi270.h v2.86.1
local REG_INT_STATUS_0                    = 0x1C      -- 特征中断状态（sig_motion/step/no_motion/any_motion），读后清除
local REG_INT_STATUS_1                    = 0x1D      -- 数据中断状态（acc/gyr_drdy、fifo_wm/ffull、err），读后清除
local REG_INT1_IO_CTRL                    = 0x53      -- INT1 引脚电气配置（input_en/output_en/od/lvl）
local REG_INT2_IO_CTRL                    = 0x54      -- INT2 引脚电气配置
local REG_INT_LATCH                       = 0x55      -- 中断锁存（bit0=1 电平锁存，0=脉冲）
local REG_INT1_MAP_FEAT                   = 0x56      -- 特征中断 → INT1 映射
local REG_INT2_MAP_FEAT                   = 0x57      -- 特征中断 → INT2 映射
local REG_INT_MAP_DATA                    = 0x58      -- 数据中断 → INT1(低4位)/INT2(高4位) 映射

-- INT1/INT2_IO_CTRL 位掩码
local INT_IO_INPUT_EN                     = 0x10      -- bit4 输入使能
local INT_IO_OUTPUT_EN                    = 0x08      -- bit3 输出使能
local INT_IO_OPEN_DRAIN                   = 0x04      -- bit2 开漏（1=开漏，0=推挽）
local INT_IO_LEVEL                        = 0x02      -- bit1 有效电平（1=高有效，0=低有效）

-- INT_STATUS_0 (0x1C) 特征中断状态位（读后清除），来源：数据手册 5.2.28
local INT_SIG_MOTION                      = 0x01      -- bit0 sig_motion_out 显著运动
local INT_STEP_DETECTOR                   = 0x02      -- bit1 step_counter_out 步进检测
local INT_NO_MOTION                       = 0x20      -- bit5 no_motion_out 无运动
local INT_ANY_MOTION                      = 0x40      -- bit6 any_motion_out 任意运动

-- INT_STATUS_1 (0x1D) 数据中断状态位（读后清除），来源：数据手册 5.2.29
local INT_FFULL                           = 0x01      -- bit0 ffull_int FIFO 满
local INT_FWM                             = 0x02      -- bit1 fwm_int FIFO 水位
local INT_ERR                             = 0x04      -- bit2 err_int 错误
local INT_AUX_DRDY                        = 0x20      -- bit5 aux_drdy_int 辅助传感器就绪
local INT_GYR_DRDY                        = 0x40      -- bit6 gyr_drdy_int 陀螺仪数据就绪
local INT_ACC_DRDY                        = 0x80      -- bit7 acc_drdy_int 加速度计数据就绪

-- INT_MAP_DATA 数据中断映射位（INT1 用低4位，INT2 用高4位）
local INT_MAP_FFULL                       = 0x01      -- FIFO 满 → INT1
local INT_MAP_FWM                         = 0x02      -- FIFO 水位 → INT1
local INT_MAP_DRDY                        = 0x04      -- 数据就绪 → INT1
local INT_MAP_ERR                         = 0x08      -- 错误 → INT1

-- INT1/INT2_MAP_FEAT 特征中断映射位
local INT_MAP_FEAT_SIG_MOT                = 0x01      -- 显著运动
local INT_MAP_FEAT_STEP                   = 0x02      -- 步进检测
local INT_MAP_FEAT_NO_MOT                 = 0x20      -- 无运动
local INT_MAP_FEAT_ANY_MOT                = 0x40      -- 任意运动

-- 特征配置寄存器（FEAT_PAGE 分页 + FEATURES 16 字节窗口，16 位字对齐写）
local REG_FEAT_PAGE                       = 0x2F      -- 特征页选择（bit[2:0]，0~7）
local REG_FEATURES                        = 0x30      -- 特征配置窗口（0x30~0x3F 共 16 字节）
local FEAT_PAGE_ANY_MOT                   = 1         -- any_motion 所在页
local FEAT_PAGE_NO_MOT                    = 2         -- no_motion 所在页
local FEAT_PAGE_SIG_MOT                   = 2         -- sig_motion 所在页
local FEAT_PAGE_STEP                      = 6         -- step counter/detector 所在页

-- any_motion 配置（页1）：ANYMO_1@0x3C（页内偏移 0x0C），ANYMO_2@0x3E（页内偏移 0x0E）
-- 数据手册 4.8.2：ANYMO_1[12:0]=duration(20ms/点)、[13]=select_x、[14]=select_y、[15]=select_z
--              ANYMO_2[10:0]=threshold、[14:11]=out_conf、[15]=enable
local FEAT_ANYMO_OFFSET                   = 0x0C      -- ANYMO_1 页内偏移
local FEAT_ANYMO_1_DEFAULT                = 0xE005    -- duration=5(100ms) + 三轴全选
local FEAT_ANYMO_2_DEFAULT                = 0x38AA    -- threshold=0xAA(83mg) + out_conf=0x7(→INT_STATUS_0 bit6) + enable=0
local FEAT_ANYMO_2_EN_MASK                = 0x8000    -- enable 位 bit15

-- no_motion 配置（页2）：NOMO_1@0x30（页内偏移 0x00），NOMO_2@0x32（页内偏移 0x02）
-- 数据手册 4.8.3：NOMO_1[12:0]=duration、[13]=select_x、[14]=select_y、[15]=select_z
--              NOMO_2[10:0]=threshold、[14:11]=out_conf、[15]=enable
local FEAT_NOMO_OFFSET                    = 0x00      -- NOMO_1 页内偏移
local FEAT_NOMO_1_DEFAULT                 = 0xE005    -- duration=5(100ms) + 三轴全选
local FEAT_NOMO_2_DEFAULT                 = 0x3090    -- threshold=0x90(70mg) + out_conf=0x6(→INT_STATUS_0 bit5) + enable=0
local FEAT_NOMO_2_EN_MASK                 = 0x8000    -- enable 位 bit15

-- sig_motion 配置（页2）：SIGMO_1@0x34（页内偏移 0x04），SIGMO_2@0x3E（页内偏移 0x0E）
-- 数据手册 4.8.4：SIGMO_1[15:0]=block_size(20ms/点，默认 0xFA=5秒)
--              SIGMO_2[0]=enable、[4:1]=out_conf
local FEAT_SIGMO_OFFSET                   = 0x04      -- SIGMO_1 页内偏移
local FEAT_SIGMO_1_DEFAULT                = 0x00FA    -- block_size=250(5秒)
local FEAT_SIGMO_2_DEFAULT                = 0x0002    -- out_conf=0x1(→INT_STATUS_0 bit0) + enable=0
local FEAT_SIGMO_2_EN_MASK                = 0x0001    -- enable 位 bit0

-- step 配置（页6）：SC_26@0x32（页内偏移 0x02），SC_27@0x34（页内偏移 0x04）
-- 数据手册 4.8.8：SC_26[9:0]=watermark_level、[10]=reset_counter、[11]=en_detector、[12]=en_counter、[13]=en_activity
--              SC_27[3:0]=out_conf_step_detector(默认 0x2→INT_STATUS_0 bit1)
local FEAT_SC26_OFFSET                    = 0x02      -- SC_26 页内偏移
local FEAT_SC26_EN_DETECTOR               = 0x0800    -- bit11 en_detector
local FEAT_SC26_EN_COUNTER                = 0x1000    -- bit12 en_counter

-- 中断引脚电平（供 gpio.setup 中断触发沿选择）
local INT_LEVEL_ACTIVE_HIGH               = 1         -- 高有效 → RISING
local INT_LEVEL_ACTIVE_LOW                = 0         -- 低有效 → FALLING

-- ==================== 常量 ====================

local CHIP_ID_BMI270                      = 0x24      -- BMI270 芯片 ID 期望值
local CMD_SOFTRESET                       = 0xB6      -- 软复位命令
local PWR_CTRL_EN                         = 0x0E      -- acc_en(bit2)+gyr_en(bit1)+temp_en(bit3)，aux_en(bit0)=0

-- 加速度量程：字符串 → 寄存器值
local ACC_RANGE_2G                        = 0x00      -- ±2g
local ACC_RANGE_4G                        = 0x01      -- ±4g
local ACC_RANGE_8G                        = 0x02      -- ±8g
local ACC_RANGE_16G                       = 0x03      -- ±16g

-- 陀螺仪量程：字符串 → 寄存器值
local GYR_RANGE_2000                      = 0x00      -- ±2000°/s
local GYR_RANGE_1000                      = 0x01      -- ±1000°/s
local GYR_RANGE_500                       = 0x02      -- ±500°/s
local GYR_RANGE_250                       = 0x03      -- ±250°/s
local GYR_RANGE_125                       = 0x04      -- ±125°/s

-- 加速度采样率寄存器值（ACC_CONF bit[3:0]，来源：bmi270-main 参考工程）
local ACC_ODR_25                          = 0x06      -- 25 Hz
local ACC_ODR_50                          = 0x07      -- 50 Hz
local ACC_ODR_100                         = 0x08      -- 100 Hz
local ACC_ODR_200                         = 0x09      -- 200 Hz（默认）
local ACC_ODR_400                         = 0x0A      -- 400 Hz
local ACC_ODR_800                         = 0x0B      -- 800 Hz
local ACC_ODR_1600                        = 0x0C      -- 1600 Hz

-- 陀螺仪采样率寄存器值（GYR_CONF bit[3:0]，来源：bmi270-main 参考工程）
local GYR_ODR_25                          = 0x06      -- 25 Hz
local GYR_ODR_50                          = 0x07      -- 50 Hz
local GYR_ODR_100                         = 0x08      -- 100 Hz
local GYR_ODR_200                         = 0x09      -- 200 Hz（默认）
local GYR_ODR_400                         = 0x0A      -- 400 Hz
local GYR_ODR_800                         = 0x0B      -- 800 Hz
local GYR_ODR_1600                        = 0x0C      -- 1600 Hz
local GYR_ODR_3200                        = 0x0D      -- 3200 Hz

-- 加速度灵敏度（LSB/g，来源：BMI270 数据手册第 4.6.6 节）
local ACC_SENS_2G                         = 16384     -- ±2g
local ACC_SENS_4G                         = 8192      -- ±4g
local ACC_SENS_8G                         = 4096      -- ±8g
local ACC_SENS_16G                        = 2048      -- ±16g

-- 陀螺仪灵敏度（LSB/(°/s)，来源：BMI270 数据手册第 4.6.7 节）
local GYR_SENS_2000                       = 16.4      -- ±2000°/s
local GYR_SENS_1000                       = 32.8      -- ±1000°/s
local GYR_SENS_500                        = 65.6      -- ±500°/s
local GYR_SENS_250                        = 131.2     -- ±250°/s
local GYR_SENS_125                        = 262.4     -- ±125°/s

local CONFIG_LOAD_WAIT_MS                 = 100       -- 配置加载后等待微程序生效（Bosch v2.71.8 数据手册要求 140ms，取 100ms+双读兜底）
local CONFIG_APPLY_WAIT_MS                = 50        -- 量程/采样率配置后等待生效+传感器稳定，50ms
local DEFAULT_DT                          = 0.005     -- 姿态解算默认积分步长，0.005s（对应 200Hz）

-- ==================== 内部状态变量 ====================

local g_iface                             = nil       -- 通信接口："I2C" / "SPI"
local g_i2c_bus                           = 0         -- I2C 总线 ID
local g_dev_addr                          = 0x68      -- I2C 设备地址（多地址 0x68/0x69 由 SDO 引脚决定，setup 自动探测后锁定）
local g_is_soft                           = false     -- 是否软件 I2C
local g_scl_pin                           = nil       -- SCL 引脚（总线恢复用）
local g_sda_pin                           = nil       -- SDA 引脚（总线恢复用）
local g_i2c_speed                         = i2c.FAST  -- 硬件 I2C 原始 speed（总线恢复后恢复）
local g_spi_dev                           = nil       -- SPI 设备对象
local g_ready                             = false     -- 是否已初始化
local g_acc_sens                          = ACC_SENS_4G    -- 当前加速度灵敏度（LSB/g）
local g_gyro_sens                         = GYR_SENS_500   -- 当前陀螺仪灵敏度（LSB/(°/s)）
local g_acc_range_reg                     = ACC_RANGE_4G   -- 当前加速度量程寄存器值
local g_gyro_range_reg                    = GYR_RANGE_500  -- 当前陀螺仪量程寄存器值
local g_acc_odr_reg                       = ACC_ODR_200    -- 当前加速度采样率寄存器值
local g_gyro_odr_reg                      = GYR_ODR_200    -- 当前陀螺仪采样率寄存器值

-- 姿态解算状态（Mahony 互补滤波）
local g_q0                                = 1.0       -- 四元数实部
local g_q1                                = 0.0       -- 四元数虚部 x
local g_q2                                = 0.0       -- 四元数虚部 y
local g_q3                                = 0.0       -- 四元数虚部 z
local g_int_x                             = 0.0       -- 陀螺误差积分 x
local g_int_y                             = 0.0       -- 陀螺误差积分 y
local g_int_z                             = 0.0       -- 陀螺误差积分 z
local g_last_yaw                          = 0.0       -- 上一次原始 yaw（角度叠加用）
local g_unwrapped_yaw                     = 0.0       -- 连续无回绕 yaw
local g_yaw_first                         = true      -- yaw 首次计算标志
local g_last_time                         = 0.0       -- 上一次姿态解算时间（秒）
local g_raw_debug_logged                  = false     -- 原始数据调试日志是否已打印

-- 陀螺零偏标定状态
local g_gyro_bias_x                       = 0.0       -- 陀螺 X 轴零偏（°/s）
local g_gyro_bias_y                       = 0.0       -- 陀螺 Y 轴零偏（°/s）
local g_gyro_bias_z                       = 0.0       -- 陀螺 Z 轴零偏（°/s）

-- 中断状态
local g_int1_cb                           = nil       -- INT1 回调函数
local g_int2_cb                           = nil       -- INT2 回调函数
local g_int1_gpio                         = nil       -- INT1 GPIO 引脚号（close 注销用）
local g_int2_gpio                         = nil       -- INT2 GPIO 引脚号（close 注销用）
local g_int1_level                        = INT_LEVEL_ACTIVE_LOW  -- INT1 有效电平（BMI270 默认低有效）
local g_int2_level                        = INT_LEVEL_ACTIVE_LOW  -- INT2 有效电平
local g_int1_cfg                          = nil       -- INT1 中断配置表缓存（软复位后重应用用）
local g_int2_cfg                          = nil       -- INT2 中断配置表缓存（软复位后重应用用）

-- ==================== I2C 总线恢复 ====================

-- I2C 总线硬件恢复：9 个 SCL 脉冲 + 每脉冲检测 SDA 释放 + STOP 信号
-- 注意：此函数被 wr8/rd8 等底层函数调用，而这些底层函数又被 get_accel/get_gyro 等
-- 公开 API 使用——公开 API 可能在协程外调用，因此本函数内部不得使用 sys.wait()。
-- GPIO 操作本身耗时足以满足 I2C 时序（gpio.set/setup/get 每条数十微秒，而
-- 100kHz I2C 每 bit 仅需 10μs），不需要额外延时。
local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return end
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0)                                       -- SCL 拉低
        gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)              -- 检测 SDA 释放
        if gpio.get(g_sda_pin) == 1 then
            gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
            break
        end
        gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
        gpio.set(g_scl_pin, 1)                                       -- SCL 拉高
    end
    gpio.set(g_sda_pin, 0)     -- 起始条件
    gpio.set(g_scl_pin, 1)     -- 结束条件前半
    gpio.set(g_sda_pin, 1)     -- 结束条件后半
end

-- 检测总线是否卡死，卡死后调用 i2c_bus_recovery 恢复
-- 锁死判据：SDA=0, SCL=1（从机锁死 SDA）
-- 恢复后恢复硬件 I2C 原始 speed（g_i2c_speed）
-- 注意：本函数被 wr8/rd8 调用，同样不得使用 sys.wait()
local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP)             -- gpio.setup 自身耗时足够稳定
    local is_stall = (gpio.get(g_sda_pin) == 0 and gpio.get(g_scl_pin) == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end  -- 总线未卡死，无需恢复
    log.warn("exs_bmi270", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_bus, g_i2c_speed) end  -- 恢复硬件 I2C 原始 speed
    return true
end

-- ==================== 底层读写 ====================

-- 写单个寄存器（I2C 带自动卡死恢复，SPI 地址低 7 位）
local function wr8(reg, val)
    if g_iface == "I2C" then
        local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val})
        if not ok then
            if try_bus_recovery() then
                ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val})
            end
        end
        return ok
    else
        -- BMI270 SPI 写协议：地址字节 bit7=0（写），随后跟数据字节
        -- 用 send（纯发送路径）而非 transfer（全双工），避免大块全双工传输在部分平台死机
        -- 校验返回字节数：send 返回实际发送字节数，应等于 2（地址+数据）
        local sent = g_spi_dev:send(string.char(reg & 0x7F, val))
        return (sent ~= nil) and (tonumber(sent) or 0) >= 2
    end
end

-- 读单个寄存器（I2C 带自动卡死恢复，SPI 用 3 字节协议跳过 2 个 dummy 字节）
-- 逻辑分析仪实测：BMI270 SPI 读需 地址|0x80 + 2 个 dummy 时钟字节，数据在第 3 字节
local function rd8(reg)
    if g_iface == "I2C" then
        local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
        if not ok then
            if try_bus_recovery() then
                ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
            end
            if not ok then return nil end
        end
        local d = i2c.recv(g_i2c_bus, g_dev_addr, 1)
        if not d or #d < 1 then return nil end
        return d:byte(1)
    else
        -- BMI270 SPI 读协议：发送 reg|0x80 + 2 个 dummy 字节，
        -- 返回串第 1 字节为地址期高阻(ff)，第 2 字节为 dummy(00)，第 3 字节才是真实数据
        -- 必须显式传 send_len=3, recv_len=3：luat_spi_device_transfer 在全双工下会把
        -- recv 缓冲扩展为 send_length 再写入，若 recv_len 缺省(默认1)则 1 字节缓冲被写 3 字节，堆溢出
        local d = g_spi_dev:transfer(string.char(reg | 0x80, 0x00, 0x00), 3, 3)
        if not d or #d < 3 then return nil end
        return d:byte(3)
    end
end

-- 连续读 len 字节，返回 string（I2C 直接读；SPI 跳过地址期+2 个 dummy 字节）
local function rd_multi(reg, len)
    if g_iface == "I2C" then
        local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
        if not ok then
            if try_bus_recovery() then
                ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
            end
            if not ok then return nil end
        end
        return i2c.recv(g_i2c_bus, g_dev_addr, len)
    else
        -- SPI 连续读：发送 reg|0x80 + (len+2) 个 dummy，
        -- 前 2 个为 dummy，真实数据从第 3 字节开始
        -- 必须显式传 send_len 和 recv_len，避免全双工下 recv 缓冲按缺省 1 字节分配导致堆溢出
        local total = len + 2
        local d = g_spi_dev:transfer(string.char(reg | 0x80) .. string.rep("\0", total), total, total)
        if not d or #d < total then return nil end
        return d:sub(3, len + 2)
    end
end

-- 连续写多字节（用于 INIT_DATA 微程序加载）
-- INIT_DATA (0x5E) 是 FIFO 写端口：在 INIT_CTRL=0 使能期间，
-- 每次写入都会自动递增内部地址。故可以分批写（每批 64 字节 +
-- 1 字节寄存器地址），共 128 批，这是 Bosch 官方驱动的标准 I2C 做法。
local function wr_multi(reg, data_str)
    if g_iface == "I2C" then
        local total = #data_str
        local off = 1
        while off <= total do
            local chunk = data_str:sub(off, math.min(off + 63, total))
            local ok = i2c.send(g_i2c_bus, g_dev_addr, string.char(reg) .. chunk)
            if not ok then
                if try_bus_recovery() then
                    ok = i2c.send(g_i2c_bus, g_dev_addr, string.char(reg) .. chunk)
                end
                if not ok then return false end
            end
            off = off + 64
        end
        return true
    else
        -- SPI 写：地址 bit7=0 + 连续数据，用 send（纯发送路径，避免全双工大块死机）
        -- 校验返回字节数 = 1(地址) + 数据长度
        local sent = g_spi_dev:send(string.char(reg & 0x7F) .. data_str)
        return (sent ~= nil) and (tonumber(sent) or 0) >= (1 + #data_str)
    end
end

-- ==================== 内部辅助函数 ====================

-- 16-bit 补码解码（LSB 先，来自 i2c.recv 字符串）
local function to_int16(lo, hi)
    local v = (hi << 8) | lo
    if v >= 0x8000 then v = v - 0x10000 end
    return v
end

-- 加速度量程字符串 → 寄存器值 + 灵敏度
local function acc_range_to_params(str)
    if str == "2g" then return ACC_RANGE_2G, ACC_SENS_2G
    elseif str == "8g" then return ACC_RANGE_8G, ACC_SENS_8G
    elseif str == "16g" then return ACC_RANGE_16G, ACC_SENS_16G
    else return ACC_RANGE_4G, ACC_SENS_4G end  -- 默认 ±4g
end

-- 陀螺仪量程字符串 → 寄存器值 + 灵敏度
local function gyro_range_to_params(str)
    if str == "2000" then return GYR_RANGE_2000, GYR_SENS_2000
    elseif str == "1000" then return GYR_RANGE_1000, GYR_SENS_1000
    elseif str == "250" then return GYR_RANGE_250, GYR_SENS_250
    elseif str == "125" then return GYR_RANGE_125, GYR_SENS_125
    else return GYR_RANGE_500, GYR_SENS_500 end  -- 默认 ±500°/s
end

-- 加速度采样率 Hz → 寄存器值（向下取最近的可用档位）
local function acc_odr_to_reg(hz)
    if hz >= 1600 then return ACC_ODR_1600
    elseif hz >= 800 then return ACC_ODR_800
    elseif hz >= 400 then return ACC_ODR_400
    elseif hz >= 200 then return ACC_ODR_200
    elseif hz >= 100 then return ACC_ODR_100
    elseif hz >= 50 then return ACC_ODR_50
    else return ACC_ODR_25 end
end

-- 陀螺仪采样率 Hz → 寄存器值（向下取最近的可用档位）
local function gyro_odr_to_reg(hz)
    if hz >= 3200 then return GYR_ODR_3200
    elseif hz >= 1600 then return GYR_ODR_1600
    elseif hz >= 800 then return GYR_ODR_800
    elseif hz >= 400 then return GYR_ODR_400
    elseif hz >= 200 then return GYR_ODR_200
    elseif hz >= 100 then return GYR_ODR_100
    elseif hz >= 50 then return GYR_ODR_50
    else return GYR_ODR_25 end
end

-- 将内部记录的量程/采样率状态还原为字符串 + 频率（供软复位重初始化使用）
local function current_cfg_to_params()
    local acc_str, gyro_str
    if g_acc_range_reg == ACC_RANGE_2G then acc_str = "2g"
    elseif g_acc_range_reg == ACC_RANGE_8G then acc_str = "8g"
    elseif g_acc_range_reg == ACC_RANGE_16G then acc_str = "16g"
    else acc_str = "4g" end
    if g_gyro_range_reg == GYR_RANGE_2000 then gyro_str = "2000"
    elseif g_gyro_range_reg == GYR_RANGE_1000 then gyro_str = "1000"
    elseif g_gyro_range_reg == GYR_RANGE_250 then gyro_str = "250"
    elseif g_gyro_range_reg == GYR_RANGE_125 then gyro_str = "125"
    else gyro_str = "500" end
    local acc_odr, gyro_odr = 200, 200
    if g_acc_odr_reg == ACC_ODR_1600 then acc_odr = 1600
    elseif g_acc_odr_reg == ACC_ODR_800 then acc_odr = 800
    elseif g_acc_odr_reg == ACC_ODR_400 then acc_odr = 400
    elseif g_acc_odr_reg == ACC_ODR_100 then acc_odr = 100
    elseif g_acc_odr_reg == ACC_ODR_50 then acc_odr = 50
    elseif g_acc_odr_reg == ACC_ODR_25 then acc_odr = 25 end
    if g_gyro_odr_reg == GYR_ODR_3200 then gyro_odr = 3200
    elseif g_gyro_odr_reg == GYR_ODR_1600 then gyro_odr = 1600
    elseif g_gyro_odr_reg == GYR_ODR_800 then gyro_odr = 800
    elseif g_gyro_odr_reg == GYR_ODR_400 then gyro_odr = 400
    elseif g_gyro_odr_reg == GYR_ODR_100 then gyro_odr = 100
    elseif g_gyro_odr_reg == GYR_ODR_50 then gyro_odr = 50
    elseif g_gyro_odr_reg == GYR_ODR_25 then gyro_odr = 25 end
    return acc_str, gyro_str, acc_odr, gyro_odr
end

-- 软复位并等待完成；SPI 模式复位后补一次 dummy 读恢复接口时序（Bosch an005 要求）
-- 用于 setup 及 set_acc_range/set_gyro_range/reset 的重新初始化
local function soft_reset_and_prepare()
    if not wr8(REG_CMD, CMD_SOFTRESET) then return false end
    sys.wait(50)  -- 等待软复位完成，Bosch 手册要求至少 2ms，取 50ms 留足余量
    if g_iface == "SPI" then
        rd8(REG_CHIP_ID)  -- SPI 复位后 dummy 读恢复时序
    end
    return true
end

-- 用加速度计初始姿态构造四元数，替代硬编码 (1,0,0,0)
-- 无论传感器水平/竖直/倾斜安装，启动瞬间姿态即为真实静态姿态，
-- 避免 Mahony 从水平假设经历 90° 收敛导致 roll/pitch 启动爬坡。
-- 输入 ax/ay/az 单位 g（未经归一化也可，内部会处理）
-- 注：需满足本库 quat_to_euler 的旋转约定（q 为 body→world 旋转的共轭），
--     经推导正确形式为 q0=w, q1=ny/(2w), q2=-nx/(2w), q3=0
local function init_quaternion_from_accel(ax, ay, az)
    local mag = math.sqrt(ax * ax + ay * ay + az * az)
    if mag < 0.1 then
        -- 加速度读数异常，回退到水平姿态
        g_q0, g_q1, g_q2, g_q3 = 1.0, 0.0, 0.0, 0.0
        return
    end
    local nx, ny, nz = ax / mag, ay / mag, az / mag
    -- 重力方向与参考 +Z 的点积
    local g = nz + 1.0
    if g < 1e-6 then
        -- 重力沿 -Z（设备倒置），绕 Y 轴旋转 180°
        g_q0, g_q1, g_q2, g_q3 = 0.0, 0.0, 1.0, 0.0
        return
    end
    local w = math.sqrt(0.5 * g)
    local q1 = ny / (2.0 * w)
    local q2 = -nx / (2.0 * w)
    local q3 = 0.0
    -- 归一化
    local norm = math.sqrt(w * w + q1 * q1 + q2 * q2 + q3 * q3)
    if norm < 1e-9 then
        g_q0, g_q1, g_q2, g_q3 = 1.0, 0.0, 0.0, 0.0
        return
    end
    g_q0 = w / norm
    g_q1 = q1 / norm
    g_q2 = q2 / norm
    g_q3 = q3 / norm
end

-- ==================== 中断配置 ====================

-- 将中断状态位转换为事件名数组（按 evt 过滤）
-- evt 为 nil 时报告全部；evt 为表时仅报告表中值为 true 的事件（回调用）
-- 内部函数：不直接用匿名函数，所有函数显式定义
local function collect_events(evt, status0, status1)
    local all = (evt == nil)
    local events = {}
    -- INT_STATUS_1：数据中断（data_ready/fifo_wm/fifo_ffull/error）
    if (all or evt.data_ready) and status1 and status1 & INT_ACC_DRDY ~= 0 then events[#events + 1] = "data_ready" end
    if (all or evt.fifo_wm) and status1 and status1 & INT_FWM ~= 0 then events[#events + 1] = "fifo_wm" end
    if (all or evt.fifo_ffull) and status1 and status1 & INT_FFULL ~= 0 then events[#events + 1] = "fifo_ffull" end
    if (all or evt.error) and status1 and status1 & INT_ERR ~= 0 then events[#events + 1] = "error" end
    -- INT_STATUS_0：特征中断（仅报告用户使能的事件，避免出厂默认 feature 状态位误报）
    if (all or evt.any_motion) and status0 and status0 & INT_ANY_MOTION ~= 0 then events[#events + 1] = "any_motion" end
    if (all or evt.no_motion) and status0 and status0 & INT_NO_MOTION ~= 0 then events[#events + 1] = "no_motion" end
    if (all or evt.sig_motion) and status0 and status0 & INT_SIG_MOTION ~= 0 then events[#events + 1] = "sig_motion" end
    if (all or evt.step) and status0 and status0 & INT_STEP_DETECTOR ~= 0 then events[#events + 1] = "step" end
    return events
end

-- 将特征事件名映射为 INT_MAP_FEAT 位掩码（any_motion/no_motion/sig_motion/step）
local function feature_event_to_mask(evt)
    local m = 0
    if evt.any_motion then m = m | INT_MAP_FEAT_ANY_MOT end
    if evt.no_motion then m = m | INT_MAP_FEAT_NO_MOT end
    if evt.sig_motion then m = m | INT_MAP_FEAT_SIG_MOT end
    if evt.step then m = m | INT_MAP_FEAT_STEP end
    return m
end

-- 读取指定页的 16 字节 FEATURES 窗口（先写 FEAT_PAGE 选页，再连续读 0x30~0x3F）
-- 返回 string 或 nil
local function read_feat_page(page)
    if not wr8(REG_FEAT_PAGE, page) then return nil end
    return rd_multi(REG_FEATURES, 16)
end

-- 写入指定页的 16 字节 FEATURES 窗口（先写 FEAT_PAGE 选页，再连续写 0x30~0x3F）
-- data_str 为 16 字节 string
local function write_feat_page(page, data_str)
    if #data_str ~= 16 then return false end
    if not wr8(REG_FEAT_PAGE, page) then return false end
    return wr_multi(REG_FEATURES, data_str)
end

-- 修改某页 FEATURES 中一个 16 位字段（read-modify-write，保持其余字节不变）
-- page: 页面号；offset: 页内字节偏移（偶数）；val16: 新的 16 位值；mask: 生效位掩码（0xFFFF 表示整字替换）
-- 返回 boolean
local function write_feat_word(page, offset, val16, mask)
    local d = read_feat_page(page)
    if not d or #d < offset + 2 then return false end
    -- 读取当前 16 位（LSB 先）
    local cur = d:byte(offset + 1) | (d:byte(offset + 2) << 8)
    local inv_mask = 0xFFFF & ~mask
    local new = (cur & inv_mask) | (val16 & mask)
    local lo = new & 0xFF
    local hi = (new >> 8) & 0xFF
    -- 从原 16 字节拷贝，仅替换目标 2 字节，保证字对齐
    local data = d:sub(1, offset) .. string.char(lo, hi) .. d:sub(offset + 3, 16)
    return write_feat_page(page, data)
end

-- 使能特征中断（any_motion/no_motion/sig_motion/step）并配置参数
-- cfg: {any_motion, no_motion, sig_motion, step(boolean) 及可选参数 any_motion_thresh_mg/duration_ms 等}
-- 每次 setup 时调用，先把所有请求的特征 enable 位打开
-- 注意：必须在初始化（微程序加载完成）之后、且写特征配置前保持省电关闭状态（init_sequence 末尾已保持 PWR_CONF=0）
-- 注意：int1/int2 可能共享同一特征寄存器，因此 write_feat_word 必须用"仅覆盖所管位"的掩码
--       （mask），不能整字替换，避免后写配置覆盖先写配置。
local function enable_feature_ints(cfg)
    if not cfg or type(cfg) ~= "table" then return end

    -- any_motion：ANYMO_1 设置 duration/三轴选择，ANYMO_2 设置 threshold/out_conf/enable
    if cfg.any_motion then
        -- ANYMO_1：duration(bit[12:0]) + select_x/y/z(bit[15:13])，默认 0xE005（100ms + 三轴）
        if cfg.any_motion_duration_ms ~= nil then
            local dur = math.floor(cfg.any_motion_duration_ms / 20)
            if dur < 0 then dur = 0 end
            if dur > 0x1FFF then dur = 0x1FFF end
            -- 仅覆盖 duration 位，保留 select_x/y/z
            write_feat_word(FEAT_PAGE_ANY_MOT, FEAT_ANYMO_OFFSET, dur, 0x1FFF)
        end

        -- ANYMO_2：threshold(bit[10:0]) + out_conf(bit[14:11])=0x7 + enable(bit15)
        -- 注意：默认值 0x38AA 的 enable 位(bit15)=0，必须显式 OR 上 EN_MASK 才能置 1！
        local anymo2_val = FEAT_ANYMO_2_DEFAULT | FEAT_ANYMO_2_EN_MASK   -- enable=1
        local anymo2_mask = FEAT_ANYMO_2_EN_MASK   -- enable 位必须写
        if cfg.any_motion_thresh_mg ~= nil then
            -- 阈值 LSB ≈ 0.488mg（1g/2047），83mg≈0xAA；换算：reg = round(mg / 0.488)
            local thr = math.floor(cfg.any_motion_thresh_mg / 0.488 + 0.5)
            if thr < 0 then thr = 0 end
            if thr > 0x7FF then thr = 0x7FF end
            anymo2_mask = anymo2_mask | 0x07FF   -- 同时覆盖阈值位
            anymo2_val = (anymo2_val & 0xF800) | (thr & 0x07FF)   -- 替换阈值，保留 out_conf/enable
            local ok = write_feat_word(FEAT_PAGE_ANY_MOT, FEAT_ANYMO_OFFSET + 2, anymo2_val, anymo2_mask)
            if ok then log.info("exs_bmi270", "any_motion 特征已使能（含自定义阈值）") end
        else
            local ok = write_feat_word(FEAT_PAGE_ANY_MOT, FEAT_ANYMO_OFFSET + 2, anymo2_val, anymo2_mask)
            if ok then log.info("exs_bmi270", "any_motion 特征已使能") end
        end
    end

    -- no_motion：NOMO_1 设置 duration/三轴选择，NOMO_2 设置 threshold/out_conf/enable
    if cfg.no_motion then
        if cfg.no_motion_duration_ms ~= nil then
            local dur = math.floor(cfg.no_motion_duration_ms / 20)
            if dur < 0 then dur = 0 end
            if dur > 0x1FFF then dur = 0x1FFF end
            write_feat_word(FEAT_PAGE_NO_MOT, FEAT_NOMO_OFFSET, dur, 0x1FFF)
        end

        -- NOMO_2：默认值 0x3090 的 enable 位(bit15)=0，必须显式 OR 上 EN_MASK 才能置 1！
        local nomo2_val = FEAT_NOMO_2_DEFAULT | FEAT_NOMO_2_EN_MASK   -- enable=1
        local nomo2_mask = FEAT_NOMO_2_EN_MASK
        if cfg.no_motion_thresh_mg ~= nil then
            local thr = math.floor(cfg.no_motion_thresh_mg / 0.488 + 0.5)
            if thr < 0 then thr = 0 end
            if thr > 0x7FF then thr = 0x7FF end
            nomo2_mask = nomo2_mask | 0x07FF
            nomo2_val = (nomo2_val & 0xF800) | (thr & 0x07FF)   -- 替换阈值，保留 out_conf/enable
            local ok = write_feat_word(FEAT_PAGE_NO_MOT, FEAT_NOMO_OFFSET + 2, nomo2_val, nomo2_mask)
            if ok then log.info("exs_bmi270", "no_motion 特征已使能（含自定义阈值）") end
        else
            local ok = write_feat_word(FEAT_PAGE_NO_MOT, FEAT_NOMO_OFFSET + 2, nomo2_val, nomo2_mask)
            if ok then log.info("exs_bmi270", "no_motion 特征已使能") end
        end
    end

    -- sig_motion：SIGMO_1 设置 block_size，SIGMO_2 设置 out_conf/enable
    if cfg.sig_motion then
        if cfg.sig_motion_block_ms ~= nil then
            -- block_size 以 20ms/点为单位，默认 0xFA=250点=5秒
            local bs = math.floor(cfg.sig_motion_block_ms / 20 + 0.5)
            if bs < 0 then bs = 0 end
            if bs > 0xFFFF then bs = 0xFFFF end
            write_feat_word(FEAT_PAGE_SIG_MOT, FEAT_SIGMO_OFFSET, bs, 0xFFFF)
        end

        -- SIGMO_2：enable=bit0，out_conf(bit[4:1]) 保持默认 0x1
        -- 注意：默认值 0x0002 的 enable 位(bit0)=0，必须显式 OR 上 EN_MASK 才能置 1！
        local sigmo2_val = FEAT_SIGMO_2_DEFAULT | FEAT_SIGMO_2_EN_MASK   -- enable=1
        local ok = write_feat_word(FEAT_PAGE_SIG_MOT, FEAT_SIGMO_OFFSET + 0x0A, sigmo2_val, FEAT_SIGMO_2_EN_MASK)
        if ok then log.info("exs_bmi270", "sig_motion 特征已使能") end
    end

    -- step：SC_26 配置 step detector/counter（页6 偏移 0x02）
    -- 数据手册 4.8.8：SC_26[9:0]=watermark_level、[10]=reset_counter、[11]=en_detector、[12]=en_counter
    -- 重要：watermark_level 默认 0 时 step counter 输出被禁用（SC_OUT 不更新），
    --       get_step_count() 恒为 0。必须设非零值（隐含 ×20 步因子）：
    --       watermark_level=1 → 每 20 步更新一次，=5 → 每 100 步更新一次
    -- 掩码只覆盖 watermark_level/en_detector/en_counter，保留 reset_counter 等其余位
    if cfg.step then
        local sc26_val = 0
        local sc26_mask = 0x1800   -- en_detector(bit11) + en_counter(bit12)
        sc26_val = sc26_val | FEAT_SC26_EN_DETECTOR   -- 使能 step detector（中断）
        if cfg.step_counter then
            sc26_val = sc26_val | FEAT_SC26_EN_COUNTER -- 使能 step counter（读数）
            -- watermark_level：步数每累计 N×20 步更新一次；默认 1（每 20 步）
            -- 用户可通过 cfg.step_watermark_steps 指定步数间隔（会向上取整到 20 的倍数）
            local wm = 1   -- 默认每 20 步更新一次
            if cfg.step_watermark_steps and cfg.step_watermark_steps > 0 then
                wm = math.max(1, math.floor((cfg.step_watermark_steps + 19) / 20))
            end
            if wm > 0x3FF then wm = 0x3FF end   -- 10 位上限，最大 0x3FF×20=20460 步
            sc26_val = sc26_val | (wm & 0x03FF)
            sc26_mask = sc26_mask | 0x03FF      -- 同时覆盖 watermark_level 位
        end
        local ok = write_feat_word(FEAT_PAGE_STEP, FEAT_SC26_OFFSET, sc26_val, sc26_mask)
        if ok then log.info("exs_bmi270", "step 特征已使能") end
    end
end

-- 将数据事件名映射为 INT_MAP_DATA 位掩码（data_ready/fifo_wm/fifo_ffull/error）
local function data_event_to_mask(evt)
    local m = 0
    if evt.data_ready then m = m | INT_MAP_DRDY end
    if evt.fifo_wm then m = m | INT_MAP_FWM end
    if evt.fifo_ffull then m = m | INT_MAP_FFULL end
    if evt.error then m = m | INT_MAP_ERR end
    return m
end

-- 配置单个中断引脚（INT1 或 INT2）的电气特性 + 中断映射
-- int_name: "int1"/"int2"; cfg: {int_gpio, lvl(可选), data_ready, any_motion, no_motion, sig_motion, step, cb}
-- 注意：特征中断（any_motion/no_motion/sig_motion/step）的 feature 使能由 enable_feature_ints 负责
--       （调用本函数前已执行），本函数只做引脚映射与 GPIO 注册。
--       仅 data_ready 等数据中断无需 feature 使能，开箱即用。
local function apply_int_pin(int_name, cfg)
    if not cfg or type(cfg) ~= "table" then return end
    local is_int1 = (int_name == "int1")
    local io_ctrl_reg = is_int1 and REG_INT1_IO_CTRL or REG_INT2_IO_CTRL
    local map_feat_reg = is_int1 and REG_INT1_MAP_FEAT or REG_INT2_MAP_FEAT

    -- 1. 读取当前引脚配置，设置输出使能 + 电平
    local io = rd8(io_ctrl_reg) or 0
    io = io | INT_IO_OUTPUT_EN    -- 使能中断输出
    io = io & ~INT_IO_INPUT_EN    -- 关闭输入模式
    local lvl = cfg.lvl or INT_LEVEL_ACTIVE_LOW  -- BMI270 默认低有效
    if lvl == INT_LEVEL_ACTIVE_LOW then
        io = io & ~INT_IO_LEVEL    -- 低有效
    else
        io = io | INT_IO_LEVEL     -- 高有效
    end
    wr8(io_ctrl_reg, io)

    -- 2. 特征中断映射（any_motion/no_motion/sig_motion/step）
    local feat_mask = feature_event_to_mask(cfg)
    if feat_mask ~= 0 then
        local cur_feat = rd8(map_feat_reg) or 0
        wr8(map_feat_reg, cur_feat | feat_mask)
    end

    -- 3. 数据中断映射（data_ready/fifo_wm/fifo_ffull/error）
    local data_mask = data_event_to_mask(cfg)
    if data_mask ~= 0 then
        local cur_data = rd8(REG_INT_MAP_DATA) or 0
        if is_int1 then
            wr8(REG_INT_MAP_DATA, cur_data | (data_mask & 0x0F))
        else
            wr8(REG_INT_MAP_DATA, cur_data | ((data_mask & 0x0F) << 4))
        end
    end

    -- 4. 锁存模式：默认脉冲（非锁存），edge 触发友好
    local latch = rd8(REG_INT_LATCH) or 0
    wr8(REG_INT_LATCH, latch & 0xFE)

    -- 5. 注册 GPIO 中断回调
    if cfg.int_gpio then
        local edge = (lvl == INT_LEVEL_ACTIVE_LOW) and gpio.FALLING or gpio.RISING
        -- 注意：中断回调运行在中断上下文，绝不能做 I2C 读取（会打断软件 I2C 位时序，
        -- 导致后续 get_data() 读出的数据错位乱跳）。回调只发消息/置标志，
        -- 数据读取与中断状态清除放到主任务协程（get_int_status/get_data）完成。
        gpio.setup(cfg.int_gpio, function()
            if cfg.topic then
                sys.publish(cfg.topic)   -- 发布中断消息，主任务 sys.waitUntil 等待
            elseif cfg.cb then
                cfg.cb()                  -- 仅通知用户（用户应在主任务里读数据）
            end
        end, gpio.PULLUP, edge)
        if is_int1 then
            g_int1_cb = cfg.cb; g_int1_gpio = cfg.int_gpio; g_int1_level = lvl
            g_int1_cfg = cfg
            log.info("exs_bmi270", string.format("INT1 已注册, int_gpio=%d", cfg.int_gpio))
        else
            g_int2_cb = cfg.cb; g_int2_gpio = cfg.int_gpio; g_int2_level = lvl
            g_int2_cfg = cfg
            log.info("exs_bmi270", string.format("INT2 已注册, int_gpio=%d", cfg.int_gpio))
        end
    end
end

-- 重新应用中断配置（软复位/量程切换等导致 FEATURES 与引脚映射被清空后调用）
-- 恢复特征使能 + INT1/INT2 引脚映射 + GPIO 中断注册
local function reapply_interrupts()
    if g_int1_cfg and type(g_int1_cfg) == "table" then
        enable_feature_ints(g_int1_cfg)
        apply_int_pin("int1", g_int1_cfg)
    end
    if g_int2_cfg and type(g_int2_cfg) == "table" then
        enable_feature_ints(g_int2_cfg)
        apply_int_pin("int2", g_int2_cfg)
    end
end

-- ==================== BMI270 微程序配置（8192 字节） ====================
-- 来源：Bosch BMI270_config.h（bmi270-main 参考工程）
-- 以 hex 字符串内嵌于本模块，避免外部 require 导致 package.loaded 内存驻留

local CONFIG_HEX = [[
C82E002E802E3DB1C82E002E802E9103802EBCB0802EA303C82E002E802E00B0
5030212E59F51030212E6AF5802E3B0300000000081901002200750000100010
D100B343802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1E05F000000000100000000000000000000009200
0000000000000000000000000000000008190000880000000000000005E0AA38
05E09030FA0096004B091100110002002D01D47B3B01DB7A04003F7BCD6CC304
8509C304ECE60C460100270019009600A00001000C00F03C0001010003000100
0E00000032000500EE060400C80000000400A805EE060004BC02B30085070000
000000000000000000000000000000000000B4000100B9000100980000000000
0000000001008000040000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000802E00C1FD2D
DE00EB00DA00000CFF0F0004C0005BF5C9011EF280003FFF19F458F566F564F5
C0F1F000E000CD01D301DB01FF7FFF01E40074F7F300FA00FF3FCA036C3856FE
44FDBC02F90600FC1202AE0158FA9AFD7705BB02960195017F01820189018701
88018A018C018F018D0192019101DD009F017E01DB00B601706926D39C071F05
9D000008BC0537FAA201AA01A101A801A001A805B401B401CE00D000FC00C501
FFFBB10000380030FDF5FCF5CD01A0005FFF0040FF0000806D0FEB007FFFC2F5
68F7B3F1670F5B0F610F800F58F75BF7830F8600720F850FC6F17F0F6CF700E0
00FFD1F5870F8A0FFF03F03F8B008E009000B9002DF5CAF5CB0120F200000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000003050982ED70E5032
982EFA030030F07F002E002ED02E002E018008A2FB2F982EBA03212E1900012E
EE0000B2072F012E190000B2032F01500352982E07CC012EDD0000B2272F052E
8A000552982EC7C1032EE90040B2F07F082F012E190000B2042F0030212EE900
982EB4B1012E180000B2102F0550982E4DC30550982E5AC7982EF9B4982E54B2
982E67B6982E17B21030212E7700012EEF0000B2042F982E7AB70030212EEF00
012ED40004AE0B2F012EDD0000B2072F0552982E8E0E00B2022F1030212E7D00
012E7D000090902EF102012ED70000B2042F982E2F0E0030212E7B00012E7B00
00B2122F012ED4000090022F982E1F0E092D982E810D012ED4000490022F5032
982EFA030030212E7B00012E7C0000B2902E0903012E7C000131010800B2042F
982E47CB1030212E77008130012E7C00010800B2612F032E8900012ED40098BC
98B805B20F58232F079009540030372F15410441DCBE44BEDCBA2C0161000F56
4A0F0C2FD14294B8C1421130052E6AF72CBD2FB980B20822982EC3B7212D6130
232ED400982EC3B70030212E5AF5182DE17F5030982EFA030F52075050427030
0D5442427E82E26F80B24242052F212ED4001030982EC3B7032D6030212ED400
012ED4000690182F012E76000B540752E07F982E7AC1E16F081A4030082F212E
D4002030982EAFB75032982EFA03052D982E380E0030212ED4000030212E7C00
182D012ED40003AA012F982E450E012ED4003F8003A2012F002E022D982E5B0E
3030982ECEB70030212E7D005032982EFA03012E770000B2242F982EF5CB032E
D5001154010ABC848386212EC901E0401352C4408240A8B9524243BE5342040A
5042E17FF0314140F26F25BD0808020AD07F982EA8CF06BCD16FE26F080A8042
982E58B70030212EEE00212E7700212EDD00802EF4011A242200802EEC011050
FB7F982EF3035750FB6F013071541142420EFC2FC02E0142F05F802E00C1FD2D
0100000000000000000000009A01340300000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
00002050E77FF67F06320F2E61F5FE09C0B3042F17302F2EEF002D2E61F5F66F
E76FE05FC82E2050E77FF67F46300F2EA4F1BE0980B3062F0D2ED40084AF022F
16302D2E7B0086302D2E60F5F66FE76FE05FC82E012E77F709BC0FB800B21050
FB7F10300B2F032E8A0096BC9FB840B2052F032E68F79EBC9FB840B2072F032E
7E004190012F982EDC03032C0030212E7E00FB6FF05FB82E2050E07FFB7F002E
2750982E3BC82950982EA7C80150982E55CCE16F2B50982EE0C9FB6F0030E05F
212E7E00B82E7350013057541142420EFC2FB82E212E59F51030C02E212E4AF1
9050F77FE67FD57FC47FB37FA17F907F827F7B7F982E35B700B2902E97B0032E
8F00072E9100052EB1003FBA9FB8012EB100A3BD4C0A052EB10004BEBFB9CB0A
4FBA22BD012EB300DC0A2FB9032EB8000ABE9A0ACFB99BBC012E97009FB8930A
0FBC910A0FB8900A252E1800052EC1F52EBD2EB9012E190031308A040090072F
012ED40004A2032F012E180000B20C2F19500552982E4DB7052E780080901030
012F212E7800252EDD00982E3EB700B202300130042F012E190000B2002F2130
012EEA00081A0E2F232EEA0033301B500B090140175646BE4B084C0A01420A80
15520142002E012E180000B21F2F032EC0F5F030480847AA7430072E7A006122
4B1A052F072E66F5BFBDBFB9C0900B2F1D562B30D242DB420104C24204BDFE80
8184232E7A0002420232252E62F5052ED6008184252ED6000231252E60F5052E
8A000B50900880B20B2F052ECAF5F03E9008252ECAF5052E59F5E03F9008252E
59F5906FA16FB36FC46FD56FE66FF76F7B6F826F705FC82EC050907FE57FD47F
C37FB17FA27F877FF67F7B7F002E012E60F5607F982E35B70230636F1552507F
627F5A2C02321A0900B3142F00B2032F092E180000910C2F437F982E97B71F50
028A02320430252E64F51552506F436F4443252E60F5D908C0B2362F982E3EB7
00B2062F012E190000B2022F506F00900A2F012E79000090192F1030212E7900
0030982EDC03132D012EC3F50CBC0FB81230100403B0262521500352982E4DB7
1030212EEE000230607F252E7900606F0090052F0030212EEA001550212E64F5
1552232E60F50232506F0090022F0330272E7800072E60F51A090091A32F1909
0091A02F906FA26FB16FC36FD46FE56F7B6FF66F876F405FC82EC050E77FF67F
26300F2E61F52F2E7C000F2E7C00BE09A27F807F80B3D57FC47FB37F917F7B7F
0B2F23501A251240427F74821240527F002E0040607F982E6AD68130012E7C00
010800B2422F032E8900012E890097BC06BC9FB80FB80090232ED80010300130
2A2F032ED40044B2052F47B200302D2F212E7C002B2D032EFDF59EBC9FB84090
142F032EFCF599BC9FB840900E2F032E49F125544A084090082F982E35B700B2
1030032F5030212ED400102D982EAFB70030212E7C000A2D052E69F72DBD2FB9
80B2012F212E7D00232E7C00E031212E61F5F66FE76F806FA26FB36FC46FD56F
7B6F916F405FC82E60510A253688F47FEB7F0032315232301330982E15CB0A25
3384D27F433005502D52982E95C1D26F2752982ED7C72A25B086C07FD37FAF84
2950F16F982E4DC82A25AE8AAA88F26E2B50C16FD36FF47F982EB6C8E06E00B2
322F33548386F16FC37F04303030F47FD07FB27FE330C56F5640454128080314
0EB408BC8240100A2F542605917F4428A37F982ED9C008B933305309C16FD36F
F46F831747406C15B26FBE09750B90424542510E32BC0289A16F7E86F47FD07F
B27F0430916FD62FEB6FA05EB82E032E97001BBC60509FBC0CB8F07F40B2EB7F
2B2F032E7F004140012EC800011A112F3758232EC8001041A07F38810141D07F
B17F982E64CFD06F0780A16F1142002EB16F01421130012EFC0000A80330CB22
4A25012E7F003C8935520554982EC4CEC16FF06F982E95CF042D0130F06F982E
95CFEB6FA05FB82E032EB3000232F030033130508A080808CB08E07F80B2F37F
DB7F252F032ECA004190042F0130232ECA00982E3F03C0B2052F032EDA000030
4104232EDA00982E92B21025F06F00B2052F012EDA0002301004212EDA0040B2
012F232EC801DB6FE06FD05F802E95CF0130E06F982E95CF1130232ECA00DB6F
D05FB82ED0500A2533845550D27FE27F038CC07FBB7F0030055A39545141A57F
967F807F982ED9C00530F57F2025916F3B583D5C3B56982E67CCC16FD56F5240
5043C17FD57F1025982EFEC91025982E74C0866F3028926F828CA56F6F52690E
3954DB2F19A01530032F0030212E81010A2D012E810105284236212E8101020E
012F982EF303575012300140982EFEC9516F0B5C8E0E3B6F57580230212E9501
456F2A8DD27FCB7F132F02303F50D27FA80E0E2FC06F535402005154420E1030
59520230012F002E032D504242421230D27F80B2032F0030212E8001122D012E
C9000280052E8001113091280040252E8001100E052F012E7F010190012F982E
F303002EA0410190A67F902EE3B4012E950100A8902EE3B45B549580824080B2
02402D8C3F52967F902EC2B3290E762F012EC900004081284552B330982E0FCA
5D54807F002EA140727F82808240607F982EFEC91025982E74C0626F05308740
C0910430052F052E830180B21430002F0430052EC900736F8140E2406904110F
E1401630FE29CB40022F836F830F222F4756130F1230772F4954420E1230732F
00910A2F012E8B0119A802306C2F6350002E17420542682C12300B25080F5030
022F212E8301032D4030212E83012B2E85015A2C123000912B25042F63500230
1742172C0242982EFEC91025982E74C0052EC90081845B308240372E8301020E
072F5F52403062404140910E012F212E830105302B2E85011230362C16301525
817F982EFEC91025982E74C019A21630152F052E9701806F820E052F012E8601
0628212E86010B2D032E87015F544E289142002E8240900E012F212E88010230
132C0530C06F081CA80F163005305B50092F02802D2E820105420580002E0242
3E80002E06420230906F3E88014004414C280142078010252440004000A8F522
232944427A827E884340044100ABF523DF284342D9A0142F0090022FD26F81B2
052F6354062890428542092C02305B500380292E7E012B2E8201054212302B2E
83014582002E40407A8202A0082F63503B30154205423780372E7E0105421230
012EC900028C404084417A8C040F032F012E8B0119A4042F2B2E8201982EF303
123081906152082F654265424380398482880542454285420543002E80410090
902EE1B46554C16F804000B243586950442F555CB7878C0F0D2E9601C440362F
41568B0E2A2F0B52A10E0A2F052E8F011425982EFEC94B54020F695005306554
152F032E8E014D5C8E0F3A2F052E8F01982EFEC94F54820F053069506554302F
6D521530428C454204302B2C84436B52428C002E85431530242C45428E0F202F
0D2E8E01B10E1C2F232E8E011A2D0E0E172FA10F152F232E8D01132D982E74C0
4354C20E0A2F655004800B3006820B42798041401230252E8C01014205306950
655484824384BE8C8440864126299442BE8ED57F19A143400B2E8C018440C741
5D29272945428442C27F012FC0B31D2F052E940199A0012F80B3132F80B3182F
C0B3162F12400140927F982E74C0926F100F2030032F1030212E7E010A2D212E
7E01072D2030212E7E01032D1030212E7E01C26F012EC900BC84028082400040
900ED56F022F1530982EF30341910530072F67503D802B2E8F0105420480002E
0542022C00300030A26F988A864080A7052F982EF303C030212E950106251A25
E26F768296405643510EFB2FBB6F305FB82E012EB8000131410840B22050F230
0208FB7F0130102F052ECC008190E07F032F232ECC00982E55B6982E1DB51025
FB6FE06FE05F802E95CF982E95CF1030212ECC00FB6FE05FB82E00510558EB7F
2A2589526F5A895013410640B3011642CB160640F3021342650EF52F05401430
2C29044208A10030902E52B6B388B08AB684A47FC47FB57FD57F927F73300430
554042408A17F3086B01900253B84B82ADBE717F450A0954847F982ED9C0A36F
7B54D042A37FF27F607F2025716F755A7758795C7556982E67CCB16F626F5042
B17FB3301025982E0FCA846F2029716F926FA56F76826A0E73300030D02FD26F
D17FB47F982E2BB715BD0BB8020AC26FC07F982E2BB715BD0BB8420AC06F0817
41188916E118D018A17F27251625982E79C08B54907FB330824080900D2F7D52
926F982E0FCAB26F900E062F8B501430426F516F144212420142002E316F982E
74C0416F807F982E74C0826F10044352010F052ECB0000300430212F516F4358
8C0E04301C2F8588416F04418C0F0430162F8488002E044104058C0E04300F2F
8288316F044104058C0E0430082F8388002E04418C0F0430022F212EAD011430
0091142F032EA10141900E2F032EAD0114304C28232EAD0146A0062F81848D52
48828240212EA10142425C2C0230052EAA0180B20230552F032EA901926FB330
982E0FCAB26F900F003002304A2FA26F875291008552510E022F002E432C0230
C26F7F52910E02303C2F516F8154982EFEC91025B3302125982E0FCA326FC07F
B3301225982E0FCA426FB07FB3301225982E0FCAB26F90288352982EFEC9C26F
900F003002301D2F052EA10180B212300F2F426F032EAB01910E0230122F526F
032EAC01910F02300C2F212EAA010A2C1230032ECB008D580889414011430043
252EA101D46F8F5200433A89002E10431043610EFB2F032EA001111A022F0225
212EA001EB6F005FB82E915210300230955652424B0EFC2F8D54888293568042
5342404242868354C02EC242002EA3520051524047401A25012E97008FBE7286
FB7F0B307CBFA5501008DFBA7088F8BFCB42D37F6CBBFCBBC50A907F1B7F0B43
C0B2E57FB77FA67FC47F902E1CB7072ED200C0B20B2F9752012ECD00827F982E
BBCC0B30372ED200826F906F1A2500B28B7F142FA6BD25BDB6B92FB980B2D4B0
0C2F99549B560B300B2EB100A1589B42DB426C092B2EB1008B42CB42867F7384
A756C30839520550727F637F982EC2C0E16F626FD10A012ECD00D56FC46F726F
97529D5C982E06CD236F906F9952C0B204BD5440AFB94540E17F0230062FC0B2
0230032F9B5C12309443854303BF6FBB80B3202F066F2601166F6E034542C090
292ECE009B52142F9B5C002E93418641E304AE0780AB042F80910A2F866F730F
072F836FC0B2042F544245421230042C1130022C1130113002BC0FB8D27F00B2
0A2F012EFC00052EC701101A022F212EC701032D022C01300130B06F982E95CF
D16FA06F982E95CFE26F9F52012ECE00824050420C2C42421130232ED2000130
B06F982E95CFA06F0130982E95CF002EFB6F005FB82E83860130003094402418
0600530E4F02F92FB82EA952002E604041400DBC98BCC02E010A0FB8AB52533C
524040404B00821626B901B84140100897B80108C02E11300108438625400440
D8BE2C0B2211544203804B0EF62FB82E9F501050AD52052ED300FB7F002E1340
9342410EFB2F982EA5B7982E87CF012ED90000B2FB6F0B2F012E69F7B13F0108
0130F05F232ED900212E69F7802E7AB7F05FB82E012EC0F8032EFCF51554AF56
82080B2E69F7CB0AB1588090DDBE4C085FB959228090072F0334C308F23A0A08
0235C0904A0A4822C02E232EFCF51050FB7F982E56C7982E49C31030FB6FF05F
212ECC00212ECA00B82E032ED30016B802344A0C212E2DF5C02E232ED30003BC
212ED500032ED50040B21030212E77000130052F052ED8008090012F232E6FF5
C02E212ED90011308108012E6AF7713F23BD0108020AC02E212E6AF730250030
212E5AF51050212E7B00212E7C00FB7F982EC3B74030212ED400FB6FF05F0325
802EAFB7802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
012E5DF708BC80AC0EBB022F003041048206C0A40030112F40A9032F40910D2F
00A70B2F80B3B358022F90A12613202380901030012FCC0E002F0030B82EB550
180808BC88B60D17C6BD56BCB758DABA04011D0A1050053032254503FB7FF630
2125982E37CA16B59ABC06B880A8410A0E2F8090022F2D50480F092FBFA0042F
BF90062FB754CA0F032F002E022CB7522D52F233982ED9C0FB6FF137C02E0108
F05FBF56B954D040C4400B2EFDF3BF529042944295420530C1500F8806400441
9642C54248BE73300D2ED8004FBA8442034281B3022F2B2E6FF5062D052E77F7
BD569308252E77F7BB54252EC2F5072EFDF34230B433DA0A4C00272EFDF34340
D43FDC084342002E002E43402430DC0A43420480032EFDF34A0A232EFDF36134
C02E0142002E60501A257A86E07FF37F0325C3524184DB7F3330982E16C21A25
7D82F06FE26F322516409440260185408E17C4426E039542410EF42FDB6FA05F
B82EB051FB7F982EE80D5A25982E0F0ECB583287C47F65896B8DC55A657FE17F
837FA67F747FD07FB67F947F1730C752C954517F002E856F427F002E51414581
424113403B8A00404B04D006C0AC857F022F02305104D306418405305D02C916
DF08D3008D02AFBCB1B9590A656F1143A1B4524153410143347F657F2631E56F
D46F982E37CA326F756F83404241237F127FF63040255125982E37CA146F2005
706F256F6907A26F316F0B3004429B428B425542327F40A9C36F717F0230D040
C37F032F4091152F00A7132F00A4112F84BD982E79CA556FB75454418200F33F
4541CB02F630982E37CA356FA46F4143032C0043A46F356F1730426F516F9340
42820041C3000343517F002E944041414C02C46FD156630E746F5143A57F8A2F
092ED80001B3212FCB58906F1341B66FE47F002E9141144092411540172E6FF5
B67FD07FCB7F982E000C0715C26F140B292E6FF5C3A3C18FE46FD06FE62F1430
052E6FF5140B292E6FF5182DCD560432B56F1C0151415241C340B57FE47F982E
1F0CE46F218700430432CF545A0EEF2F1554092E77F7220B292E77F7FB6F505E
B82E1050012ED40000B2FB7F512F01B2482F02B2422F0390562FD75279804240
818400404242982E930CD954D750A14098BD82403E82DA0A44408B16E3005342
002E43409A025242002E414015544A0E3A2F3A8200304140212E850F40B20A2F
982EB10C982E450E982E5B0EFB6FF05F0030802ECEB7DD52D35442424F847330
DB5283421B306B422330272ED700372ED400212ED6007A84172C42423030212E
D400122D21300030232ED400212E7BF70B2D1730982E510CD5500C8272302F2E
D400252E7BF74042002EFB6FF05FB82E70500A253986FB7FE1326230982EC2C4
B556A56FAB08916F4B08DF56C46F23094DBA93BC8C0BD16F0B09CB52E15E5642
AF094DBA23BD940AE56F68BBEB08BDB963BEFB6F5242E30AC02E4342905FD150
032E25F3134000409BBC9BB408BDB8B998BCDA0A08B68916C02E190062021050
FB7F982E810D012ED40031300804FB6F0130F05F232ED600212ED700B82E012E
D700032ED600480E012F802E1F0EB82EE350213401428230C132252E62F50100
223001404A0A0142B82EE354F03B8340D808E5528342003083305042C432272E
64F5940050424042D33F84407D82E30840428342B82EDD52003040427C86B952
092E700FBF54C442D3865440554094428542212ED7004240252EFDF3C0427E82
052E7D0080B2142F052E890027BD2FB98090022F212E6FF50C2D072E710F1430
1C09052E77F7BD5647BE9308940A252E77F7E75450424A0EFC2FB82E50500230
4386E550FB7FE37FD27FC07FB17F002E414000404804982E74C01EAAD36F1430
B16FE322C06F5240E46F4C0E1242D37FEB2F032E860F40901130032F232E860F
022C0030D06FFB6FB05FB82E4050F17F0A253C86EB7F41332230982EC2C4D36F
F430DC094758C26F9409EB586ABBDC08B4B9B1BDE95A950821BDF6BF770B51BE
F16FEB6F52425442C02E4342C05F5050F55031301142FB7F7B300B4211300280
233301420300072E8003052ED3002352E27FD37FC07F982EB60ED16F080A1A25
7B86D07F01331230982EC2C4D16F080A00B20D2FE36F012E80035130C786232E
21F208BCC042982EA5B7002E002ED02EB06F0BB8032E1B00081AB07F7030042F
212E21F2002E002ED02E982E6DC0982E5DC0ED50982E44CBEF50982E46C3F150
982E53C73550982E64CF1030982EDC032026C06F02311242AB330B4237800130
0142F337F752FB504440A20A42428B31092E5EF7F954E30883421B4223334B00
BC840B40333083420B42E07FD17F982E58B7D16F803040420330E06FF3540430
002E002E0189620EFA2F43421130FB6FC02E0142B05FC14A00006D570000778E
0000E0FFFFFFD3FFFFFFE5FFFFFFEEE1FFFF7C13000046E6FFFF000000000000
0000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1802E00C1
]]

-- 加载 BMI270 微程序到 INIT_DATA
-- INIT_DATA (0x5E) 是 FIFO 写端口：INIT_CTRL=0 期间，写入地址由 INIT_ADDR_0/1 指定，
-- 单事务内自动递增、跨事务不自增。因此分块写：每块前设 INIT_ADDR_0/1（字地址 offset/2），
-- 再 burst 写 INIT_DATA。Bosch 官方 read_write_len 默认 32/64，此处用 128 字节小分块。
-- SPI 和 I2C 统一走此方案（128 字节远小于 LuatOS 4096 单次上限，无截断风险）。
local function load_config_file()
    local cfg_bin = string.fromHex(CONFIG_HEX)
    if #cfg_bin ~= 8192 then
        log.error("exs_bmi270", string.format("配置文件长度异常：%d 字节（应为 8192）", #cfg_bin))
        return false
    end
    local chunk_size = 128
    local offset = 0
    while offset < 8192 do
        local chunk = cfg_bin:sub(offset + 1, offset + chunk_size)
        local word_addr = offset / 2
        if not wr8(REG_INIT_ADDR_0, word_addr & 0x0F) then
            log.error("exs_bmi270", string.format("INIT_ADDR_0 写入失败 offset=%d", offset))
            return false
        end
        if not wr8(REG_INIT_ADDR_1, (word_addr >> 4) & 0xFF) then
            log.error("exs_bmi270", string.format("INIT_ADDR_1 写入失败 offset=%d", offset))
            return false
        end
        local ok
        if g_iface == "I2C" then
            ok = i2c.send(g_i2c_bus, g_dev_addr, string.char(REG_INIT_DATA) .. chunk)
        else
            -- SPI 用 send（纯发送，无 recv 缓冲）；校验返回字节数 = 1(地址) + 块长
            local sent = g_spi_dev:send(string.char(REG_INIT_DATA & 0x7F) .. chunk)
            ok = (sent ~= nil) and (tonumber(sent) or 0) >= (#chunk + 1)
        end
        if not ok then
            log.error("exs_bmi270", string.format("配置数据写入失败 offset=%d", offset))
            return false
        end
        -- 数据手册 Quick Start 要求：配置加载期间两次写之间至少 450µs 间隔。
        -- 参考工程是软件 SPI（位操作、速度低），天然满足；硬件 SPI 10MHz 下 128B 块仅 ~100µs，
        -- 必须主动补延时。I2C 400kHz 下每块 ~2.6ms 天然满足，无需额外延时。
        if g_iface == "SPI" then
            sys.wait(1)  -- 1ms ≥ 450µs，64 块共约 64ms，可接受
        end
        offset = offset + #chunk
    end
    log.info("exs_bmi270", "微程序已分块写入（8192 字节，每块 128）")
    return true
end

-- 执行 BMI270 初始化序列
-- 流程：关闭省电 → 使能配置加载 → 写入微程序 → 禁止加载 → 等待 → 校验状态 → 上电使能 → 配置量程/采样率
local function init_sequence(acc_range_str, gyro_range_str, acc_odr, gyro_odr)
    -- 关闭省电模式，否则微程序无法加载（PWR_CONF bit0=adv_power_save）
    if not wr8(REG_PWR_CONF, 0x00) then return false end
    sys.wait(2)  -- 等待省电模式关闭生效（参考工程 2ms）

    -- 使能配置加载（INIT_CTRL=0）
    if not wr8(REG_INIT_CTRL, 0x00) then return false end

    -- 写入 8192 字节微程序
    if not load_config_file() then
        log.error("exs_bmi270", "微程序加载失败")
        return false
    end

    -- 禁止配置加载（INIT_CTRL=1）
    if not wr8(REG_INIT_CTRL, 0x01) then return false end

    sys.wait(CONFIG_LOAD_WAIT_MS)  -- 等待微程序生效，100ms

    -- 校验加载结果：INTERNAL_STATUS bit[3:0] 应为 0x01 (init_ok)
    -- 实测 0x02=init_err 是真实失败（ACC/GYR 全零、STATUS=0x10 无 drdy），非参考工程可容忍的状态
    -- 0x21 首次读可能返回陈旧值，读两次取第二次
    local st = rd8(REG_INTERNAL_STATUS)  -- 第一次读触发状态更新
    sys.wait(5)
    st = rd8(REG_INTERNAL_STATUS)        -- 第二次读取真实值
    if not st or (st & 0x0F) ~= 0x01 then
        log.error("exs_bmi270", string.format("配置加载失败：INTERNAL_STATUS=0x%02X（期望 bit[3:0]=0x01）", st or 0))
        return false
    end

    -- 启动传感器：PWR_CTRL = 0x0E (acc_en=bit2, gyr_en=bit1, temp_en=bit3, aux_en=bit0=0)
    -- 数据手册 Quick Start 第 4.7 节：初始化后必须写 PWR_CTRL 才能开始采样
    if not wr8(REG_PWR_CTRL, PWR_CTRL_EN) then return false end

    -- 非易失配置：I2C 模式写 0，SPI 模式写 1（NV_CONF bit0）
    -- 先读回当前值，仅在不匹配时才写入（NV_CONF 为 NVM 寄存器，写入次数有限）
    local nv_val = g_iface == "SPI" and 0x01 or 0x00
    local nv_cur = rd8(REG_NV_CONF)
    if nv_cur and (nv_cur & 0x01) ~= nv_val then
        if not wr8(REG_NV_CONF, nv_val) then return false end
    end

    -- 接口配置：bit7=0 四线 SPI / I2C
    if not wr8(REG_IF_CONF, 0x00) then return false end

    -- 配置陀螺仪量程（GYR_RANGE bit[2:0]）
    local gyro_reg, gyro_sens = gyro_range_to_params(gyro_range_str)
    if not wr8(REG_GYR_RANGE, gyro_reg) then return false end

    -- 配置陀螺仪采样率（GYR_CONF：ODR bit[3:0] + BWP=normal(0x20) + filter_perf(0x80)）
    -- 参考 bmi270-main 工程：gyro_rate|0x20|0x80
    if not wr8(REG_GYR_CONF, gyro_odr_to_reg(gyro_odr) | 0x20 | 0x80) then return false end

    -- 配置加速度量程（ACC_RANGE bit[1:0]）
    local acc_reg, acc_sens = acc_range_to_params(acc_range_str)
    if not wr8(REG_ACC_RANGE, acc_reg) then return false end

    -- 配置加速度采样率（ACC_CONF：ODR bit[3:0] + BWP=normal(0x20) + filter_perf(0x80)）
    -- 参考 bmi270-main 工程：acc_rate|0x20|0x80
    if not wr8(REG_ACC_CONF, acc_odr_to_reg(acc_odr) | 0x20 | 0x80) then return false end

    sys.wait(CONFIG_APPLY_WAIT_MS)  -- 等待量程/采样率配置生效，50ms

    -- [调试] 回读关键寄存器，验证初始化是否真正生效
    local pwr_ctrl_rb = rd8(REG_PWR_CTRL)
    local status_reg = rd8(0x03)  -- STATUS: bit7=drdy_acc, bit6=drdy_gyr
    local acc_range_rb = rd8(REG_ACC_RANGE)
    local gyr_range_rb = rd8(REG_GYR_RANGE)
    log.info("exs_bmi270", string.format("init verify: PWR_CTRL=0x%02X STATUS=0x%02X ACC_RANGE=0x%02X GYR_RANGE=0x%02X",
        pwr_ctrl_rb or 0xFF, status_reg or 0xFF, acc_range_rb or 0xFF, gyr_range_rb or 0xFF))

    -- 等待传感器真正开始产出数据（STATUS bit7=drdy_acc, bit6=drdy_gyr）
    -- 最长等待 300ms，避免上电初期传感器尚未稳定导致读到的数据全零
    local drdy_ok = false
    for i = 1, 15 do
        local st = rd8(0x03)
        if st and (st & 0xC0) == 0xC0 then  -- bit7+bit6 同时置位
            drdy_ok = true
            break
        end
        sys.wait(20)
    end
    if not drdy_ok then
        log.warn("exs_bmi270", "等待数据就绪超时，传感器可能未稳定")
    end

    -- 更新内部记录的量程/采样率状态
    g_acc_range_reg, g_acc_sens = acc_reg, acc_sens
    g_gyro_range_reg, g_gyro_sens = gyro_reg, gyro_sens
    g_acc_odr_reg = acc_odr_to_reg(acc_odr)
    g_gyro_odr_reg = gyro_odr_to_reg(gyro_odr)

    -- 重置姿态解算状态：初始四元数用加速度计推算的真实静态姿态
    -- （替代硬编码水平姿态，避免竖直/倾斜安装时的 90° 收敛爬坡）
    g_int_x, g_int_y, g_int_z = 0.0, 0.0, 0.0
    g_last_yaw, g_unwrapped_yaw = 0.0, 0.0
    g_yaw_first = true
    g_last_time = 0.0

    -- 读取一次加速度，构造初始四元数
    -- 注意：此处不能调用 read_raw_data（它在 init_sequence 之后定义），直接用 rd_multi
    local acc0 = rd_multi(REG_ACC_X_LSB, 6)
    if acc0 and #acc0 >= 6 then
        init_quaternion_from_accel(
            to_int16(acc0:byte(1), acc0:byte(2)) / g_acc_sens,
            to_int16(acc0:byte(3), acc0:byte(4)) / g_acc_sens,
            to_int16(acc0:byte(5), acc0:byte(6)) / g_acc_sens)
    else
        g_q0, g_q1, g_q2, g_q3 = 1.0, 0.0, 0.0, 0.0
    end

    return true
end

-- 读取传感器原始数据（加速度 6 字节 + 陀螺仪 6 字节 + 温度 2 字节）
-- 使用 rd_multi 批量读取，3 次总线事务完成全部数据采集
local function read_raw_data()
    local acc_data = rd_multi(REG_ACC_X_LSB, 6)
    if not acc_data or #acc_data < 6 then return nil end
    local gyro_data = rd_multi(REG_GYRO_X_LSB, 6)
    if not gyro_data or #gyro_data < 6 then return nil end
    local temp_data = rd_multi(REG_TEMP_LSB, 2)
    if not temp_data or #temp_data < 2 then return nil end

    -- [调试] 首次调用时打印原始字节，用于排查数据全零问题
    if not g_raw_debug_logged then
        g_raw_debug_logged = true
        local hex_parts = {}
        for i = 1, #acc_data do hex_parts[#hex_parts + 1] = string.format("%02X", acc_data:byte(i)) end
        log.info("exs_bmi270", "ACC_RAW: " .. table.concat(hex_parts, " "))
        hex_parts = {}
        for i = 1, #gyro_data do hex_parts[#hex_parts + 1] = string.format("%02X", gyro_data:byte(i)) end
        log.info("exs_bmi270", "GYR_RAW: " .. table.concat(hex_parts, " "))
        hex_parts = {}
        for i = 1, #temp_data do hex_parts[#hex_parts + 1] = string.format("%02X", temp_data:byte(i)) end
        log.info("exs_bmi270", "TMP_RAW: " .. table.concat(hex_parts, " "))
    end

    local raw = {}
    raw.ax = to_int16(acc_data:byte(1), acc_data:byte(2))
    raw.ay = to_int16(acc_data:byte(3), acc_data:byte(4))
    raw.az = to_int16(acc_data:byte(5), acc_data:byte(6))
    raw.gx = to_int16(gyro_data:byte(1), gyro_data:byte(2))
    raw.gy = to_int16(gyro_data:byte(3), gyro_data:byte(4))
    raw.gz = to_int16(gyro_data:byte(5), gyro_data:byte(6))
    raw.temp = to_int16(temp_data:byte(1), temp_data:byte(2))
    return raw
end

-- ==================== Mahony 姿态解算 ====================

-- Mahony 互补滤波单步更新（移植自 bmi270-main 工程 BMI270.c + ESP32 自适应增益版）
-- 输入：ax/ay/az 单位 g；gx/gy/gz 单位 rad/s；dt 积分步长（秒）
-- 算法要点：
--   1) 加速度合矢量模长接近 1g 时信任加速度计（Kp=1.6/Ki=0.02），运动时减小修正（Kp=0.4/Ki=0.001）
--   2) 叉积误差 + 积分限幅（±0.5）+ 比例/积分校正后更新四元数
--   3) 四元数归一化防止累积漂移
local function mahony_update(ax, ay, az, gx, gy, gz, dt)
    local acc_mag = ax * ax + ay * ay + az * az

    local kp, ki
    if acc_mag < 0.9 or acc_mag > 1.1 then
        -- 运动/震动剧烈，不信任加速度计，减小修正系数
        kp, ki = 0.4, 0.001
    else
        -- 接近静止，信任加速度计，正常大增益修正
        kp, ki = 1.6, 0.02
    end

    if acc_mag > 0.01 then
        -- 加速度归一化
        local recip_norm = 1.0 / math.sqrt(acc_mag)
        ax, ay, az = ax * recip_norm, ay * recip_norm, az * recip_norm

        -- 由当前四元数估计的重力方向（参考坐标系）
        local vx = 2.0 * (g_q1 * g_q3 - g_q0 * g_q2)
        local vy = 2.0 * (g_q0 * g_q1 + g_q2 * g_q3)
        local vz = g_q0 * g_q0 - g_q1 * g_q1 - g_q2 * g_q2 + g_q3 * g_q3

        -- 加速度测量与估计的叉积误差
        local ex = ay * vz - az * vy
        local ey = az * vx - ax * vz
        local ez = ax * vy - ay * vx

        -- 积分项（带 ±0.5 限幅）
        if ki > 0.0 then
            g_int_x = g_int_x + ex * dt
            g_int_y = g_int_y + ey * dt
            g_int_z = g_int_z + ez * dt
            if g_int_x > 0.5 then g_int_x = 0.5 elseif g_int_x < -0.5 then g_int_x = -0.5 end
            if g_int_y > 0.5 then g_int_y = 0.5 elseif g_int_y < -0.5 then g_int_y = -0.5 end
            if g_int_z > 0.5 then g_int_z = 0.5 elseif g_int_z < -0.5 then g_int_z = -0.5 end
            gx = gx + ki * g_int_x
            gy = gy + ki * g_int_y
            gz = gz + ki * g_int_z
        end

        -- 比例项校正
        gx = gx + kp * ex
        gy = gy + kp * ey
        gz = gz + kp * ez
    end

    -- 四元数微分方程更新
    local qd0 = 0.5 * (-g_q1 * gx - g_q2 * gy - g_q3 * gz)
    local qd1 = 0.5 * (g_q0 * gx + g_q2 * gz - g_q3 * gy)
    local qd2 = 0.5 * (g_q0 * gy - g_q1 * gz + g_q3 * gx)
    local qd3 = 0.5 * (g_q0 * gz + g_q1 * gy - g_q2 * gx)
    g_q0 = g_q0 + qd0 * dt
    g_q1 = g_q1 + qd1 * dt
    g_q2 = g_q2 + qd2 * dt
    g_q3 = g_q3 + qd3 * dt

    -- 四元数归一化
    local norm = 1.0 / math.sqrt(g_q0 * g_q0 + g_q1 * g_q1 + g_q2 * g_q2 + g_q3 * g_q3)
    g_q0 = g_q0 * norm
    g_q1 = g_q1 * norm
    g_q2 = g_q2 * norm
    g_q3 = g_q3 * norm
end

-- 四元数 → 欧拉角（roll/pitch/yaw，单位 °）
-- roll: 横滚角；pitch: 俯仰角；yaw: 偏航角（原始值 -180°~180°）
local function quat_to_euler()
    local roll = math.atan2(2.0 * (g_q0 * g_q1 + g_q2 * g_q3), 1.0 - 2.0 * (g_q1 * g_q1 + g_q2 * g_q2)) * 57.29578
    local pitch = math.asin(2.0 * (g_q0 * g_q2 - g_q3 * g_q1)) * 57.29578
    local yaw = math.atan2(2.0 * (g_q0 * g_q3 + g_q1 * g_q2), 1.0 - 2.0 * (g_q2 * g_q2 + g_q3 * g_q3)) * 57.29578
    return roll, pitch, yaw
end

-- 对 yaw 做无限叠加展开（避免 ±180° 跳变，可累计多圈）
local function unwrap_yaw(current_yaw)
    if g_yaw_first then
        g_unwrapped_yaw = current_yaw
        g_last_yaw = current_yaw
        g_yaw_first = false
    else
        local diff = current_yaw - g_last_yaw
        if diff > 180.0 then
            diff = diff - 360.0
        elseif diff < -180.0 then
            diff = diff + 360.0
        end
        g_unwrapped_yaw = g_unwrapped_yaw + diff
        g_last_yaw = current_yaw
    end
    return g_unwrapped_yaw
end

-- ==================== 对外 API ====================

--[[
初始化 BMI270 六轴惯性传感器

支持 I2C 与 SPI 两种接口。I2C 模式下可指定 scl/sda（软件 I2C）
或 i2c_id（硬件 I2C）；SPI 模式下需指定 spi_id 与 cs 引脚。

初始化流程：芯片 ID 校验 → 关闭省电 → 加载 8192 字节微程序 →
校验加载状态 → 上电使能 → 配置量程与采样率。

@api exs_bmi270.setup(model, config)
@string model 通信模式："I2C" 或 "SPI"
@table config 配置参数
  scl/sda   - 软件 I2C 引脚（I2C 模式与 i2c_id 二选一）
  i2c_id    - 硬件 I2C 总线 ID（I2C 模式与 scl/sda 二选一）
  addr      - I2C 设备地址（可选）。不传时自动探测 0x68/0x69（SDO 引脚决定），chip id 校验命中即锁定
  spi_id    - SPI 总线 ID（SPI 模式必填）
  cs        - SPI 片选引脚（SPI 模式必填）
  speed     - SPI 速率，默认 1MHz
  acc_range - 加速度量程 "2g"/"4g"/"8g"/"16g"，默认 "4g"
  gyro_range- 陀螺仪量程 "125"/"250"/"500"/"1000"/"2000"，默认 "500"
  acc_odr   - 加速度采样率 25~1600Hz，默认 200
  gyro_odr  - 陀螺仪采样率 25~3200Hz，默认 200
@return boolean
  含义说明：初始化是否成功
  数据类型：boolean
  注意事项：需在 sys.taskInit 协程中调用（内部含 sys.wait）
]]
function exs_bmi270.setup(model, config)
    if type(model) ~= "string" or type(config) ~= "table" then
        log.error("exs_bmi270.setup 参数错误")
        return false
    end

    -- 按接口初始化通信
    if model == "I2C" then
        if config.scl and config.sda then
            g_scl_pin, g_sda_pin = config.scl, config.sda
            if config.i2c_id then
                if i2c.setup(config.i2c_id, i2c.FAST) == 0 then
                    log.error("exs_bmi270.setup I2C 初始化失败")
                    return false
                end
                g_i2c_bus = config.i2c_id
                g_i2c_speed = i2c.FAST
                g_is_soft = false
            else
                g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
                if not g_i2c_bus then
                    log.error("exs_bmi270.setup 软件 I2C 初始化失败")
                    return false
                end
                g_is_soft = true
            end
        else
            local i2c_id = config.i2c_id or 0
            if i2c.setup(i2c_id, i2c.FAST) == 0 then
                log.error("exs_bmi270.setup I2C 初始化失败")
                return false
            end
            g_i2c_bus = i2c_id
            g_i2c_speed = i2c.FAST
            g_is_soft = false
            g_scl_pin, g_sda_pin = nil, nil
        end
        g_iface = "I2C"
        -- 未传 addr 时先取默认 0x68，下方 chip id 校验阶段自动探测 0x68/0x69 锁定
        g_dev_addr = config.addr or 0x68
    elseif model == "SPI" then
        local spi_id = config.spi_id
        local cs = config.cs
        if not spi_id or not cs then
            log.error("exs_bmi270.setup SPI 模式缺少 spi_id/cs 参数")
            return false
        end
        local speed = config.speed or 1000000
        -- BMI270 支持 SPI Mode 0/3；参考工程使用 Mode 3，此处统一用 Mode 3
        -- （CPHA=1, CPOL=1，与 bmi270-main 的 _MySPI_.h #define SPI_MODE 3 一致）
        g_spi_dev = spi.deviceSetup(spi_id, cs, 1, 1, 8, speed)
        if not g_spi_dev then
            log.error("exs_bmi270.setup SPI 初始化失败")
            return false
        end
        g_iface = "SPI"
        -- BMI270 上电时 CSB 为低即进入 SPI 模式，首次 SPI 读事务即有效。
        -- 读时序（地址+2 dummy，数据在第3字节）已由 rd8 正确实现，
        -- 此处无需额外的接口切换读。
    else
        log.error("exs_bmi270.setup 不支持的模式：", model)
        return false
    end

    -- 芯片 ID 校验：失败必须 return false
    -- I2C 多地址自动探测（0x68/0x69，由 SDO 引脚决定）：
    --   未传 config.addr 时逐个地址读 chip id，命中即锁定 g_dev_addr；SPI 模式只读一次
    local id = nil
    if model == "I2C" and not config.addr then
        local addr_list = {0x68, 0x69}
        for i = 1, #addr_list do
            g_dev_addr = addr_list[i]
            id = rd8(REG_CHIP_ID)
            if id == CHIP_ID_BMI270 then
                log.info("exs_bmi270", string.format("芯片地址自适应：0x%02X", g_dev_addr))
                break
            end
        end
    else
        id = rd8(REG_CHIP_ID)
    end
    if id ~= CHIP_ID_BMI270 then
        log.error("exs_bmi270", string.format("芯片识别失败：期望 0x%02X 实际 0x%02X", CHIP_ID_BMI270, id or 0))
        return false
    end
    log.info("exs_bmi270", string.format("BMI270 @ %s 模式，芯片 ID=0x%02X", model, id))

    -- 软复位：Bosch 官方 API 标准流程，初始化前先软复位确保芯片处于已知干净状态。
    -- 反复初始化失败/残留状态时，软复位可清掉旧配置（配置加载每次只能成功一次，
    -- 软复位后必须重载微程序）。
    if not soft_reset_and_prepare() then return false end

    -- 执行初始化序列（最多重试 3 次）
    -- 每次重试前都软复位回到干净状态（配置加载每次只能成功一次）
    local init_ok = false
    for attempt = 1, 3 do
        if init_sequence(config.acc_range or "4g", config.gyro_range or "500",
                         config.acc_odr or 200, config.gyro_odr or 200) then
            init_ok = true
            break
        end
        log.warn("exs_bmi270", string.format("初始化失败（第 %d/3 次），软复位后重试", attempt))
        if attempt < 3 then
            if not soft_reset_and_prepare() then break end
        end
    end
    if not init_ok then
        log.error("exs_bmi270", "3 次初始化均失败")
        return false
    end

    g_ready = true
    log.info("exs_bmi270", string.format("初始化完成：acc_range=%s gyro_range=%s acc_odr=%dHz gyro_odr=%dHz",
        config.acc_range or "4g", config.gyro_range or "500",
        config.acc_odr or 200, config.gyro_odr or 200))

    -- 配置中断（可选）：config.int1/int2 注册 GPIO 中断
    -- 支持事件：data_ready（数据就绪，开箱即用）、any_motion/no_motion/sig_motion/step（特征中断）
    -- 特征中断在微程序配置基础上再通过 FEATURES 寄存器使能（本库已实现），
    -- 若用户在 int1/int2 中请求了特征事件，先使能对应 feature，再做引脚映射与 GPIO 注册。
    if config.int1 and type(config.int1) == "table" then
        enable_feature_ints(config.int1)
        apply_int_pin("int1", config.int1)
    end
    if config.int2 and type(config.int2) == "table" then
        enable_feature_ints(config.int2)
        apply_int_pin("int2", config.int2)
    end

    return true
end

--[[
读取传感器原始 ADC 值

返回未经过换算的原始数据，供高级用户做自定义算法。

@api exs_bmi270.get_raw()
@return table or nil
  raw.ax/ay/az - 三轴加速度原始值（16-bit 有符号）
  raw.gx/gy/gz - 三轴陀螺仪原始值（16-bit 有符号）
  raw.temp     - 温度原始值（16-bit 有符号）
]]
function exs_bmi270.get_raw()
    if not g_ready then log.error("exs_bmi270.get_raw 请先 setup()"); return nil end
    return read_raw_data()
end

--[[
读取三轴加速度（单位 g）

静止水平放置时：Z≈+1.0g，X≈0g，Y≈0g。

@api exs_bmi270.get_accel()
@return table or nil
  acc.x/y/z - 三轴加速度，单位 g
]]
function exs_bmi270.get_accel()
    if not g_ready then log.error("exs_bmi270.get_accel 请先 setup()"); return nil end
    local raw = read_raw_data()
    if not raw then return nil end
    return { x = raw.ax / g_acc_sens, y = raw.ay / g_acc_sens, z = raw.az / g_acc_sens }
end

--[[
读取三轴角速度（单位 °/s）

静止时三轴均接近 0°/s。

@api exs_bmi270.get_gyro()
@return table or nil
  gyro.x/y/z - 三轴角速度，单位 °/s
]]
function exs_bmi270.get_gyro()
    if not g_ready then log.error("exs_bmi270.get_gyro 请先 setup()"); return nil end
    local raw = read_raw_data()
    if not raw then return nil end
    return { x = raw.gx / g_gyro_sens, y = raw.gy / g_gyro_sens, z = raw.gz / g_gyro_sens }
end

--[[
读取芯片温度（单位 °C）

公式：temp = 23.0 + rawTemp / 512.0（来源：BMI270 数据手册第 4.6.14 节）。

@api exs_bmi270.get_temp()
@return number or nil 芯片温度，单位 °C
]]
function exs_bmi270.get_temp()
    if not g_ready then log.error("exs_bmi270.get_temp 请先 setup()"); return nil end
    local raw = read_raw_data()
    if not raw then return nil end
    return 23.0 + raw.temp / 512.0
end

--[[
读取加速度、角速度与温度组合数据

@api exs_bmi270.get_data()
@return table or nil
  data.x/y/z   - 三轴加速度，单位 g
  data.gx/gy/gz- 三轴角速度，单位 °/s
  data.temp    - 芯片温度，单位 °C
]]
function exs_bmi270.get_data()
    if not g_ready then log.error("exs_bmi270.get_data 请先 setup()"); return nil end
    local raw = read_raw_data()
    if not raw then return nil end
    return {
        x = raw.ax / g_acc_sens, y = raw.ay / g_acc_sens, z = raw.az / g_acc_sens,
        gx = raw.gx / g_gyro_sens, gy = raw.gy / g_gyro_sens, gz = raw.gz / g_gyro_sens,
        temp = 23.0 + raw.temp / 512.0,
    }
end

--[[
Mahony 互补滤波姿态解算

融合陀螺仪积分（动态响应快）与加速度计修正（长期稳定），输出平滑姿态角。
yaw 角做无限叠加展开，可累计多圈（无 ±180° 跳变）。

> 必须在一个循环中以固定频率（建议 10~50ms 间隔）持续调用，
> 中断后陀螺积分会重置，姿态将从当前加速度推算值重新收敛。

@api exs_bmi270.get_attitude()
@return number, number, number or nil
  roll  - 横滚角，单位 °，右倾为正
  pitch - 俯仰角，单位 °，前倾为正
  yaw   - 偏航角，单位 °，连续叠加（无磁力计会缓慢漂移）
]]
function exs_bmi270.get_attitude()
    if not g_ready then log.error("exs_bmi270.get_attitude 请先 setup()"); return nil end
    local raw = read_raw_data()
    if not raw then return nil end

    -- 计算积分步长 dt（秒），首次调用用默认值
    -- 使用 mcu.ticks2(1) 获取高精度毫秒计数（64bit 不溢出）
    local ms_h, ms_l = mcu.ticks2(1)
    local now = ms_h * 1000000.0 + ms_l  -- 合并为总毫秒数（浮点避免溢出）
    local dt = g_last_time > 0 and (now - g_last_time) * 0.001 or DEFAULT_DT
    g_last_time = now
    if dt <= 0 or dt > 1 then dt = DEFAULT_DT end  -- 异常时回退默认值

    -- 加速度单位 g，陀螺仪单位 rad/s（°/s → rad/s：×π/180），扣除零偏
    local ax, ay, az = raw.ax / g_acc_sens, raw.ay / g_acc_sens, raw.az / g_acc_sens
    local gx = (raw.gx / g_gyro_sens - g_gyro_bias_x) * 0.0174533
    local gy = (raw.gy / g_gyro_sens - g_gyro_bias_y) * 0.0174533
    local gz = (raw.gz / g_gyro_sens - g_gyro_bias_z) * 0.0174533

    mahony_update(ax, ay, az, gx, gy, gz, dt)

    local roll, pitch, yaw = quat_to_euler()
    return roll, pitch, unwrap_yaw(yaw)
end

--[[
切换加速度量程

@api exs_bmi270.set_acc_range(range)
@string range 量程字符串："2g"/"4g"/"8g"/"16g"
@return boolean
]]
function exs_bmi270.set_acc_range(range)
    if not g_ready then log.error("exs_bmi270.set_acc_range 请先 setup()"); return false end
    local reg, sens = acc_range_to_params(range)
    if reg == g_acc_range_reg then
        log.info("exs_bmi270", string.format("加速度量程已是 %s，无需切换", range))
        return true
    end
    -- 实测：运行中直接写 ACC_RANGE 寄存器（含断电→写→上电）数据通路均不生效，
    -- 唯一实测有效的路径是软复位后完整重走 init_sequence（此时写量程才被应用）。
    local acc_str, gyro_str, acc_odr, gyro_odr = current_cfg_to_params()
    if not soft_reset_and_prepare() then return false end
    if not init_sequence(range, gyro_str, acc_odr, gyro_odr) then
        log.error("exs_bmi270", "加速度量程切换（软复位重初始化）失败")
        return false
    end
    reapply_interrupts()   -- 软复位清空特征配置与引脚映射，需重新使能与注册
    log.info("exs_bmi270", string.format("加速度量程切换为 %s", range))
    return true
end

--[[
切换陀螺仪量程

@api exs_bmi270.set_gyro_range(range)
@string range 量程字符串："125"/"250"/"500"/"1000"/"2000"
@return boolean
]]
function exs_bmi270.set_gyro_range(range)
    if not g_ready then log.error("exs_bmi270.set_gyro_range 请先 setup()"); return false end
    local reg, sens = gyro_range_to_params(range)
    if reg == g_gyro_range_reg then
        log.info("exs_bmi270", string.format("陀螺仪量程已是 %s，无需切换", range))
        return true
    end
    -- 实测：运行中直接写 GYR_RANGE 寄存器（含断电→写→上电）数据通路均不生效，
    -- 唯一实测有效的路径是软复位后完整重走 init_sequence。
    local acc_str, gyro_str, acc_odr, gyro_odr = current_cfg_to_params()
    if not soft_reset_and_prepare() then return false end
    if not init_sequence(acc_str, range, acc_odr, gyro_odr) then
        log.error("exs_bmi270", "陀螺仪量程切换（软复位重初始化）失败")
        return false
    end
    reapply_interrupts()   -- 软复位清空特征配置与引脚映射，需重新使能与注册
    log.info("exs_bmi270", string.format("陀螺仪量程切换为 %s°/s", range))
    return true
end

--[[
陀螺零偏标定

设备必须保持静止。采集 samples 次（默认 50）陀螺读数求平均，
作为三轴零偏在姿态解算前扣除，可显著减少静止时 roll/pitch/yaw 漂移。

@api exs_bmi270.calibrate_gyro(samples)
@int samples 采样次数，默认 50，越多越准但耗时越长
@return table or nil
  bias.x/y/z - 三轴零偏，单位 °/s
]]
function exs_bmi270.calibrate_gyro(samples)
    if not g_ready then log.error("exs_bmi270.calibrate_gyro 请先 setup()"); return nil end
    samples = samples or 50
    local sx, sy, sz = 0, 0, 0
    for i = 1, samples do
        local raw = read_raw_data()
        if not raw then return nil end
        sx = sx + raw.gx
        sy = sy + raw.gy
        sz = sz + raw.gz
    end
    g_gyro_bias_x = sx / samples / g_gyro_sens
    g_gyro_bias_y = sy / samples / g_gyro_sens
    g_gyro_bias_z = sz / samples / g_gyro_sens
    log.info("exs_bmi270", string.format("陀螺零偏标定完成: (%.3f, %.3f, %.3f)°/s",
        g_gyro_bias_x, g_gyro_bias_y, g_gyro_bias_z))
    return { x = g_gyro_bias_x, y = g_gyro_bias_y, z = g_gyro_bias_z }
end

--[[
配置中断事件（setup 之外动态配置）

@api exs_bmi270.int_config(int, cfg)
@string int "int1" 或 "int2"
@table  cfg 事件配置，字段：
  int_gpio - 中断引脚号（必填）
  lvl      - 有效电平：1=高有效(RISING)，0=低有效(FALLING)，默认低有效（BMI270 原生）
  data_ready - 数据就绪中断（boolean，开箱即用）
  any_motion - 任意运动中断（boolean，开箱即用，自动使能）
  no_motion  - 无运动中断（boolean，开箱即用，自动使能）
  sig_motion - 显著运动中断（boolean，开箱即用，自动使能）
  step       - 步进检测中断（boolean，开箱即用，自动使能）
  any_motion_thresh_mg - 任意运动阈值（number，mg，默认 83）
  any_motion_duration_ms - 任意运动持续时间（number，ms，默认 100）
  no_motion_thresh_mg - 无运动阈值（number，mg，默认 70）
  no_motion_duration_ms - 无运动持续时间（number，ms，默认 100）
  sig_motion_block_ms - 显著运动触发时长（number，ms，默认 5000）
  step_counter - 步数计数器开关（boolean，配合 step 使用，可读取步数）
  step_watermark_steps - 步数刷新间隔（number，单位步，默认 20；每累计该步数 get_step_count() 刷新一次）
  topic    - 中断消息 topic（string）：中断回调通过 sys.publish(topic) 通知，主任务
             sys.waitUntil(topic) 等待后读取数据（推荐，回调内不做 I2C）
  cb       - 中断回调函数（无参）：仅通知用户"中断发生"，用户应在主任务里读数据
             注意：回调运行在中断上下文，绝不能在里面做 I2C 读取（会打断软件 I2C 位时序）
@return boolean
  注意事项：特征中断（any_motion/no_motion/sig_motion/step）开箱即用，本库自动使能对应
  feature 并映射到 INT 引脚；data_ready 数据中断无需额外配置。
  推荐用 topic 模式：中断回调只发消息，数据读取在主任务协程完成。
]]
function exs_bmi270.int_config(int, cfg)
    if not g_ready then log.error("exs_bmi270.int_config 请先 setup()"); return false end
    if type(int) ~= "string" or type(cfg) ~= "table" then
        log.error("exs_bmi270.int_config 参数错误"); return false
    end
    enable_feature_ints(cfg)   -- 使能 cfg 中请求的特征中断（any_motion/no_motion/sig_motion/step）
    apply_int_pin(int, cfg)
    return true
end

--[[
读取中断状态（读后自动清除中断标志）

@api exs_bmi270.get_int_status()
@return table 事件名数组，可能包含：
  "data_ready" "fifo_wm" "fifo_ffull" "error"   -- 数据中断
  "any_motion" "no_motion" "sig_motion" "step"  -- 特征中断
]]
function exs_bmi270.get_int_status()
    if not g_ready then log.error("exs_bmi270.get_int_status 请先 setup()"); return nil end
    local s0 = rd8(REG_INT_STATUS_0) or 0
    local s1 = rd8(REG_INT_STATUS_1) or 0
    return collect_events(nil, s0, s1)  -- nil 表示报告全部状态位
end

--[[
读取步数计数值（32 位完整步数）

需要先使能 step_counter（config.int1/int2 的 step 事件 + step_counter=true，或 int_config 配置）。
步数保存在特征页 0 的 SC_OUT_0_1(0x30)/SC_OUT_2_3(0x32) 共 4 字节（32 位无符号），
与 Bosch 官方驱动读取方式一致，可支持 0 ~ 4294967295 步。

注意：
- 必须同时使能 step_counter 并设置非零 watermark（step_watermark_steps），
  否则计步器输出被禁用，本函数恒返回 0。
- 步数每累计 step_watermark_steps 步更新一次（内部以 20 步为粒度）。
- 超过 32 位上限会自然回绕，正常使用几乎不会达到。

@api exs_bmi270.get_step_count()
@return number or nil 步数（0~4294967295），未初始化、未使能 step_counter 或读取失败返回 nil
]]
function exs_bmi270.get_step_count()
    if not g_ready then log.error("exs_bmi270.get_step_count 请先 setup()"); return nil end
    -- 读特征页 0 的 SC_OUT_0_1 + SC_OUT_2_3（0x30~0x33 共 4 字节，LSB 先）
    local d = read_feat_page(0)
    if not d or #d < 4 then return nil end
    local lo16 = d:byte(1) | (d:byte(2) << 8)
    local hi16 = d:byte(3) | (d:byte(4) << 8)
    return (hi16 << 16) | lo16
end

--[[
清零步数计数器

写 SC_26.reset_counter 位（bit10）触发计步器清零，计数重新从 0 开始。
仅在 step counter/detector 已使能时生效；该位硬件自清零，无需手动复位。

@api exs_bmi270.reset_step_count()
@return boolean 是否成功
]]
function exs_bmi270.reset_step_count()
    if not g_ready then log.error("exs_bmi270.reset_step_count 请先 setup()"); return false end
    -- 页6 偏移 0x02 的 SC_26，写 bit10=1（reset_counter）
    return write_feat_word(FEAT_PAGE_STEP, FEAT_SC26_OFFSET, 0x0400, 0x0400)
end

--[[
软复位并重新初始化传感器

发送软复位命令（CMD=0xB6）后重新执行完整初始化序列，
量程/采样率恢复为 setup 时的配置。

@api exs_bmi270.reset()
@return boolean
  注意事项：需在 sys.taskInit 协程中调用（内部含 sys.wait）
]]
function exs_bmi270.reset()
    if not g_ready then log.error("exs_bmi270.reset 请先 setup()"); return false end
    if not soft_reset_and_prepare() then return false end

    -- 恢复为当前记录的量程/采样率配置
    local acc_str, gyro_str, acc_odr, gyro_odr = current_cfg_to_params()
    if not init_sequence(acc_str, gyro_str, acc_odr, gyro_odr) then return false end
    reapply_interrupts()   -- 软复位清空特征配置与引脚映射，需重新使能与注册
    return true
end

--[[
进入休眠模式（低功耗）

关闭加速度计、陀螺仪和温度传感器电源（PWR_CTRL=0x00），保持内部配置。
调用 wakeup() 可快速恢复工作，无需重新 setup()。

@api exs_bmi270.sleep()
@return nil
]]
function exs_bmi270.sleep()
    if not g_ready then log.error("exs_bmi270.sleep 请先 setup()"); return end
    wr8(REG_PWR_CTRL, 0x00)
    log.info("exs_bmi270", "已进入休眠模式")
end

--[[
从休眠模式唤醒

重新上电使能加速度计+陀螺仪+温度传感器（PWR_CTRL=0x0E）。

@api exs_bmi270.wakeup()
@return nil
]]
function exs_bmi270.wakeup()
    if not g_ready then log.error("exs_bmi270.wakeup 请先 setup()"); return end
    wr8(REG_PWR_CTRL, PWR_CTRL_EN)  -- 重新上电使能传感器（配置仍在，无需重新加载微程序）
    -- 等待传感器上电并开始采样。BMI270 快速启动约 2ms，但实测 SPI 下首次读仍可能全零，
    -- 等 data ready（STATUS bit7=drdy_acc）或超时 50ms
    sys.wait(20)
    for i = 1, 10 do
        local st = rd8(0x03)
        if st and (st & 0x80) ~= 0 then break end  -- drdy_acc 置位，数据就绪
        sys.wait(5)
    end
    log.info("exs_bmi270", "已从休眠模式唤醒")
end

--[[
关闭传感器并释放资源

传感器进入休眠（PWR_CTRL=0x00），软件 I2C 无需手动关闭（gc 自动回收），
硬件 I2C 与 SPI 设备关闭。close 后需重新调用 setup() 才能再次使用。

@api exs_bmi270.close()
@return nil
]]
function exs_bmi270.close()
    if not g_ready then return end

    -- 先注销 GPIO 中断（防止 close 后 INT 引脚变化触发回调导致死机）
    if g_int1_gpio then gpio.setup(g_int1_gpio, nil) end
    if g_int2_gpio then gpio.setup(g_int2_gpio, nil) end

    -- 传感器进入休眠
    wr8(REG_PWR_CTRL, 0x00)

    -- 释放通信资源
    if g_iface == "I2C" then
        if not g_is_soft then i2c.close(g_i2c_bus) end  -- 软件 I2C 由 gc 自动回收
    elseif g_iface == "SPI" then
        if g_spi_dev then g_spi_dev:close() end
    end

    -- 重置内部状态
    g_iface = nil
    g_i2c_bus = 0
    g_dev_addr = 0x68
    g_is_soft = false
    g_scl_pin, g_sda_pin = nil, nil
    g_spi_dev = nil
    g_ready = false
    g_acc_sens = ACC_SENS_4G
    g_gyro_sens = GYR_SENS_500
    g_acc_range_reg = ACC_RANGE_4G
    g_gyro_range_reg = GYR_RANGE_500
    g_acc_odr_reg = ACC_ODR_200
    g_gyro_odr_reg = GYR_ODR_200
    g_raw_debug_logged = false
    g_gyro_bias_x, g_gyro_bias_y, g_gyro_bias_z = 0.0, 0.0, 0.0
    g_int1_cb, g_int2_cb = nil, nil
    g_int1_gpio, g_int2_gpio = nil, nil
    g_int1_level, g_int2_level = INT_LEVEL_ACTIVE_LOW, INT_LEVEL_ACTIVE_LOW
    g_int1_cfg, g_int2_cfg = nil, nil

    log.info("exs_bmi270", "传感器已关闭")
end

--[[
获取版本号

@api exs_bmi270.version()
@return string 版本号，格式 yyyymmddhhmm
]]
function exs_bmi270.version() return "202608051600" end

log.debug("exs_bmi270", "version -> " .. exs_bmi270.version())
return exs_bmi270
