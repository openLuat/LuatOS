--[[
@module  lis2dh12_demo
@summary LIS2DH12 三轴加速度传感器演示模块，包含所有功能的演示用例
@version 2.0
@date    2026.07.17
@author  江访
@usage
本文件包含 LIS2DH12 的逐项功能演示。
通过 exs_lis2dh12 扩展库的 API 逐一演示数据读取、量程切换、输出速率切换、温度读取、休眠唤醒等功能。
]]

local exs_lis2dh12 = require "exs_lis2dh12"

local function lis2dh12_int1_cb(data)
    if data.dir then
        log.info("lis2dh12_demo", string.format("int1: 朝向=%s X=%.3f Y=%.3f Z=%.3f g", data.dir, data.x, data.y, data.z))
    else
        log.info("lis2dh12_demo", string.format("int1: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end
end

-- [1/5] 初始化与数据读取
local function demo_init_and_read()
    log.info("lis2dh12_demo", "===== [1/5] 初始化与数据读取 =====")
    local result = exs_lis2dh12.setup("I2C", {
        scl = 4,
        sda = 5,
        powermode = "highres",
        enable_direction = "6d",
        int1 = { int_gpio = 3, tap = true, direction = true, cb = lis2dh12_int1_cb },
    })

    if not result then
        log.error("lis2dh12_demo", "LIS2DH12 初始化失败，请检查接线")
        return false
    end
    log.info("lis2dh12_demo", "LIS2DH12 初始化成功，版本:", exs_lis2dh12.version())
    exs_lis2dh12.dump_regs()

    sys.wait(200)
    local data = exs_lis2dh12.get_data()
    if data then
        log.info("lis2dh12_demo", string.format("X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    else
        log.error("lis2dh12_demo", "读取数据失败")
    end
    sys.wait(1000)

    for i = 1, 3 do
        sys.wait(500)
        local d = exs_lis2dh12.get_data()
        if d then
            log.info("lis2dh12_demo", string.format("第%d次读取: X=%.3f Y=%.3f Z=%.3f g", i, d.x, d.y, d.z))
        end
    end
    log.info("lis2dh12_demo", "---- [1/5] 完成 ----")
    return true
end

-- [2/5] 量程切换演示
local function demo_range_switch()
    log.info("lis2dh12_demo", "===== [2/5] 量程切换演示 =====")
    log.info("lis2dh12_demo", "切换量程为 4g")
    exs_lis2dh12.set_range("4g")
    sys.wait(300)
    local data = exs_lis2dh12.get_data()
    if data then
        log.info("lis2dh12_demo", string.format("4g 量程: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end
    sys.wait(1000)

    log.info("lis2dh12_demo", "切换量程为 2g（高精度）")
    exs_lis2dh12.set_range("2g")
    sys.wait(300)
    data = exs_lis2dh12.get_data()
    if data then
        log.info("lis2dh12_demo", string.format("2g 量程: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end
    sys.wait(1000)
    log.info("lis2dh12_demo", "---- [2/5] 完成 ----")
end

-- [3/5] 输出速率切换
local function demo_odr_switch()
    log.info("lis2dh12_demo", "===== [3/5] 输出速率切换 =====")
    local odr_list = { 25, 50, 100, 200 }
    for _, odr in ipairs(odr_list) do
        log.info("lis2dh12_demo", string.format("设置输出速率为 %dHz", odr))
        exs_lis2dh12.set_odr(odr)
        sys.wait(500)
        local data = exs_lis2dh12.get_data()
        if data then
            log.info("lis2dh12_demo", string.format("%dHz 下: X=%.3f Y=%.3f Z=%.3f g", odr, data.x, data.y, data.z))
        end
        sys.wait(500)
    end
    exs_lis2dh12.set_odr(100)
    log.info("lis2dh12_demo", "---- [3/5] 完成 ----")
end

-- [4/5] 温度读取演示
local function demo_temp_read()
    log.info("lis2dh12_demo", "===== [4/5] 温度读取演示 =====")
    log.info("lis2dh12_demo", "使能温度传感器")
    exs_lis2dh12.enable_temp(true)
    sys.wait(200)
    local temp = exs_lis2dh12.get_temp()
    if temp then
        log.info("lis2dh12_demo", string.format("芯片温度: %.1f °C", temp))
    else
        log.error("lis2dh12_demo", "读取温度失败")
    end
    exs_lis2dh12.enable_temp(false)
    log.info("lis2dh12_demo", "---- [4/5] 完成 ----")
end

-- [5/5] 休眠与唤醒演示
local function demo_sleep_wakeup()
    log.info("lis2dh12_demo", "===== [5/5] 休眠与唤醒演示 =====")
    log.info("lis2dh12_demo", "进入 power-down 模式（低功耗）")
    exs_lis2dh12.sleep(); sys.wait(10000)
    sys.wait(500)
    log.info("lis2dh12_demo", "从 power-down 模式唤醒")
    exs_lis2dh12.wakeup()
    sys.wait(200)
    local data = exs_lis2dh12.get_data()
    if data then
        log.info("lis2dh12_demo", string.format("唤醒后数据: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end
    log.info("lis2dh12_demo", "---- [5/5] 完成 ----")
end

local function lis2dh12_demo_task_func()
    log.info("lis2dh12_demo", "HELLO")
    sys.wait(1000)
    local ok = demo_init_and_read()
    if not ok then return end
    sys.wait(500)
    demo_range_switch()
    sys.wait(500)
    demo_odr_switch()
    sys.wait(500)
    demo_temp_read()
    sys.wait(500)
    demo_sleep_wakeup()
    sys.wait(500)
    log.info("lis2dh12_demo", "===== [演示完毕] =====")
    exs_lis2dh12.close()
    log.info("lis2dh12_demo", "End")
end

sys.taskInit(lis2dh12_demo_task_func)
