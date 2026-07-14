--[[
@module  qmc5883l_demo
@summary QMC5883L 三轴地磁传感器演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.07.14
@author  江访
@usage
本文件包含 QMC5883L 的逐项功能演示。
通过 exs_qmc5883l 扩展库的 API 逐一演示数据读取、量程切换、输出速率切换等功能。
注意：QMC5883L 片内温度传感器精度有限，本 demo 不包含读取温度数据演示。
]]

-- 加载 exs_qmc5883l 扩展库
local exs_qmc5883l = require "exs_qmc5883l"

-- [1/3] 初始化与数据读取
local function demo_init_and_read()
    log.info("qmc5883l_demo", "===== [1/3] 初始化与数据读取 =====")

    -- 初始化 QMC5883L 传感器（软件 I2C 模式，参照 TM1638 demo 引脚）
    -- 推荐使用软件 I2C：QMC5883L 在异常 I2C 通信后可能锁死 SDA 总线，
    -- 软件 I2C 可用 GPIO 直接脉冲 SCL 恢复，硬件 I2C 无法恢复锁死的总线
    local result = exs_qmc5883l.setup({
        scl = 31,
        sda = 30,
    })
    if not result then
        log.error("qmc5883l_demo", "QMC5883L 初始化失败，请检查接线")
        return false
    end

    log.info("qmc5883l_demo", "QMC5883L 初始化成功，版本:", exs_qmc5883l.version())

    -- 读取并显示磁场数据
    sys.wait(200)
    local data = exs_qmc5883l.get_data()
    if data then
        log.info("qmc5883l_demo", string.format("X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    else
        log.error("qmc5883l_demo", "读取数据失败")
    end

    sys.wait(1000)

    -- 连续读取 3 次，观察数据变化
    for i = 1, 3 do
        sys.wait(500)
        local d = exs_qmc5883l.get_data()
        if d then
            log.info("qmc5883l_demo", string.format("第%d次读取: X=%.2f Y=%.2f Z=%.2f uT", i, d.x, d.y, d.z))
        end
    end

    log.info("qmc5883l_demo", "---- [1/3] 完成 ----")
    return true
end

-- [2/3] 量程切换演示
local function demo_range_switch()
    log.info("qmc5883l_demo", "===== [2/3] 量程切换演示 =====")

    -- 切换为 ±2G 量程（高精度）
    log.info("qmc5883l_demo", "切换量程为 2G（高精度）")
    exs_qmc5883l.set_range("2G")
    sys.wait(300)

    local data = exs_qmc5883l.get_data()
    if data then
        log.info("qmc5883l_demo", string.format("2G 量程: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end

    sys.wait(1000)

    -- 切换回 ±8G 量程（宽范围）
    log.info("qmc5883l_demo", "切换量程为 8G（宽范围）")
    exs_qmc5883l.set_range("8G")
    sys.wait(300)

    data = exs_qmc5883l.get_data()
    if data then
        log.info("qmc5883l_demo", string.format("8G 量程: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end

    sys.wait(1000)

    log.info("qmc5883l_demo", "---- [2/3] 完成 ----")
end

-- [3/3] 输出速率切换
local function demo_odr_switch()
    log.info("qmc5883l_demo", "===== [3/3] 输出速率切换 =====")

    local odr_list = {10, 50, 100, 200}
    for _, odr in ipairs(odr_list) do
        log.info("qmc5883l_demo", string.format("设置输出速率为 %dHz", odr))
        exs_qmc5883l.set_odr(odr)
        sys.wait(500)

        local data = exs_qmc5883l.get_data()
        if data then
            log.info("qmc5883l_demo", string.format("%dHz 下: X=%.2f Y=%.2f Z=%.2f uT", odr, data.x, data.y, data.z))
        end
        sys.wait(500)
    end

    -- 恢复为 10Hz
    exs_qmc5883l.set_odr(10)
    log.info("qmc5883l_demo", "---- [3/3] 完成 ----")
end

-- 演示主函数（运行在协程中）
local function qmc5883l_demo_task_func()
    -- HELLO 开始
    log.info("qmc5883l_demo", "HELLO")
    sys.wait(1000)

    -- [1/3] 初始化与数据读取
    local ok = demo_init_and_read()
    if not ok then
        log.error("qmc5883l_demo", "初始化失败，演示终止")
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
    log.info("qmc5883l_demo", "===== [演示完毕] =====")
    log.info("qmc5883l_demo", "End")
end

sys.taskInit(qmc5883l_demo_task_func)
