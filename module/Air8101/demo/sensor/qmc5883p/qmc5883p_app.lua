--[[
@module  qmc5883p_app
@summary QMC5883P 三轴地磁传感器演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.08.05
@author  江访
@usage
本文件包含 QMC5883P 的逐项功能演示。
通过 exs_qmc5883p 扩展库的 API 逐一演示数据读取、量程切换、输出速率切换、
过采样/降采样配置、软复位、芯片自检、休眠唤醒等功能。

通过 MODE 变量选择通信模式（改 MODE 的值即可，无需注释/取消注释代码）：
  MODE = 1  软件 I2C（默认推荐，仅需 scl/sda 引脚，任意 GPIO 均可，接线最灵活）
  MODE = 2  硬件 I2C（指定 i2c_id，占用 CPU 少，Air8101 用 I2C1）
]]

-- 加载 exs_qmc5883p 扩展库
-- 该库提供 QMC5883P 的全部驱动功能: 初始化/数据读取/量程配置/速率配置/自检/电源管理
local exs_qmc5883p = require "exs_qmc5883p"

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
    log.error("qmc5883p_demo", "MODE 取值错误，应为 1/2")
    return
end

--------------------------------------------------------------
-- [1/7] 初始化与数据读取
-- - setup() 自动完成芯片 ID 校验、I2C 总线恢复、采样参数配置
-- - get_data() 返回三轴磁场强度，单位 μT，并带溢出标志 overflow
--------------------------------------------------------------
local function demo_init_and_read()
    log.info("qmc5883p_demo", "===== [1/7] 初始化与数据读取 =====")

    local result = exs_qmc5883p.setup(init_config)
    if not result then
        log.error("qmc5883p_demo", "QMC5883P 初始化失败")
        log.error("qmc5883p_demo", "检查接线: VCC=3.3V GND SCL SDA")
        return false  -- 初始化失败必须返回 false
    end

    log.info("qmc5883p_demo", "QMC5883P 初始化成功，版本:", exs_qmc5883p.version())

    sys.wait(200)   -- 等待首次测量数据就绪，200ms

    local data = exs_qmc5883p.get_data()
    if data then
        log.info("qmc5883p_demo", string.format("X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    else
        log.error("qmc5883p_demo", "读取数据失败")
    end

    for i = 1, 3 do
        sys.wait(500)   -- 每 500ms 读取一次
        local d = exs_qmc5883p.get_data()
        if d then
            log.info("qmc5883p_demo", string.format("第%d次读取: X=%.2f Y=%.2f Z=%.2f uT", i, d.x, d.y, d.z))
        end
    end

    log.info("qmc5883p_demo", "---- [1/7] 完成 ----")
    return true
end

--------------------------------------------------------------
-- [2/7] 量程切换演示
-- - set_range() 支持 "2G"/"8G"/"12G"/"30G" 四种量程
-- - 切换后 get_data() 自动按新灵敏度换算 μT 值，无需重新 setup()
--------------------------------------------------------------
local function demo_range_switch()
    log.info("qmc5883p_demo", "===== [2/7] 量程切换演示 =====")

    log.info("qmc5883p_demo", "切换量程为 2G（高精度，灵敏度 15000 LSB/G）")
    exs_qmc5883p.set_range("2G")
    sys.wait(300)   -- 等待量程切换生效，300ms

    local data = exs_qmc5883p.get_data()
    if data then
        log.info("qmc5883p_demo", string.format("2G 量程: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end
    sys.wait(1000)  -- 展示间隔，1 秒

    log.info("qmc5883p_demo", "切换量程为 8G（宽范围，灵敏度 3750 LSB/G）")
    exs_qmc5883p.set_range("8G")
    sys.wait(300)   -- 等待量程切换生效，300ms

    data = exs_qmc5883p.get_data()
    if data then
        log.info("qmc5883p_demo", string.format("8G 量程: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end
    sys.wait(1000)  -- 展示间隔，1 秒

    log.info("qmc5883p_demo", "切换量程为 30G（最宽量程，抗干扰最强）")
    exs_qmc5883p.set_range("30G")
    sys.wait(300)   -- 等待量程切换生效，300ms

    data = exs_qmc5883p.get_data()
    if data then
        log.info("qmc5883p_demo", string.format("30G 量程: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end

    -- 恢复默认量程
    exs_qmc5883p.set_range("8G")
    log.info("qmc5883p_demo", "---- [2/7] 完成 ----")
end

--------------------------------------------------------------
-- [3/7] 输出速率切换演示
-- - set_odr() 支持 10Hz / 50Hz / 100Hz / 200Hz
-- - ODR 越低功耗越低，越高响应越快
--------------------------------------------------------------
local function demo_odr_switch()
    log.info("qmc5883p_demo", "===== [3/7] 输出速率切换 =====")

    local odr_list = {10, 50, 100, 200}
    for _, odr in ipairs(odr_list) do
        log.info("qmc5883p_demo", string.format("设置输出速率为 %dHz", odr))
        exs_qmc5883p.set_odr(odr)
        sys.wait(500)   -- 等待速率配置生效，500ms

        local data = exs_qmc5883p.get_data()
        if data then
            log.info("qmc5883p_demo", string.format("%dHz 下: X=%.2f Y=%.2f Z=%.2f uT", odr, data.x, data.y, data.z))
        end
        sys.wait(500)   -- 展示间隔，500ms
    end

    exs_qmc5883p.set_odr(10)    -- 恢复默认 10Hz
    log.info("qmc5883p_demo", "---- [3/7] 完成 ----")
end

--------------------------------------------------------------
-- [4/7] 过采样/降采样配置演示
-- - set_osr(osr, osr2)：osr 为过采样率（8/4/2/1），osr2 为降采样率（1/2/4/8）
-- - 两者乘积最大 64，值越大噪声越低、功耗越高
--------------------------------------------------------------
local function demo_osr_config()
    log.info("qmc5883p_demo", "===== [4/7] 过采样/降采样配置 =====")

    log.info("qmc5883p_demo", "配置为最高滤波：OSR1=8（过采样 8 次）+ OSR2=8（降采样 8 次）")
    exs_qmc5883p.set_osr(8, 8)
    sys.wait(300)   -- 等待配置生效，300ms

    local data = exs_qmc5883p.get_data()
    if data then
        log.info("qmc5883p_demo", string.format("最高滤波: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end
    sys.wait(1000)  -- 展示间隔，1 秒

    log.info("qmc5883p_demo", "配置为最低功耗：OSR1=1 + OSR2=1")
    exs_qmc5883p.set_osr(1, 1)
    sys.wait(300)   -- 等待配置生效，300ms

    data = exs_qmc5883p.get_data()
    if data then
        log.info("qmc5883p_demo", string.format("最低功耗: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end

    -- 恢复默认配置
    exs_qmc5883p.set_osr(8, 8)
    log.info("qmc5883p_demo", "---- [4/7] 完成 ----")
end

--------------------------------------------------------------
-- [5/7] 软复位演示
-- - soft_reset() 复位芯片后自动重新应用当前配置，无需重新 setup()
--------------------------------------------------------------
local function demo_soft_reset()
    log.info("qmc5883p_demo", "===== [5/7] 软复位演示 =====")

    local result = exs_qmc5883p.soft_reset()
    if not result then
        log.error("qmc5883p_demo", "软复位失败")
        return false
    end
    log.info("qmc5883p_demo", "软复位完成，配置已恢复")
    sys.wait(300)   -- 等待复位后数据稳定，300ms

    local data = exs_qmc5883p.get_data()
    if data then
        log.info("qmc5883p_demo", string.format("复位后数据: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end
    log.info("qmc5883p_demo", "---- [5/7] 完成 ----")
    return true
end

--------------------------------------------------------------
-- [6/7] 芯片自检演示
-- - self_test() 利用芯片内置自检激励信号验证信号链路是否正常
-- - 返回自检前后三轴增量（单位 LSB），增量明显大于正常噪声表示信号链路正常
--------------------------------------------------------------
local function demo_self_test()
    log.info("qmc5883p_demo", "===== [6/7] 芯片自检演示 =====")

    local delta = exs_qmc5883p.self_test()
    if not delta then
        log.error("qmc5883p_demo", "芯片自检失败")
        return false
    end
    log.info("qmc5883p_demo", string.format("自检增量 dx=%d dy=%d dz=%d", delta.dx, delta.dy, delta.dz))
    log.info("qmc5883p_demo", "自检增量明显大于正常噪声表示信号链路正常")
    log.info("qmc5883p_demo", "---- [6/7] 完成 ----")
    return true
end

--------------------------------------------------------------
-- [7/7] 休眠唤醒与关闭
-- - sleep() 进入挂起模式（功耗约 22 μA），wakeup() 快速恢复，无需重新 setup()
-- - close() 关闭传感器，之后需重新 setup() 才能使用
--------------------------------------------------------------
local function demo_sleep_wakeup_close()
    log.info("qmc5883p_demo", "===== [7/7] 休眠唤醒与关闭 =====")

    log.info("qmc5883p_demo", "进入挂起模式（低功耗约 22 μA）")
    exs_qmc5883p.sleep()
    sys.wait(3000)  -- 挂起演示 3 秒

    log.info("qmc5883p_demo", "从挂起模式唤醒")
    exs_qmc5883p.wakeup()
    sys.wait(200)   -- 等待唤醒后数据稳定，200ms

    local data = exs_qmc5883p.get_data()
    if data then
        log.info("qmc5883p_demo", string.format("唤醒后数据: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end

    exs_qmc5883p.close()
    log.info("qmc5883p_demo", "---- [7/7] 完成 ----")
    return true
end

--------------------------------------------------------------
-- 主任务：按 [1/7]~[7/7] 顺序执行全部演示
--------------------------------------------------------------
local function qmc5883p_demo_task_func()
    log.info("qmc5883p_demo", "HELLO")
    sys.wait(1000)  -- 等待系统启动稳定，1 秒

    local ok = demo_init_and_read()
    if not ok then
        log.error("qmc5883p_demo", "初始化失败，演示终止")
        return
    end
    sys.wait(500)   -- 演示间隔，500ms

    demo_range_switch()
    sys.wait(500)   -- 演示间隔，500ms

    demo_odr_switch()
    sys.wait(500)   -- 演示间隔，500ms

    demo_osr_config()
    sys.wait(500)   -- 演示间隔，500ms

    ok = demo_soft_reset()
    if not ok then
        log.error("qmc5883p_demo", "软复位失败，演示终止")
        return
    end
    sys.wait(500)   -- 演示间隔，500ms

    ok = demo_self_test()
    if not ok then
        log.error("qmc5883p_demo", "自检失败，演示终止")
        return
    end
    sys.wait(500)   -- 演示间隔，500ms

    demo_sleep_wakeup_close()

    log.info("qmc5883p_demo", "===== [演示完毕] =====")
    log.info("qmc5883p_demo", "End")
end

-- 启动演示任务协程
sys.taskInit(qmc5883p_demo_task_func)
