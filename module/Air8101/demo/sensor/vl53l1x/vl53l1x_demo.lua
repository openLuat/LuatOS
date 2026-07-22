--[[
@module  vl53l1x_demo
@summary VL53L1X 飞行时间测距传感器演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.07.21
@author  江访
@usage
本文件包含 VL53L1X 的逐项功能演示。
通过 exs_vl53l1x 扩展库的 API 逐一演示标准测距、模式切换、中断读取、休眠唤醒、持续测距等功能。
]]

-- 加载 exs_vl53l1x 扩展库
local exs_vl53l1x = require "exs_vl53l1x"

-- [1/5] 标准测距演示
local function demo_standard_ranging()
    log.info("vl53l1x_demo", "===== [1/5] 标准测距 =====")

    -- 软件 I2C 模式：SCL=GPIO4, SDA=GPIO5（Air8101 接线）
    local result = exs_vl53l1x.setup({scl = 4, sda = 5})
    if not result then
        log.error("vl53l1x_demo", "初始化失败，请检查接线")
        return false
    end
    log.info("vl53l1x_demo", "VL53L1X 初始化成功，版本:", exs_vl53l1x.version())

    sys.wait(200)
    for i = 1, 5 do
        local data = exs_vl53l1x.get_data()
        if data then
            log.info("vl53l1x_demo", string.format("第%d次: 距离=%dmm 状态=%s stream=%d",
                i, data.distance, data.status_str, data.stream_count or 0))
        else
            log.error("vl53l1x_demo", "读取数据失败")
        end
        sys.wait(500)
    end

    exs_vl53l1x.close()
    log.info("vl53l1x_demo", "---- [1/5] 完成 ----")
    return true
end

-- [2/5] 测距模式切换
local function demo_range_mode()
    log.info("vl53l1x_demo", "===== [2/5] 测距模式切换 =====")

    -- short 模式（抗强光，约 1.36m）
    log.info("vl53l1x_demo", "切换 short 模式（抗强光）")
    local ok = exs_vl53l1x.setup({scl = 4, sda = 5, range_mode = "short"})
    if not ok then return end
    sys.wait(200)
    local data = exs_vl53l1x.get_data()
    if data then
        log.info("vl53l1x_demo", string.format("short 模式: 距离=%dmm 状态=%s", data.distance, data.status_str))
    end
    exs_vl53l1x.close()

    -- long 模式（远距离，约 3.6m）
    log.info("vl53l1x_demo", "切换 long 模式（远距离）")
    ok = exs_vl53l1x.setup({scl = 4, sda = 5, range_mode = "long"})
    if not ok then return end
    sys.wait(200)
    data = exs_vl53l1x.get_data()
    if data then
        log.info("vl53l1x_demo", string.format("long 模式: 距离=%dmm 状态=%s", data.distance, data.status_str))
    end
    exs_vl53l1x.close()

    log.info("vl53l1x_demo", "---- [2/5] 完成 ----")
end

-- [3/5] 休眠与唤醒
local function demo_sleep_wakeup()
    log.info("vl53l1x_demo", "===== [4/5] 休眠与唤醒演示 =====")

    local result = exs_vl53l1x.setup({scl = 4, sda = 5})
    if not result then return end
    sys.wait(200)

    local data = exs_vl53l1x.get_data()
    if data then
        log.info("vl53l1x_demo", string.format("休眠前: 距离=%dmm 状态=%s", data.distance, data.status_str))
    end

    log.info("vl53l1x_demo", "进入软件待机模式")
    exs_vl53l1x.sleep()
    sys.wait(3000)

    log.info("vl53l1x_demo", "从软件待机模式唤醒")
    exs_vl53l1x.wakeup()
    sys.wait(200)

    data = exs_vl53l1x.get_data()
    if data then
        log.info("vl53l1x_demo", string.format("唤醒后: 距离=%dmm 状态=%s", data.distance, data.status_str))
    end

    exs_vl53l1x.close()
    log.info("vl53l1x_demo", "---- [4/5] 完成 ----")
end

-- [5/5] 持续测距演示
local function demo_continuous_ranging()
    log.info("vl53l1x_demo", "===== [5/5] 持续测距演示 =====")

    local result = exs_vl53l1x.setup({scl = 4, sda = 5})
    if not result then return end

    log.info("vl53l1x_demo", "每隔 1 秒读取一次距离数据，共 5 次")
    for i = 1, 5 do
        sys.wait(1000)
        local data = exs_vl53l1x.get_data()
        if data then
            log.info("vl53l1x_demo", string.format("持续测距[%d]: 距离=%dmm 状态=%s",
                i, data.distance, data.status_str))
        else
            log.warn("vl53l1x_demo", string.format("持续测距[%d] 读取失败", i))
        end
    end

    exs_vl53l1x.close()
    log.info("vl53l1x_demo", "---- [5/5] 完成 ----")
end

local function vl53l1x_demo_task_func()
    log.info("vl53l1x_demo", "HELLO")
    sys.wait(1000)

    local ok = demo_standard_ranging()
    if not ok then return end
    sys.wait(500)

    demo_range_mode()
    sys.wait(500)

    demo_sleep_wakeup()
    sys.wait(500)

    demo_continuous_ranging()
    sys.wait(500)

    log.info("vl53l1x_demo", "===== [演示完毕] =====")
end

sys.taskInit(vl53l1x_demo_task_func)
