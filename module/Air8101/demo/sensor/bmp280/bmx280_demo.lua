--[[
@module  bmp280_demo
@summary BMP280 数字气压传感器演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.07.23
@author  江访
@usage
本文件包含 BMP280 的逐项功能演示。
通过 exs_bmx280 扩展库的 API 逐一演示数据读取、IIR 滤波切换、海拔计算等功能。
]]

local exs_bmx280 = require "exs_bmx280"

-- [1/4] 初始化与数据读取
local function demo_init_and_read()
    log.info("bmp280_demo", "===== [1/4] 初始化与数据读取 =====")

    -- BMP280 使用软件 I2C 模式初始化，开启 IIR 滤波
    -- 注意：BMP280/BME280 使用 exs_bmx280 扩展库，与 BMP180 的 exs_bmp180 不同
    -- BMP180 返回气压单位为 Pa，BMP280 返回气压单位为 hPa，使用时不需换算
    local result = exs_bmx280.setup("I2C", {
        scl = 4,
        sda = 5,
        filter = 4,         -- 16 次采样平均，数据更平滑
    })

    if not result then
        log.error("bmp280_demo", "BMP280 初始化失败，请检查接线")
        return false
    end
    log.info("bmp280_demo", "BMP280 初始化成功，版本:", exs_bmx280.version())

    -- 等待传感器稳定，数据手册推荐 200ms
    sys.wait(200)
    local data = exs_bmx280.get_data()
    if data then
        log.info("bmp280_demo", string.format("温度=%.2f°C 气压=%.2fhPa", data.temperature, data.pressure))
    else
        log.error("bmp280_demo", "读取数据失败")
    end
    sys.wait(1000)                          -- 稳定后等待 1 秒进入连续读取

    -- 连续读取 3 次，观察数据变化
    for i = 1, 3 do
        sys.wait(2000)                      -- 每次读取间隔 2 秒
        local d = exs_bmx280.get_data()
        if d then
            log.info("bmp280_demo", string.format("第%d次读取: 温度=%.2f°C 气压=%.1fhPa", i, d.temperature, d.pressure))
        end
    end
    log.info("bmp280_demo", "---- [1/4] 完成 ----")
    return true
end

-- [2/4] IIR 滤波器切换演示
local function demo_filter_switch()
    log.info("bmp280_demo", "===== [2/4] IIR 滤波器切换演示 =====")

    -- 依次切换 filter=0/1/2/3/4，观察数据变化
    local filter_list = { 0, 1, 2, 3, 4 }
    for _, f in ipairs(filter_list) do
        log.info("bmp280_demo", string.format("设置滤波器 filter=%d", f))
        exs_bmx280.set_filter(f)
        sys.wait(100)                       -- 等待滤波器生效

        local data = exs_bmx280.get_data()
        if data then
            log.info("bmp280_demo", string.format("filter=%d: 温度=%.2f°C 气压=%.2fhPa", f, data.temperature, data.pressure))
        end
        sys.wait(1000)                      -- 每档滤波器显示间隔 1 秒
    end
    log.info("bmp280_demo", "---- [2/4] 完成 ----")
end

-- [3/4] 海拔高度测量
local function demo_altitude()
    log.info("bmp280_demo", "===== [3/4] 海拔高度测量 =====")

    local data = exs_bmx280.get_data()
    if data then
        local alt = exs_bmx280.get_altitude(data.pressure)
        log.info("bmp280_demo", string.format("温度=%.2f°C 气压=%.1fhPa 海拔=%.1f米", data.temperature, data.pressure, alt))
    end
    log.info("bmp280_demo", "---- [3/4] 完成 ----")
end

-- [4/4] 关闭传感器
local function demo_close()
    log.info("bmp280_demo", "===== [4/4] 关闭传感器 =====")
    exs_bmx280.close()
    log.info("bmp280_demo", "---- [4/4] 完成 ----")
end

local function bmp280_demo_task_func()
    log.info("bmp280_demo", "HELLO")
    sys.wait(1000)                          -- 启动后等待 1 秒再开始演示

    local ok = demo_init_and_read()
    if not ok then
        log.error("bmp280_demo", "初始化失败，演示终止")
        return
    end
    sys.wait(500)                           -- 每项演示间隔 500ms

    demo_filter_switch()
    sys.wait(500)                           -- 每项演示间隔 500ms

    demo_altitude()
    sys.wait(500)                           -- 每项演示间隔 500ms

    demo_close()
    sys.wait(500)                           -- 关闭后等待 500ms 再结束

    log.info("bmp280_demo", "===== [演示完毕] =====")
    log.info("bmp280_demo", "End")
end

sys.taskInit(bmp280_demo_task_func)
