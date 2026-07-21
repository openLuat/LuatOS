--[[
@module  qmc5883l_demo
@summary QMC5883L 三轴地磁传感器演示模块，包含所有功能的演示用例
@version 2.0
@date    2026.07.17
@author  江访
@usage
本文件包含 QMC5883L 的逐项功能演示。
通过 exs_qmc5883l 扩展库的 API 逐一演示数据读取、量程切换、输出速率切换、休眠唤醒等功能。
]]

local exs_qmc5883l = require "exs_qmc5883l"

-- [1/4] 初始化与数据读取
local function demo_init_and_read()
    log.info("qmc5883l_demo", "===== [1/4] 初始化与数据读取 =====")

    local result = exs_qmc5883l.setup({
        scl = 31,
        sda = 30,
    })
    if not result then
        log.error("qmc5883l_demo", "QMC5883L 初始化失败，请检查接线")
        return false
    end

    log.info("qmc5883l_demo", "QMC5883L 初始化成功，版本:", exs_qmc5883l.version())

    sys.wait(200)
    local data = exs_qmc5883l.get_data()
    if data then
        log.info("qmc5883l_demo", string.format("X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    else
        log.error("qmc5883l_demo", "读取数据失败")
    end

    sys.wait(1000)

    for i = 1, 3 do
        sys.wait(500)
        local d = exs_qmc5883l.get_data()
        if d then
            log.info("qmc5883l_demo", string.format("第%d次读取: X=%.2f Y=%.2f Z=%.2f uT", i, d.x, d.y, d.z))
        end
    end

    log.info("qmc5883l_demo", "---- [1/4] 完成 ----")
    return true
end

-- [2/4] 量程切换演示
local function demo_range_switch()
    log.info("qmc5883l_demo", "===== [2/4] 量程切换演示 =====")

    log.info("qmc5883l_demo", "切换量程为 2G（高精度）")
    exs_qmc5883l.set_range("2G")
    sys.wait(300)

    local data = exs_qmc5883l.get_data()
    if data then
        log.info("qmc5883l_demo", string.format("2G 量程: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end
    sys.wait(1000)

    log.info("qmc5883l_demo", "切换量程为 8G（宽范围）")
    exs_qmc5883l.set_range("8G")
    sys.wait(300)

    data = exs_qmc5883l.get_data()
    if data then
        log.info("qmc5883l_demo", string.format("8G 量程: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end
    sys.wait(1000)

    log.info("qmc5883l_demo", "---- [2/4] 完成 ----")
end

-- [3/4] 输出速率切换
local function demo_odr_switch()
    log.info("qmc5883l_demo", "===== [3/4] 输出速率切换 =====")

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

    exs_qmc5883l.set_odr(10)
    log.info("qmc5883l_demo", "---- [3/4] 完成 ----")
end

-- [4/4] 休眠与唤醒演示
local function demo_sleep_wakeup()
    log.info("qmc5883l_demo", "===== [4/4] 休眠与唤醒演示 =====")

    log.info("qmc5883l_demo", "进入待机模式（低功耗）")
    exs_qmc5883l.sleep(); sys.wait(10000)
    sys.wait(500)

    log.info("qmc5883l_demo", "从待机模式唤醒")
    exs_qmc5883l.wakeup()
    sys.wait(200)

    local data = exs_qmc5883l.get_data()
    if data then
        log.info("qmc5883l_demo", string.format("唤醒后数据: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z))
    end

    log.info("qmc5883l_demo", "---- [4/4] 完成 ----")
end

local function qmc5883l_demo_task_func()
    log.info("qmc5883l_demo", "HELLO")
    sys.wait(1000)

    local ok = demo_init_and_read()
    if not ok then
        log.error("qmc5883l_demo", "初始化失败，演示终止")
        return
    end
    sys.wait(500)

    demo_range_switch()
    sys.wait(500)

    demo_odr_switch()
    sys.wait(500)

    demo_sleep_wakeup()
    sys.wait(500)

    log.info("qmc5883l_demo", "===== [演示完毕] =====")
    exs_qmc5883l.close()
    log.info("qmc5883l_demo", "End")
end

sys.taskInit(qmc5883l_demo_task_func)
