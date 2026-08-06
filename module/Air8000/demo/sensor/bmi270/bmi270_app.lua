--[[
@module  bmi270_app
@summary BMI270 六轴惯性传感器演示模块（3 种通信模式 + 中断触发）
@version 1.1
@date    2026.08.05
@author  江访
@usage
=== 演示流程: 初始化 → 数据读取 → 量程切换 → 姿态解算 → 中断触发 → 休眠唤醒 ===

通过 MODE 变量选择通信模式（改 MODE 的值即可，无需注释/取消注释代码）：

  MODE = 1  软件 I2C（默认推荐，仅需 scl/sda 引脚，任意 GPIO 均可，接线最灵活）
  MODE = 2  硬件 I2C（指定 i2c_id，占用 CPU 少，Air8000 用 I2C1）
  MODE = 3  SPI（高速模式，需指定 spi_id + cs，Air8000 用 SPI1，适合高速采样）

本文件通过 exs_bmi270 扩展库的 API 逐一演示 BMI270 的以下功能：

1.  初始化和基本信息查询  -- setup() 芯片 ID 校验 + 微程序自动加载 + 中断注册
2.  加速度/角速度/温度读取  -- get_accel()/get_gyro()/get_temp(), 单位 g/°/s/°C
3.  量程切换演示          -- set_acc_range()/set_gyro_range(), 动态调整测量范围
4.  姿态解算              -- calibrate_gyro() 零偏标定 + get_attitude() Mahony 互补滤波
5.  中断触发演示          -- any_motion 事件中断，topic 方式回调
6.  休眠唤醒与资源释放     -- sleep()/wakeup()/close(), 低功耗管理
]]

-- 加载 exs_bmi270 扩展库
-- 该库提供 BMI270 的全部驱动功能: 初始化/数据读取/量程配置/姿态解算/中断/电源管理
local exs_bmi270 = require "exs_bmi270"

-- ==================== 通信模式选择 ====================
-- 改 MODE 的值选择通信模式：
--   1 = 软件 I2C（默认）   2 = 硬件 I2C   3 = SPI
-- 各模式所需引脚/参数见下方 init_config，接线说明见 readme.md
local MODE = 1

-- 中断 GPIO：BMI270 的 INT1 引脚接到核心板的这个 GPIO（三种模式通用，按实际接线修改）
-- 注意：Air8000A/AB/U/N/D/B 内置 G-Sensor 占用 PIN80/81（I2C0），INT1 接线不要占用该两脚
local INT1_GPIO = 17

local init_mode = "I2C"
local init_config
if MODE == 1 then
    -- 软件 I2C：SCL/SDA 用任意 GPIO，Air8000 接线示例用 GPIO1/GPIO2
    -- 不传 addr：扩展库自动探测 0x68/0x69（SDO 引脚决定），chip id 校验命中即锁定
    init_config = {scl = 1, sda = 2, acc_range = "4g", gyro_range = "500", acc_odr = 200, gyro_odr = 200}
elseif MODE == 2 then
    -- 硬件 I2C：Air8000 用 I2C1（i2c_id=1），默认管脚 Pin66=SCL, Pin67=SDA
    -- 注意：Air8000A/AB/U/N/D/B 的 I2C0 固定 PIN80/81 且已被内部 G-Sensor(地址0x27)占用，外部不可使用；
    --       同时外部设备地址不要使用 0x27，避免与内部 G-Sensor 冲突
    init_config = {i2c_id = 1, acc_range = "4g", gyro_range = "500", acc_odr = 200, gyro_odr = 200}
elseif MODE == 3 then
    -- SPI：Air8000 用 SPI1（spi_id=1），CS 用 GPIO12/SPI1_CS，SCLK/MOSI/MISO 用 SPI1 默认管脚
    -- 注意：Air8000A/U/N/W/AB 的 SPI0 已被内部 AirLink（4G主控↔WiFi芯片）占用，对外只有 SPI1 可用
    init_mode = "SPI"
    init_config = {spi_id = 1, cs = 12, speed = 1000000, acc_range = "4g", gyro_range = "500", acc_odr = 200, gyro_odr = 200}
else
    log.error("TEST", "MODE 取值错误，应为 1/2/3")
    return
end

-- 中断消息 topic：GPIO 中断回调发布，主任务等待后读取
local INT_TOPIC = "BMI270_INT"

--------------------------------------------------------------
-- [1/6] 初始化
-- - 自动完成芯片 ID 校验（期望 0x24）
-- - 自动加载 8192 字节 Bosch 出厂微程序（首次使用必须，否则无法测量）
-- - 自动配置量程、采样率，并注册 INT1 中断（data_ready + any_motion）
--------------------------------------------------------------
local function init_func()
    log.info("TEST", "=== [1/6] 初始化 ===")
    log.info("TEST", string.format("通信模式: %s (MODE=%d)", MODE == 3 and "SPI" or (MODE == 2 and "硬件I2C" or "软件I2C"), MODE))
    local result = exs_bmi270.setup(init_mode, {
        scl = init_config.scl, sda = init_config.sda,
        i2c_id = init_config.i2c_id,
        spi_id = init_config.spi_id, cs = init_config.cs, speed = init_config.speed,
        acc_range = init_config.acc_range, gyro_range = init_config.gyro_range,
        acc_odr = init_config.acc_odr, gyro_odr = init_config.gyro_odr,
        int1 = {
            int_gpio = INT1_GPIO,        -- BMI270 INT1 引脚接的 GPIO
            -- data_ready = true,           -- 数据就绪中断：每个采样周期触发一次
            any_motion = true,           -- 任意运动中断：检测到晃动触发
            any_motion_thresh_mg = 100,  -- 阈值 100mg（默认 83mg，越小越灵敏）
            topic = INT_TOPIC,           -- 中断回调发布该 topic，主任务等待
        },
    })
    if not result then
        log.error("TEST", "初始化失败! 检查接线: VCC=3.3V GND SCL SDA")
        return false  -- 初始化失败必须返回 false
    end
    log.info("TEST", "初始化成功，扩展库版本:", exs_bmi270.version())
    return true
end

--------------------------------------------------------------
-- [2/6] 加速度/角速度/温度读取
-- - get_accel() 单位 g，水平静止时 Z≈1.0g，X/Y≈0
-- - get_gyro()  单位 °/s，静止时应接近 0
-- - get_temp()  单位 °C，芯片温度会高于环境温度
--------------------------------------------------------------
local function read_data_func()
    log.info("TEST", "=== [2/6] 数据读取 (单位 g / °/s / °C) ===")
    local acc = exs_bmi270.get_accel()
    local gyro = exs_bmi270.get_gyro()
    local temp = exs_bmi270.get_temp()
    if not acc or not gyro or not temp then
        log.error("TEST", "读取数据失败!")
        return
    end
    log.info("TEST", string.format("accel  x=%.3f  y=%.3f  z=%.3f", acc.x, acc.y, acc.z))
    log.info("TEST", string.format("gyro   x=%.1f  y=%.1f  z=%.1f", gyro.x, gyro.y, gyro.z))
    log.info("TEST", string.format("temp   %.1f°C", temp))
    -- 静止水平时 Z 轴应接近 1g；若设备竖直/倾斜安装，重力会分布到 X/Y/Z 上，
    -- 属正常现象（此时姿态解算会自动以真实安装方向为基准）。
    local acc_mag = math.sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
    if math.abs(acc_mag - 1.0) > 0.15 then
        log.warn("TEST", "加速度合矢量偏差较大(期望≈1.0g)，检查传感器是否受振动或供电异常")
    end
end

--------------------------------------------------------------
-- [3/6] 量程切换演示
-- - set_acc_range("8g") 将加速度量程从 ±4g 切换到 ±8g（分辨率下降但可测更大加速度）
-- - set_gyro_range("1000") 将陀螺仪量程从 ±500°/s 切换到 ±1000°/s
-- - 切换后 get_accel()/get_gyro() 自动按新量程换算
--------------------------------------------------------------
local function range_switch_func()
    log.info("TEST", "=== [3/6] 量程切换演示 ===")
    if not exs_bmi270.set_acc_range("8g") then
        log.error("TEST", "加速度量程切换失败!")
        return
    end
    log.info("TEST", "加速度量程已切换为 ±8g")
    local acc = exs_bmi270.get_accel()
    if acc then
        log.info("TEST", string.format("accel  x=%.3f  y=%.3f  z=%.3f", acc.x, acc.y, acc.z))
    end

    if not exs_bmi270.set_gyro_range("1000") then
        log.error("TEST", "陀螺仪量程切换失败!")
        return
    end
    log.info("TEST", "陀螺仪量程已切换为 ±1000°/s")
    local gyro = exs_bmi270.get_gyro()
    if gyro then
        log.info("TEST", string.format("gyro   x=%.1f  y=%.1f  z=%.1f", gyro.x, gyro.y, gyro.z))
    end
end

--------------------------------------------------------------
-- [4/6] 姿态解算（Mahony 互补滤波）
-- - get_attitude() 融合陀螺仪积分与加速度计修正，输出 roll/pitch/yaw
-- - yaw 角连续叠加，无 ±180° 跳变；无磁力计会随时间缓慢漂移
-- - 必须在固定间隔循环中持续调用，保持陀螺积分连续
-- - 首次使用建议先调用 calibrate_gyro() 做陀螺零偏标定（设备保持静止），
--   可显著抑制静止时 roll/pitch/yaw 的缓慢漂移
--------------------------------------------------------------
local function attitude_func()
    log.info("TEST", "=== [4/6] 姿态解算 (5秒) ===")

    -- 陀螺零偏标定：设备必须保持静止，采集 50 次陀螺读数求平均
    -- 标定结果在库内部自动生效，后续 get_attitude() 积分前会扣除零偏
    log.info("TEST", "请保持设备静止，正在进行陀螺零偏标定...")
    local bias = exs_bmi270.calibrate_gyro(50)
    if bias then
        log.info("TEST", string.format("零偏标定完成: (%.3f, %.3f, %.3f)°/s", bias.x, bias.y, bias.z))
    else
        log.warn("TEST", "零偏标定失败，姿态解算将不带零偏补偿")
    end

    local start = os.clock()
    while os.clock() - start < 5 do
        local roll, pitch, yaw = exs_bmi270.get_attitude()
        if roll then
            log.info("TEST", string.format("roll=%.1f°  pitch=%.1f°  yaw=%.1f°", roll, pitch, yaw))
        end
        sys.wait(20)  -- 20ms 调用一次（50Hz），间隔过大会影响姿态平滑度
    end
    log.info("TEST", "姿态解算演示结束")
end

--------------------------------------------------------------
-- [5/6] 中断触发演示
-- - 已通过 setup 注册 any_motion 事件中断（未启用 data_ready，避免高频触发）
-- - GPIO 中断回调只发布消息（不读 I2C），主任务 sys.waitUntil 等待
-- - 收到中断后 get_int_status() 查询具体事件，get_data() 读取数据
-- 测试方法：晃动设备 → any_motion 触发
--------------------------------------------------------------
local function int_func()
    log.info("TEST", "=== [5/6] 中断触发演示 (10秒) ===")
    log.info("TEST", "测试方法：晃动设备触发 any_motion 中断")
    local start = os.clock()
    while os.clock() - start < 10 do
        sys.waitUntil(INT_TOPIC, 2000)  -- 等待中断消息，超时 2 秒
        -- 读取并清除中断状态（区分具体是哪个事件触发）
        local events = exs_bmi270.get_int_status()
        if events and #events > 0 then
            log.info("TEST", "中断事件:", table.concat(events, ","))
        end
        -- 读取一次数据验证（在主任务协程中，I2C 时序完整）
        local data = exs_bmi270.get_data()
        if data then
            log.info("TEST", string.format("acc(%.2f,%.2f,%.2f)g gyr(%.1f,%.1f,%.1f)°/s",
                data.x, data.y, data.z, data.gx, data.gy, data.gz))
        end
    end
    log.info("TEST", "中断触发演示结束")
end

--------------------------------------------------------------
-- [6/6] 休眠唤醒与资源释放
-- - sleep() 进入休眠，功耗最低；wakeup() 快速恢复，无需重新 setup()
-- - close() 关闭传感器并释放通信资源，之后需重新 setup() 才能使用
--------------------------------------------------------------
local function sleep_wakeup_func()
    log.info("TEST", "=== [6/6] 休眠唤醒演示 ===")
    exs_bmi270.sleep()
    log.info("TEST", "已进入休眠，3 秒后唤醒")
    sys.wait(3000)  -- 休眠演示 3 秒
    exs_bmi270.wakeup()
    log.info("TEST", "已唤醒，读取一次数据验证")
    local acc = exs_bmi270.get_accel()
    if acc then
        log.info("TEST", string.format("accel  x=%.3f  y=%.3f  z=%.3f", acc.x, acc.y, acc.z))
    end

    -- 释放资源（演示用，实际项目按需调用）
    exs_bmi270.close()
    log.info("TEST", "传感器已关闭")
end

--------------------------------------------------------------
-- 主任务：按 [1/6]~[6/6] 顺序执行全部演示
--------------------------------------------------------------
local function bmi270_task()
    sys.wait(300)  -- 等待系统启动稳定，300ms
    if not init_func() then return end  -- 初始化失败则结束，按返回值判断

    read_data_func()
    sys.wait(500)  -- 两个演示之间留 500ms，便于观察日志

    range_switch_func()
    sys.wait(500)  -- 量程切换后等待配置生效，500ms

    attitude_func()
    sys.wait(500)  -- 姿态解算演示后间隔 500ms

    int_func()

    sleep_wakeup_func()

    log.info("TEST", "========== 所有演示完成 ==========")
end

-- 启动演示任务协程
sys.taskInit(bmi270_task)
