--[[
@module  qmc5883l_demo
@summary QMC5883L 三轴地磁传感器演示模块
@version 1.0
@date    2026.07.14
@author  江访
]]

local exs_qmc5883l = require "exs_qmc5883l"

local function demo_init_and_read()
    log.info("qmc5883l_demo", "===== [1/3] 初始化与数据读取 =====")
    local result = exs_qmc5883l.setup({scl = 1, sda = 2})
    if not result then
        log.error("qmc5883l_demo", "QMC5883L 初始化失败")
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
    log.info("qmc5883l_demo", "---- [1/3] 完成 ----")
    return true
end

local function demo_range_switch()
    log.info("qmc5883l_demo", "===== [2/3] 量程切换演示 =====")
    log.info("qmc5883l_demo", "切换量程为 2G")
    exs_qmc5883l.set_range("2G")
    sys.wait(300)
    local data = exs_qmc5883l.get_data()
    if data then log.info("qmc5883l_demo", string.format("2G: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z)) end
    sys.wait(1000)
    log.info("qmc5883l_demo", "切换量程为 8G")
    exs_qmc5883l.set_range("8G")
    sys.wait(300)
    data = exs_qmc5883l.get_data()
    if data then log.info("qmc5883l_demo", string.format("8G: X=%.2f Y=%.2f Z=%.2f uT", data.x, data.y, data.z)) end
    sys.wait(1000)
    log.info("qmc5883l_demo", "---- [2/3] 完成 ----")
end

local function demo_odr_switch()
    log.info("qmc5883l_demo", "===== [3/3] 输出速率切换 =====")
    for _, odr in ipairs({10, 50, 100, 200}) do
        log.info("qmc5883l_demo", string.format("设置 %dHz", odr))
        exs_qmc5883l.set_odr(odr)
        sys.wait(500)
        local data = exs_qmc5883l.get_data()
        if data then log.info("qmc5883l_demo", string.format("%dHz: X=%.2f Y=%.2f Z=%.2f uT", odr, data.x, data.y, data.z)) end
        sys.wait(500)
    end
    exs_qmc5883l.set_odr(10)
    log.info("qmc5883l_demo", "---- [3/3] 完成 ----")
end

local function task_func()
    log.info("qmc5883l_demo", "HELLO")
    sys.wait(1000)
    if not demo_init_and_read() then return end
    sys.wait(500)
    demo_range_switch()
    sys.wait(500)
    demo_odr_switch()
    sys.wait(500)
    log.info("qmc5883l_demo", "End")
end
sys.taskInit(task_func)
