--[[
@module  bmp180_demo
@summary BMP180 数字气压传感器演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.07.23
@author  江访
@usage
本文件包含 BMP180 的逐项功能演示。
通过 exs_bmp180 扩展库的 API 逐一演示数据读取、过采样率切换、海拔高度计算、关闭传感器等功能。
]]

-- 加载 exs_bmp180 扩展库
local exs_bmp180 = require "exs_bmp180"

-- [1/4] 初始化与数据读取
local function demo_init_and_read()
    log.info("bmp180_demo", "===== [1/4] 初始化与数据读取 =====")

    -- 软件 I2C 模式初始化 BMP180 传感器
    local result = exs_bmp180.setup({
        scl = 31,
        sda = 30,
    })

    if not result then
        log.error("bmp180_demo", "BMP180 初始化失败，请检查接线")
        return false
    end

    log.info("bmp180_demo", "BMP180 初始化成功，版本:", exs_bmp180.version())

    -- 读取并显示温度和气压
    sys.wait(200)
    local data = exs_bmp180.get_data()
    if data then
        log.info("bmp180_demo", string.format("温度=%.1f°C 气压=%.2fhPa", data.temperature, data.pressure / 100))
    else
        log.error("bmp180_demo", "读取数据失败")
    end

    sys.wait(1000)

    -- 连续读取 3 次，观察数据变化
    for i = 1, 3 do
        sys.wait(2000)
        local d = exs_bmp180.get_data()
        if d then
            log.info("bmp180_demo", string.format("第%d次读取: 温度=%.1f°C 气压=%.1fPa", i, d.temperature, d.pressure))
        end
    end

    log.info("bmp180_demo", "---- [1/4] 完成 ----")
    return true
end

-- [2/4] 过采样率切换演示
local function demo_oss_switch()
    log.info("bmp180_demo", "===== [2/4] 过采样率切换演示 =====")

    local oss_list = {0, 1, 2, 3}
    for _, oss in ipairs(oss_list) do
        log.info("bmp180_demo", string.format("设置过采样率为 oss=%d", oss))
        exs_bmp180.set_oss(oss)
        sys.wait(100)

        local data = exs_bmp180.get_data()
        if data then
            log.info("bmp180_demo", string.format("oss=%d: 温度=%.1f°C 气压=%.2fhPa", oss, data.temperature, data.pressure / 100))
        end
        sys.wait(1000)
    end

    log.info("bmp180_demo", "---- [2/4] 完成 ----")
end

-- [3/4] 海拔高度测量
local function demo_altitude()
    log.info("bmp180_demo", "===== [3/4] 海拔高度测量 =====")

    local data = exs_bmp180.get_data()
    if data then
        local alt = exs_bmp180.get_altitude(data.pressure)
        log.info("bmp180_demo", string.format("温度=%.1f°C 气压=%.1fPa 海拔=%.1f米", data.temperature, data.pressure, alt))
    end

    log.info("bmp180_demo", "---- [3/4] 完成 ----")
end

-- [4/4] 关闭传感器
local function demo_close()
    log.info("bmp180_demo", "===== [4/4] 演示完毕 =====")
    log.info("bmp180_demo", "---- [4/4] 完成 ----")
end

-- 演示主函数（运行在协程中）
local function bmp180_demo_task_func()
    -- HELLO 开始
    log.info("bmp180_demo", "HELLO")
    sys.wait(1000)

    -- [1/4] 初始化与数据读取
    local ok = demo_init_and_read()
    if not ok then
        log.error("bmp180_demo", "初始化失败，演示终止")
        return
    end

    sys.wait(500)

    -- [2/4] 过采样率切换演示
    demo_oss_switch()
    sys.wait(500)

    -- [3/4] 海拔高度测量
    demo_altitude()
    sys.wait(500)

    -- [4/4] 关闭传感器
    demo_close()
    sys.wait(500)

    -- End
    log.info("bmp180_demo", "===== [演示完毕] =====")
    log.info("bmp180_demo", "End")
end

sys.taskInit(bmp180_demo_task_func)
