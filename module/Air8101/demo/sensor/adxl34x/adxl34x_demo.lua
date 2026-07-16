--[[
@module  adxl34x_demo
@summary ADXL345/ADXL346 三轴加速度传感器演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.07.14
@author  江访
@usage
本文件包含 ADXL345/ADXL346 的逐项功能演示。
通过 exs_adxl34x 扩展库的 API 逐一演示数据读取、量程切换、输出速率切换等功能。
]]

-- 加载 exs_adxl34x 扩展库
local exs_adxl34x = require "exs_adxl34x"

-- int1中断回调函数（需定义在 setup 之前）
local function adxl34x_int1_cb(data)
    log.info("adxl34x_demo", string.format("int1: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
end

-- [1/3] 初始化与数据读取
local function demo_init_and_read()
    log.info("adxl34x_demo", "===== [1/3] 初始化与数据读取 =====")

    -- 软件 I2C 模式初始化 ADXL345/ADXL346 传感器，配置 int1 数据就绪中断
    -- 使用 data_ready，100Hz ODR 下每秒触发 100 次
    -- 使用 tap 模式初始化，检测到敲击时触发（默认阈值 2g）
    local result = exs_adxl34x.setup("I2C", {
        scl = 4,
        sda = 5,
        int1 = { int_gpio = 3, tap = true, cb = adxl34x_int1_cb },
    })

    if not result then
        log.error("adxl34x_demo", "ADXL345/ADXL346 初始化失败，请检查接线")
        return false
    end

    log.info("adxl34x_demo", "ADXL345/ADXL346 初始化成功，版本:", exs_adxl34x.version())

    -- 读取并显示加速度数据
    sys.wait(200)
    local data = exs_adxl34x.get_data()
    if data then
        log.info("adxl34x_demo", string.format("X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    else
        log.error("adxl34x_demo", "读取数据失败")
    end

    sys.wait(1000)

    -- 连续读取 3 次，观察数据变化
    for i = 1, 3 do
        sys.wait(500)
        local d = exs_adxl34x.get_data()
        if d then
            log.info("adxl34x_demo", string.format("第%d次读取: X=%.3f Y=%.3f Z=%.3f g", i, d.x, d.y, d.z))
        end
    end

    log.info("adxl34x_demo", "---- [1/3] 完成 ----")
    return true
end

-- [2/3] 量程切换演示
local function demo_range_switch()
    log.info("adxl34x_demo", "===== [2/3] 量程切换演示 =====")

    -- 切换为 ±4g 量程
    log.info("adxl34x_demo", "切换量程为 4g")
    exs_adxl34x.set_range("4g")
    sys.wait(300)

    local data = exs_adxl34x.get_data()
    if data then
        log.info("adxl34x_demo", string.format("4g 量程: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end

    sys.wait(1000)

    -- 切换回 ±2g 量程（高精度）
    log.info("adxl34x_demo", "切换量程为 2g（高精度）")
    exs_adxl34x.set_range("2g")
    sys.wait(300)

    data = exs_adxl34x.get_data()
    if data then
        log.info("adxl34x_demo", string.format("2g 量程: X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end

    sys.wait(1000)

    log.info("adxl34x_demo", "---- [2/3] 完成 ----")
end

-- [3/3] 输出速率切换
local function demo_odr_switch()
    log.info("adxl34x_demo", "===== [3/3] 输出速率切换 =====")

    local odr_list = { 25, 50, 100, 200 }
    for _, odr in ipairs(odr_list) do
        log.info("adxl34x_demo", string.format("设置输出速率为 %dHz", odr))
        exs_adxl34x.set_odr(odr)
        sys.wait(500)

        local data = exs_adxl34x.get_data()
        if data then
            log.info("adxl34x_demo", string.format("%dHz 下: X=%.3f Y=%.3f Z=%.3f g", odr, data.x, data.y, data.z))
        end
        sys.wait(500)
    end

    -- 恢复为 100Hz
    exs_adxl34x.set_odr(100)
    log.info("adxl34x_demo", "---- [3/3] 完成 ----")
end

-- 演示主函数（运行在协程中）
local function adxl34x_demo_task_func()
    -- HELLO 开始
    log.info("adxl34x_demo", "HELLO")
    sys.wait(1000)

    -- [1/3] 初始化与数据读取
    local ok = demo_init_and_read()
    if not ok then
        log.error("adxl34x_demo", "初始化失败，演示终止")
        return
    end

    sys.wait(500)

    -- [2/3] 量程切换演示
    demo_range_switch()
    sys.wait(500)

    -- [3/3] 输出速率切换
    demo_odr_switch()
    sys.wait(500)

    -- End
    log.info("adxl34x_demo", "===== [演示完毕] =====")
    log.info("adxl34x_demo", "End")
end

sys.taskInit(adxl34x_demo_task_func)
