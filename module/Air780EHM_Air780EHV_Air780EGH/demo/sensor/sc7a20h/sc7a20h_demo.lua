--[[
@module  sc7a20h_demo
@summary SC7A20H 三轴加速度传感器演示模块，包含所有功能的演示用例
@version 1.1
@date    2026.07.23
@author  江访
@usage
本文件包含 SC7A20H 的逐项功能演示。
通过 exs_sc7a20h 扩展库的 API 逐一演示数据读取、量程切换、输出速率切换、休眠唤醒等功能。
注意：SC7A20H 片内温度传感器精度有限，本 demo 不包含读取温度数据演示。
]]

-- 加载 exs_sc7a20h 扩展库
local exs_sc7a20h = require "exs_sc7a20h"

-- int1中断回调函数（需定义在 setup 之前）
local function sc7a20h_int1_cb(data)
    if data.dir then
        log.info("sc7a20h_demo", string.format("int1: 朝向=%s X=%.3f Y=%.3f Z=%.3f g", data.dir, data.x, data.y, data.z))
    else
        log.info("sc7a20h_demo", string.format("int1: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end
end

-- [1/4] 初始化与数据读取
local function demo_init_and_read()
    log.info("sc7a20h_demo", "===== [1/4] 初始化与数据读取 =====")

    -- 初始化 SC7A20H 传感器（软件 I2C 模式）
    -- 推荐使用软件 I2C：SC7A20H 在异常 I2C 通信后可能锁死 SDA 总线，
    -- 软件 I2C 可用 GPIO 直接脉冲 SCL 恢复，硬件 I2C 无法恢复锁死的总线
    local result = exs_sc7a20h.setup("I2C", {
        scl = 31,
        sda = 30,
        powermode = "highres",
        enable_direction = "6d",
        int1 = { int_gpio = 29, activity = true, threshold_mg = 500, cb = sc7a20h_int1_cb },
    })
    if not result then
        log.error("sc7a20h_demo", "SC7A20H 初始化失败，请检查接线")
        return false
    end

    log.info("sc7a20h_demo", "SC7A20H 初始化成功，版本:", exs_sc7a20h.version())
    exs_sc7a20h.dump_regs()

    -- 读取并显示加速度数据
    sys.wait(200)
    local data = exs_sc7a20h.get_data()
    if data then
        log.info("sc7a20h_demo", string.format("X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    else
        log.error("sc7a20h_demo", "读取数据失败")
    end

    sys.wait(1000)

    -- 连续读取 3 次，观察数据变化
    for i = 1, 3 do
        sys.wait(500)
        local d = exs_sc7a20h.get_data()
        if d then
            log.info("sc7a20h_demo", string.format("第%d次读取: X=%.3f Y=%.3f Z=%.3f g", i, d.x, d.y, d.z))
        end
    end

    log.info("sc7a20h_demo", "---- [1/4] 完成 ----")
    return true
end

-- [2/4] 量程切换演示
local function demo_range_switch()
    log.info("sc7a20h_demo", "===== [2/4] 量程切换演示 =====")

    -- 切换为 ±4g 量程（宽范围）
    log.info("sc7a20h_demo", "切换量程为 4g")
    exs_sc7a20h.set_range("4g")
    sys.wait(300)

    local data = exs_sc7a20h.get_data()
    if data then
        log.info("sc7a20h_demo", string.format("4g 量程: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end

    sys.wait(1000)

    -- 切换为 ±2g 量程（高精度）
    log.info("sc7a20h_demo", "切换量程为 2g（高精度）")
    exs_sc7a20h.set_range("2g")
    sys.wait(300)

    data = exs_sc7a20h.get_data()
    if data then
        log.info("sc7a20h_demo", string.format("2g 量程: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end

    sys.wait(1000)

    log.info("sc7a20h_demo", "---- [2/4] 完成 ----")
end

-- [3/4] 输出速率切换
local function demo_odr_switch()
    log.info("sc7a20h_demo", "===== [3/4] 输出速率切换 =====")

    local odr_list = {25, 50, 100, 200}
    for _, odr in ipairs(odr_list) do
        log.info("sc7a20h_demo", string.format("设置输出速率为 %dHz", odr))
        exs_sc7a20h.set_odr(odr)
        sys.wait(500)

        local data = exs_sc7a20h.get_data()
        if data then
            log.info("sc7a20h_demo", string.format("%dHz 下: X=%.3f Y=%.3f Z=%.3f g", odr, data.x, data.y, data.z))
        end
        sys.wait(500)
    end

    -- 恢复为 100Hz
    exs_sc7a20h.set_odr(100)
    log.info("sc7a20h_demo", "---- [3/4] 完成 ----")
end

-- [4/4] 休眠与唤醒演示
local function demo_sleep_wakeup()
    log.info("sc7a20h_demo", "===== [4/4] 休眠与唤醒演示 =====")

    log.info("sc7a20h_demo", "进入 power-down 模式（低功耗）")
    exs_sc7a20h.sleep(); sys.wait(10000)
    sys.wait(500)

    log.info("sc7a20h_demo", "从 power-down 模式唤醒")
    exs_sc7a20h.wakeup()
    sys.wait(200)

    local data = exs_sc7a20h.get_data()
    if data then
        log.info("sc7a20h_demo", string.format("唤醒后数据: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end

    log.info("sc7a20h_demo", "---- [4/4] 完成 ----")
end

-- 演示主函数（运行在协程中）
local function sc7a20h_demo_task_func()
    -- HELLO 开始
    log.info("sc7a20h_demo", "HELLO")
    sys.wait(1000)

    -- [1/4] 初始化与数据读取
    local ok = demo_init_and_read()
    if not ok then
        log.error("sc7a20h_demo", "初始化失败，演示终止")
        return
    end

    sys.wait(500)

    -- [2/4] 量程切换演示
    demo_range_switch()
    sys.wait(500)

    -- [3/4] 输出速率切换
    demo_odr_switch()
    sys.wait(500)

    -- [4/4] 休眠与唤醒演示
    demo_sleep_wakeup()
    sys.wait(500)

    -- End
    log.info("sc7a20h_demo", "===== [演示完毕] =====")
    exs_sc7a20h.close()
    log.info("sc7a20h_demo", "End")
end

sys.taskInit(sc7a20h_demo_task_func)
