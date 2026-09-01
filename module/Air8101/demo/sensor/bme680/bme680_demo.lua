--[[
@module  bme680_demo
@summary BME680 四合一环境传感器演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.08.08
@author  江访
@usage
本文件包含 BME680 的逐项功能演示。
通过 exs_bme680 扩展库的 API 逐一演示数据读取、IIR 滤波切换、过采样率切换、
气体加热器切换、海拔计算等功能。

通过 MODE 变量选择通信模式（改 MODE 的值即可，无需注释/取消注释代码）：
  MODE = 1  软件 I2C（默认推荐，仅需 scl/sda 引脚，任意 GPIO 均可，接线最灵活）
  MODE = 2  硬件 I2C（指定 i2c_id，占用 CPU 少）

Air8101 接线（软件 I2C）：
  SCL = GPIO4
  SDA = GPIO5
]]

-- 加载 exs_bme680 扩展库
-- 该库提供 BME680 的全部驱动功能: 初始化/温度/气压/湿度/气体电阻读取/过采样/滤波/加热器/海拔
local exs_bme680 = require "exs_bme680"

-- ==================== 通信模式选择 ====================
-- 改 MODE 的值选择通信模式：
--   1 = 软件 I2C（默认）   2 = 硬件 I2C
-- 各模式所需引脚/参数见下方 init_config，接线说明见 readme.md
local MODE = 1

local init_config
if MODE == 1 then
    -- 软件 I2C：SCL/SDA 用任意 GPIO，Air8101 接线示例用 GPIO4/GPIO5
    init_config = {scl = 4, sda = 5}
elseif MODE == 2 then
    -- 硬件 I2C：i2c_id 为总线号（Air8101 用 1），不传 scl/sda 时无总线恢复能力
    init_config = {i2c_id = 1}
else
    log.error("bme680_demo", "MODE 取值错误，应为 1/2")
    return
end

--------------------------------------------------------------
-- [1/5] 初始化与数据读取
-- - setup() 自动完成芯片 ID 校验、校准数据读取、采样/滤波/加热器参数配置
-- - get_data() 返回温度(°C)、气压(hPa)、湿度(%RH)、气体电阻(Ω)
--------------------------------------------------------------
local function demo_init_and_read()
    log.info("bme680_demo", "===== [1/5] 初始化与数据读取 =====")

    -- BME680 默认配置：温度 4X 过采样，气压 4X 过采样，湿度 2X 过采样
    -- IIR 滤波 8 次平均，气体加热器 320°C / 150ms
    local result = exs_bme680.setup(init_config)

    if not result then
        log.error("bme680_demo", "BME680 初始化失败")
        log.error("bme680_demo", "检查接线: VCC=3.3V GND SCL SDA，I2C 地址是否正确（如 0x76/0x77）")
        return false  -- 初始化失败必须返回 false
    end
    log.info("bme680_demo", "BME680 初始化成功，版本:", exs_bme680.version())

    -- 等待传感器稳定，气体传感器需要预热
    -- 首次读取气体电阻可能为 0（加热器未稳定），这是正常现象
    sys.wait(500)   -- 等待传感器稳定，500ms
    local data = exs_bme680.get_data()
    if data then
        local gas_kohm = data.gas_resistance / 1000
        log.info("bme680_demo", string.format("温度=%.2f°C 气压=%.2fhPa 湿度=%.1f%%RH 气体=%.1fkΩ",
            data.temperature, data.pressure, data.humidity, gas_kohm))
    else
        log.error("bme680_demo", "读取数据失败")
    end
    sys.wait(1000)  -- 稳定后等待 1 秒进入连续读取

    -- 连续读取 3 次，观察数据变化
    for i = 1, 3 do
        sys.wait(2000)  -- 每次读取间隔 2 秒
        local d = exs_bme680.get_data()
        if d then
            local gas_kohm = d.gas_resistance / 1000
            log.info("bme680_demo", string.format("第%d次读取: 温度=%.2f°C 气压=%.1fhPa 湿度=%.1f%%RH 气体=%.1fkΩ",
                i, d.temperature, d.pressure, d.humidity, gas_kohm))
        end
    end
    log.info("bme680_demo", "---- [1/5] 完成 ----")
    return true
end

--------------------------------------------------------------
-- [2/5] IIR 滤波器切换演示
-- - set_filter(0~7) 设置 IIR 滤波器系数，数值越大数据越平滑
--------------------------------------------------------------
local function demo_filter_switch()
    log.info("bme680_demo", "===== [2/5] IIR 滤波器切换演示 =====")

    -- 依次切换 filter=0/1/2/3/4/5/6/7，观察数据变化
    local filter_list = { 0, 1, 2, 3, 4, 5, 6, 7 }
    for _, f in ipairs(filter_list) do
        log.info("bme680_demo", string.format("设置滤波器 filter=%d", f))
        exs_bme680.set_filter(f)
        sys.wait(100)   -- 等待滤波器生效，100ms

        local data = exs_bme680.get_data()
        if data then
            log.info("bme680_demo", string.format("filter=%d: 温度=%.2f°C 气压=%.2fhPa 湿度=%.1f%%RH",
                f, data.temperature, data.pressure, data.humidity))
        end
        sys.wait(1000)  -- 每档滤波器显示间隔 1 秒
    end
    log.info("bme680_demo", "---- [2/5] 完成 ----")
    return true
end

--------------------------------------------------------------
-- [3/5] 过采样率切换演示
-- - set_temp/press/hum_oversampling(0~5) 设置过采样率
-- - 低功耗(1X)与高精度(16X)对比
--------------------------------------------------------------
local function demo_oversampling_switch()
    log.info("bme680_demo", "===== [3/5] 过采样率切换演示 =====")

    -- 低功耗模式：全部 1X 过采样
    log.info("bme680_demo", "切换到低功耗模式（1X过采样）")
    exs_bme680.set_temp_oversampling(1)
    exs_bme680.set_press_oversampling(1)
    exs_bme680.set_hum_oversampling(1)
    sys.wait(100)   -- 等待配置生效，100ms

    local data = exs_bme680.get_data()
    if data then
        log.info("bme680_demo", string.format("低功耗: 温度=%.2f°C 气压=%.2fhPa 湿度=%.1f%%RH",
            data.temperature, data.pressure, data.humidity))
    end
    sys.wait(1000)  -- 展示间隔 1 秒

    -- 高精度模式：全部 16X 过采样
    log.info("bme680_demo", "切换到高精度模式（16X过采样）")
    exs_bme680.set_temp_oversampling(5)
    exs_bme680.set_press_oversampling(5)
    exs_bme680.set_hum_oversampling(5)
    sys.wait(100)   -- 等待配置生效，100ms

    data = exs_bme680.get_data()
    if data then
        log.info("bme680_demo", string.format("高精度: 温度=%.2f°C 气压=%.2fhPa 湿度=%.1f%%RH",
            data.temperature, data.pressure, data.humidity))
    end
    log.info("bme680_demo", "---- [3/5] 完成 ----")
    return true
end

--------------------------------------------------------------
-- [4/5] 气体加热器切换演示
-- - set_gas_heater(temp, time) 设置加热器温度(200~400°C)与时长(1~4032ms)
-- - 不同温度下气体电阻值会变化
--------------------------------------------------------------
local function demo_gas_heater_switch()
    log.info("bme680_demo", "===== [4/5] 气体加热器切换演示 =====")

    -- 不同加热器温度组合
    local heater_configs = {
        { temp = 250, time = 100, desc = "低温短时（250°C/100ms）" },
        { temp = 320, time = 150, desc = "默认配置（320°C/150ms）" },
        { temp = 350, time = 200, desc = "高温长时（350°C/200ms）" },
    }

    for _, cfg in ipairs(heater_configs) do
        log.info("bme680_demo", cfg.desc)
        exs_bme680.set_gas_heater(cfg.temp, cfg.time)
        sys.wait(200)   -- 等待加热器参数生效，200ms

        local data = exs_bme680.get_data()
        if data then
            local gas_kohm = data.gas_resistance / 1000
            log.info("bme680_demo", string.format("气体=%.1fkΩ 温度=%.2f°C 湿度=%.1f%%RH",
                gas_kohm, data.temperature, data.humidity))
        end
        sys.wait(1000)  -- 展示间隔 1 秒
    end
    log.info("bme680_demo", "---- [4/5] 完成 ----")
    return true
end

--------------------------------------------------------------
-- [5/5] 海拔高度测量与关闭
-- - get_altitude(pressure) 依据气压计算海拔高度
-- - close() 关闭传感器并释放 I2C 资源
--------------------------------------------------------------
local function demo_altitude_and_close()
    log.info("bme680_demo", "===== [5/5] 海拔高度测量与关闭 =====")

    local data = exs_bme680.get_data()
    if data then
        local alt = exs_bme680.get_altitude(data.pressure)
        local gas_kohm = data.gas_resistance / 1000
        log.info("bme680_demo", string.format("温度=%.2f°C 气压=%.1fhPa 湿度=%.1f%%RH 气体=%.1fkΩ 海拔=%.1f米",
            data.temperature, data.pressure, data.humidity, gas_kohm, alt))
    end

    -- 关闭传感器
    exs_bme680.close()
    log.info("bme680_demo", "---- [5/5] 完成 ----")
    return true
end

--------------------------------------------------------------
-- 主任务：按 [1/5]~[5/5] 顺序执行全部演示
--------------------------------------------------------------
local function bme680_demo_task_func()
    log.info("bme680_demo", "HELLO")
    sys.wait(1000)  -- 等待系统启动稳定，1 秒

    local ok = demo_init_and_read()
    if not ok then
        log.error("bme680_demo", "初始化失败，演示终止")
        return
    end
    sys.wait(500)   -- 演示间隔，500ms

    demo_filter_switch()
    sys.wait(500)   -- 演示间隔，500ms

    demo_oversampling_switch()
    sys.wait(500)   -- 演示间隔，500ms

    demo_gas_heater_switch()
    sys.wait(500)   -- 演示间隔，500ms

    demo_altitude_and_close()
    sys.wait(500)   -- 演示间隔，500ms

    log.info("bme680_demo", "===== [演示完毕] =====")
    log.info("bme680_demo", "End")
end

-- 启动演示任务协程
sys.taskInit(bme680_demo_task_func)
