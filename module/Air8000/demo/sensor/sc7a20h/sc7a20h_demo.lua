--[[
@module  sc7a20h_demo
@summary SC7A20H 三轴加速度传感器演示模块
@version 1.1
@date    2026.07.23
@author  江访
@usage
本文件包含 SC7A20H 的逐项功能演示。
通过 exs_sc7a20h 扩展库的 API 逐一演示数据读取、量程切换、输出速率切换、休眠唤醒等功能。
]]

local exs_sc7a20h = require "exs_sc7a20h"

local function sc7a20h_int1_cb(data)
    if data.dir then
        log.info("sc7a20h_demo", string.format("int1: 朝向=%s X=%.3f Y=%.3f Z=%.3f g", data.dir, data.x, data.y, data.z))
    else
        log.info("sc7a20h_demo", string.format("int1: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end
end

local function demo_init_and_read()
    log.info("sc7a20h_demo", "===== [1/4] 初始化与数据读取 =====")
    local result = exs_sc7a20h.setup("I2C", {
        scl = 1, sda = 2,
        powermode = "highres",
        enable_direction = "6d",
        int1 = { int_gpio = 17, activity = true, threshold_mg = 500, cb = sc7a20h_int1_cb },
    })
    if not result then
        log.error("sc7a20h_demo", "SC7A20H 初始化失败")
        return false
    end
    log.info("sc7a20h_demo", "SC7A20H 初始化成功，版本:", exs_sc7a20h.version())
    exs_sc7a20h.dump_regs()
    sys.wait(200)
    local data = exs_sc7a20h.get_data()
    if data then
        log.info("sc7a20h_demo", string.format("X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    else
        log.error("sc7a20h_demo", "读取数据失败")
    end
    sys.wait(1000)
    for i = 1, 3 do
        sys.wait(500)
        local d = exs_sc7a20h.get_data()
        if d then log.info("sc7a20h_demo", string.format("第%d次读取: X=%.3f Y=%.3f Z=%.3f g", i, d.x, d.y, d.z)) end
    end
    log.info("sc7a20h_demo", "---- [1/4] 完成 ----")
    return true
end

local function demo_range_switch()
    log.info("sc7a20h_demo", "===== [2/4] 量程切换演示 =====")
    log.info("sc7a20h_demo", "切换量程为 4g")
    exs_sc7a20h.set_range("4g")
    sys.wait(300)
    local data = exs_sc7a20h.get_data()
    if data then log.info("sc7a20h_demo", string.format("4g: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z)) end
    sys.wait(1000)
    log.info("sc7a20h_demo", "切换量程为 2g")
    exs_sc7a20h.set_range("2g")
    sys.wait(300)
    data = exs_sc7a20h.get_data()
    if data then log.info("sc7a20h_demo", string.format("2g: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z)) end
    sys.wait(1000)
    log.info("sc7a20h_demo", "---- [2/4] 完成 ----")
end

local function demo_odr_switch()
    log.info("sc7a20h_demo", "===== [3/4] 输出速率切换 =====")
    for _, odr in ipairs({25, 50, 100, 200}) do
        log.info("sc7a20h_demo", string.format("设置 %dHz", odr))
        exs_sc7a20h.set_odr(odr)
        sys.wait(500)
        local data = exs_sc7a20h.get_data()
        if data then log.info("sc7a20h_demo", string.format("%dHz: X=%.3f Y=%.3f Z=%.3f g", odr, data.x, data.y, data.z)) end
        sys.wait(500)
    end
    exs_sc7a20h.set_odr(100)
    log.info("sc7a20h_demo", "---- [3/4] 完成 ----")
end

local function demo_sleep_wakeup()
    log.info("sc7a20h_demo", "===== [4/4] 休眠与唤醒演示 =====")
    log.info("sc7a20h_demo", "进入 power-down 模式（低功耗）")
    exs_sc7a20h.sleep(); sys.wait(10000)
    sys.wait(500)
    log.info("sc7a20h_demo", "从 power-down 模式唤醒")
    exs_sc7a20h.wakeup()
    sys.wait(200)
    local data = exs_sc7a20h.get_data()
    if data then log.info("sc7a20h_demo", string.format("唤醒后数据: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z)) end
    log.info("sc7a20h_demo", "---- [4/4] 完成 ----")
end

local function task_func()
    log.info("sc7a20h_demo", "HELLO")
    sys.wait(1000)
    if not demo_init_and_read() then return end
    sys.wait(500)
    demo_range_switch()
    sys.wait(500)
    demo_odr_switch()
    sys.wait(500)
    demo_sleep_wakeup()
    sys.wait(500)
    log.info("sc7a20h_demo", "===== [演示完毕] =====")
    exs_sc7a20h.close()
    log.info("sc7a20h_demo", "End")
end
sys.taskInit(task_func)
