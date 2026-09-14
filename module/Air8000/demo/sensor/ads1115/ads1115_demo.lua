--[[
@module  ads1115_demo
@summary ADS1115 16位ADC传感器演示模块，包含所有功能的演示用例
@version 2.0
@date    2026.08.24
@author  王城钧
@usage
本文件包含 ADS1115 的逐项功能演示。
通过 exs_ads1115 扩展库的 API 逐一演示数据读取、多通道扫描、比较器中断、PGA 增益切换等功能。
]]

-- 加载 exs_ads1115 扩展库
local exs_ads1115 = require "exs_ads1115"

-- ==================== 通信模式选择 ====================
-- 改 MODE 的值选择通信模式：
--   1 = 软件 I2C（任意 GPIO，接线最灵活）
--   2 = 硬件 I2C（占用 CPU 少，稳定可靠，推荐）
local MODE = 2

-- ALERT/RDY 中断引脚：ADS1115 模块 ALERT/RDY 接到核心板 GPIO22（按实际接线修改）
local ALERT_GPIO = 21

-- 中断消息 topic：GPIO 中断回调发布，主任务等待后读取数据清除锁存报警
local ALERT_TOPIC = "ADS1115_ALERT"

-- 按 MODE 组装初始化配置
local init_config
if MODE == 1 then
    -- 软件 I2C：SCL/SDA 用任意 GPIO（示例 GPIO31/GPIO30）
    -- 不传 addr：扩展库自动探测 0x48~0x4B，读 Config 校验命中即锁定
    init_config = {scl = 31, sda = 30, channel = 0, pga = 1, sps = 128, mode = 1, alert_pin = ALERT_GPIO}
elseif MODE == 2 then
    -- 硬件 I2C：i2c_id 为总线号
    init_config = {i2c_id = 0, channel = 0, pga = 1, sps = 128, mode = 1, alert_pin = ALERT_GPIO}
else
    log.error("ads1115_demo", "MODE 取值错误，应为 1/2")
    return
end

-- [1/4] 初始化与数据读取
local function demo_init_and_read()
    log.info("ads1115_demo", "===== [1/4] 初始化与数据读取 =====")

    local result = exs_ads1115.setup(init_config)
    if not result then
        log.error("ads1115_demo", "ADS1115 初始化失败，请检查接线")
        return false
    end

    log.info("ads1115_demo", "ADS1115 初始化成功，版本:", exs_ads1115.version())

    sys.wait(200)
    local data = exs_ads1115.get_data()
    if data then
        log.info("ads1115_demo", string.format("AIN0 = %.4f V (raw=%d)", data.voltage, data.raw))
    else
        log.error("ads1115_demo", "读取数据失败")
    end

    sys.wait(1000)

    for i = 1, 3 do
        sys.wait(500)
        local d = exs_ads1115.get_data()
        if d then
            log.info("ads1115_demo", string.format("第%d次读取: AIN0 = %.4f V (raw=%d)", i, d.voltage, d.raw))
        end
    end

    log.info("ads1115_demo", "---- [1/4] 完成 ----")
    return true
end

-- [2/4] 多通道扫描
local function demo_channel_scan()
    log.info("ads1115_demo", "===== [2/4] 多通道扫描 =====")

    for ch = 0, 3 do
        local ok = exs_ads1115.set_config({channel = ch})
        if not ok then
            log.warn("ads1115_demo", "通道", ch, "切换失败")
            return false
        end
        local data = exs_ads1115.get_data()
        if data then
            log.info("ads1115_demo", string.format("AIN%d = %.4f V (raw=%d)", ch, data.voltage, data.raw))
        end
        sys.wait(50)
    end

    -- 扫描结束显式切回 AIN0 通道，避免通道停留在 AIN3 影响后续步骤
    exs_ads1115.set_config({channel = 0})

    log.info("ads1115_demo", "---- [2/4] 完成 ----")
    return true
end

-- ALERT 中断回调：只发布消息，不直接做 I2C 操作（避免打断通信时序）
local function alert_cb_func()
    sys.publish(ALERT_TOPIC)
end

-- [3/4] 比较器中断报警
local function demo_comparator_int()
    log.info("ads1115_demo", "===== [3/4] 比较器中断报警 =====")

    -- 切回 AIN0 通道并切换到连续模式（多通道扫描后通道停在 AIN3，必须先切回）
    local ok = exs_ads1115.set_config({channel = 0, mode = 0})
    if not ok then
        return false
    end

    -- 窗口比较器（高于 3.0V 或低于 2.0V 都报警），1 次越界报警，锁存
    ok = exs_ads1115.set_comparator(1, 0, true)
    if not ok then
        return false
    end

    -- 阈值：低于 2.0V 或高于 3.0V 触发报警
    ok = exs_ads1115.set_threshold(2.0, 3.0)
    if not ok then
        return false
    end

    -- 注册 ALERT 引脚下降沿中断（覆盖 setup 时的输入模式）
    gpio.setup(ALERT_GPIO, alert_cb_func, gpio.PULLUP, gpio.FALLING)

    -- 读取当前电压并提示（帮助判断电压是否已在阈值外）
    local cur = exs_ads1115.get_data()
    if cur then
        log.info("ads1115_demo", string.format("当前 channel=%d, 电压 %.3f V（阈值 2.0V~3.0V）", cur.channel, cur.voltage))
        if cur.voltage > 3.0 or cur.voltage < 2.0 then
            log.info("ads1115_demo", "当前电压已在阈值外！请先调回 2.5V 左右，再越过阈值触发下降沿中断")
        end
    end
    log.info("ads1115_demo", "请调节输入电压越过 3.0V 或低于 2.0V，等待 ALERT 中断（30 秒内）...")

    -- 等待中断消息，同时每 500ms 轮询电压与 ALERT 电平辅助检测（总时长约 30 秒）
    -- 轮询检测不依赖 ALERT 下降沿：即使操作方式不产生下降沿，也能验证比较器逻辑是否正常
    local got = false
    for i = 1, 60 do
        -- 每 500ms 轮询一次电压与 ALERT 电平，实时观察比较器状态
        cur = exs_ads1115.get_data()
        if cur then
            local alert = exs_ads1115.get_alert()
            log.info("ads1115_demo", string.format("电压 %.3f V，ALERT=%s", cur.voltage, tostring(alert)))
            if cur.voltage > 3.0 or cur.voltage < 2.0 then
                -- 先检查 ALERT 中断消息，优先验证硬件中断链路
                if sys.waitUntil(ALERT_TOPIC, 200) then
                    log.warn("ads1115_demo", "收到 ALERT 中断：电压超阈值报警！")
                else
                    log.warn("ads1115_demo", string.format("轮询检测到电压越界！当前 AIN0 = %.3f V", cur.voltage))
                end
                got = true
                break
            end
        end
        -- 等待中断消息（500ms 超时，超时后继续轮询）
        if sys.waitUntil(ALERT_TOPIC, 500) then
            log.warn("ads1115_demo", "收到 ALERT 中断：电压超阈值报警！")
            got = true
            break
        end
    end

    if got then
        -- 中断刚结束，延迟 100ms 再读数据（避开 GPIO 中断打断 I2C 传输后的总线敏感期）
        sys.wait(100)
        -- 锁存模式下读取数据可清除报警（扩展库内置失败重试与总线重建）
        cur = exs_ads1115.get_data()
        if cur then
            log.info("ads1115_demo", string.format("当前电压 = %.3f V (raw=%d)", cur.voltage, cur.raw))
        else
            log.warn("ads1115_demo", "读取当前电压失败（扩展库已自动重试并重建 I2C 总线）")
        end
    else
        log.info("ads1115_demo", "30 秒内未触发报警（可调节输入电压验证中断功能）")
    end

    log.info("ads1115_demo", "---- [3/4] 完成 ----")
    return true
end

-- [4/4] PGA 增益切换演示
local function demo_pga_switch()
    log.info("ads1115_demo", "===== [4/4] PGA 增益切换演示 =====")

    -- 切回 AIN0 通道、单次模式（比较器演示后处于连续模式，此处恢复）
    exs_ads1115.set_config({channel = 0, mode = 1})

    log.info("ads1115_demo", "切换 PGA 为 1（满量程 ±4.096V，分辨率 125μV）")
    exs_ads1115.set_config({channel = 0, pga = 1})
    sys.wait(300)

    local data = exs_ads1115.get_data()
    if data then
        log.info("ads1115_demo", string.format("PGA=1 下: AIN0 = %.4f V (raw=%d)", data.voltage, data.raw))
    end

    sys.wait(1000)

    log.info("ads1115_demo", "切换 PGA 为 2（满量程 ±2.048V，分辨率 62.5μV，输入超过 ±2.048V 会钳位）")
    exs_ads1115.set_config({channel = 0, pga = 2})
    sys.wait(300)

    data = exs_ads1115.get_data()
    if data then
        log.info("ads1115_demo", string.format("PGA=2 下: AIN0 = %.4f V (raw=%d)", data.voltage, data.raw))
    end

    sys.wait(1000)

    -- 恢复默认 PGA=1
    log.info("ads1115_demo", "恢复 PGA 为 1（满量程 ±4.096V）")
    exs_ads1115.set_config({channel = 0, pga = 1})
    sys.wait(300)

    log.info("ads1115_demo", "---- [4/4] 完成 ----")
end

local function ads1115_demo_task_func()
    log.info("ads1115_demo", "HELLO")
    sys.wait(1000)

    local ok = demo_init_and_read()
    if not ok then
        log.error("ads1115_demo", "初始化失败，演示终止")
        return
    end

    sys.wait(500)
    demo_channel_scan()
    sys.wait(500)
    demo_comparator_int()
    sys.wait(500)
    demo_pga_switch()
    sys.wait(500)

    log.info("ads1115_demo", "===== [演示完毕] =====")
    exs_ads1115.close()
    log.info("ads1115_demo", "End")
end

sys.taskInit(ads1115_demo_task_func)
