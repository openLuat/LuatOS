--[[
@module  tsl2561_demo
@summary TSL2561 数字环境光传感器 Demo
@version 1.0
@date    2026.08.26
@author  沈园园
@usage
本文件为 exs_tsl2561 扩展库的演示模块，按顺序演示以下 4 项功能：
HELLO→[1/4]→[2/4]→[3/4]→[4/4]→End
1、基础读取演示（[1/4]）- 默认配置（1x 增益 + 402ms 积分），读取 CH0/CH1 原始值和 lux，共 5 次
2、积分时间切换演示（[2/4]）- 13.7ms / 101ms / 402ms 三种积分时间切换，对比 lux 读数
3、增益切换演示（[3/4]）- 1x / 16x 增益切换，对比 lux 读数
4、中断与电源管理演示（[4/4]）- 阈值中断设置/清除、手动积分、断电/上电/复位演示

本文件没有对外接口，直接在 main.lua 中 require "tsl2561_demo" 就可以加载运行；
注意：exs_tsl2561 内部会执行系统延时（sys.wait），必须在任务协程中调用，
因此本 demo 将初始化与全部演示放在同一个任务函数内顺序执行。
]]

local tsl2561 = require "exs_tsl2561"

-- ==================== 演示任务函数 ====================

-- [1/4] 基础读取演示：默认配置（1x 增益 + 402ms 积分），每秒读取一次，共 5 次
-- 演示 exs_tsl2561.get_lux / get_data 的持续监测能力
local function basic_demo()
    log.info("tsl2561_demo", "[1/4] 基础读取演示开始（默认配置：1x 增益 + 402ms 积分）")
    for i = 1, 5 do
        -- 读取照度 lux（内部自动读取 CH0/CH1 并计算）
        local lux = tsl2561.get_lux()
        if lux then
            -- 再读取一次双通道原始数据用于展示
            local data = tsl2561.get_data()
            if data then
                log.info("tsl2561_demo", string.format("第 %d 次读取, CH0=%d, CH1=%d, 照度: %.1f lux", i, data.ch0, data.ch1, lux))
            else
                log.info("tsl2561_demo", string.format("第 %d 次读取, 照度: %.1f lux", i, lux))
            end
        else
            log.error("tsl2561_demo", "第 %d 次读取失败", i)
        end
        sys.wait(1000)
    end
    log.info("tsl2561_demo", "[1/4] 基础读取演示结束")
end

-- [2/4] 积分时间切换演示：13.7ms / 101ms / 402ms 三种积分时间切换，对比 lux 读数
-- 说明：lux 计算已按 (402/积分时间) 自动归一化，三种配置下读数应基本一致
local function integration_demo()
    log.info("tsl2561_demo", "[2/4] 积分时间切换演示开始（lux 已自动归一化）")
    -- 积分时间 13.7ms（满量程 5047，适合快速采样）
    if tsl2561.set_timing(tsl2561.GAIN_1X, tsl2561.INTEG_13MS) then
        sys.wait(100)
        local lux = tsl2561.get_lux()
        log.info("tsl2561_demo", "积分时间 13.7ms, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- 积分时间 101ms（满量程 37177，兼顾速度与精度）
    if tsl2561.set_timing(tsl2561.GAIN_1X, tsl2561.INTEG_101MS) then
        sys.wait(200)
        local lux = tsl2561.get_lux()
        log.info("tsl2561_demo", "积分时间 101ms, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- 积分时间 402ms（满量程 65535，最高精度）
    if tsl2561.set_timing(tsl2561.GAIN_1X, tsl2561.INTEG_402MS) then
        sys.wait(500)
        local lux = tsl2561.get_lux()
        log.info("tsl2561_demo", "积分时间 402ms, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    log.info("tsl2561_demo", "[2/4] 积分时间切换演示结束")
end

-- [3/4] 增益切换演示：1x / 16x 增益切换，对比 lux 读数
-- 说明：低照度环境建议用 16x 增益提高灵敏度；强光环境 16x 可能饱和（CH0=0xFFFF，lux 记为 0）
local function gain_demo()
    log.info("tsl2561_demo", "[3/4] 增益切换演示开始")
    -- 低增益 1x（默认，适合明亮环境）
    if tsl2561.set_timing(tsl2561.GAIN_1X, tsl2561.INTEG_402MS) then
        sys.wait(500)
        local lux = tsl2561.get_lux()
        log.info("tsl2561_demo", "低增益 1x, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- 高增益 16x（灵敏度提高 16 倍，适合低照度环境）
    if tsl2561.set_timing(tsl2561.GAIN_16X, tsl2561.INTEG_402MS) then
        sys.wait(500)
        local lux = tsl2561.get_lux()
        log.info("tsl2561_demo", "高增益 16x, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- 恢复低增益 1x
    tsl2561.set_timing(tsl2561.GAIN_1X, tsl2561.INTEG_402MS)
    log.info("tsl2561_demo", "[3/4] 增益切换演示结束")
end

-- [4/4] 中断与电源管理演示：阈值中断设置/清除、手动积分、断电/上电/复位演示
-- 中断基于 CH0 原始值，阈值取当前 CH0 的 ±20%，PERSIST=1（超出阈值 1 次触发）
local function interrupt_power_demo()
    log.info("tsl2561_demo", "[4/4] 中断与电源管理演示开始")
    -- 阈值中断演示
    local data = tsl2561.get_data()
    if data then
        local base = data.ch0
        local low = math.max(0, base - math.floor(base * 0.2))
        local high = math.min(65535, base + math.floor(base * 0.2))
        -- 设置阈值中断：电平中断模式，PERSIST=1
        if tsl2561.set_interrupt(low, high, tsl2561.PERSIST_ONCE) then
            log.info("tsl2561_demo", "阈值中断设置成功, 低阈值=", low, "高阈值=", high)
        end
        sys.wait(100)
        -- 清除中断
        if tsl2561.clear_interrupt() then
            log.info("tsl2561_demo", "中断清除成功")
        end
    end
    sys.wait(500)
    -- 手动积分演示：设置手动模式 → 开始积分 → 等待 100ms → 停止积分 → 读取
    log.info("tsl2561_demo", "手动积分演示开始（100ms）")
    if tsl2561.set_timing(tsl2561.GAIN_1X, tsl2561.INTEG_MANUAL) then
        if tsl2561.manual_start() then
            sys.wait(100)
            if tsl2561.manual_stop() then
                sys.wait(50)
                local d = tsl2561.get_data()
                if d then
                    log.info("tsl2561_demo", "手动积分 100ms, CH0=", d.ch0, "CH1=", d.ch1)
                end
            end
        end
    end
    sys.wait(500)
    -- 断电（进入低功耗）
    if tsl2561.power_down() then
        sys.wait(300)
        log.info("tsl2561_demo", "断电后读取（应为失败或无响应）")
        local lux = tsl2561.get_lux()
        log.info("tsl2561_demo", "断电后 get_lux 返回: ", lux or "nil（符合预期）")
    end
    sys.wait(500)
    -- 上电恢复测量
    if tsl2561.power_up() then
        tsl2561.set_timing(tsl2561.GAIN_1X, tsl2561.INTEG_402MS)
        sys.wait(500)
        local lux = tsl2561.get_lux()
        log.info("tsl2561_demo", "上电恢复后, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- 复位（恢复默认配置）
    if tsl2561.reset() then
        sys.wait(500)
        local lux = tsl2561.get_lux()
        log.info("tsl2561_demo", "复位恢复后, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    log.info("tsl2561_demo", "[4/4] 中断与电源管理演示结束")
end

-- ==================== 主任务 ====================

-- 主演示任务：初始化 TSL2561 并顺序执行 4 项演示
local function tsl2561_demo_task_func()
    log.info("tsl2561_demo", "TSL2561 Demo 启动")
    -- 初始化：I2C1（Air780EHV 67=SCL/66=SDA）、地址 0x29（本模块 ADDR SEL 接地）
    local result = tsl2561.init(1, tsl2561.ADDR_GND)
    if not result then
        log.error("tsl2561_demo", "TSL2561 初始化失败，请检查接线/供电/地址配置")
        return
    end
    log.info("tsl2561_demo", "TSL2561 初始化成功, 版本:", tsl2561.version())
    sys.wait(500)
    -- 顺序执行 4 项演示
    basic_demo()
    integration_demo()
    gain_demo()
    interrupt_power_demo()
    log.info("tsl2561_demo", "TSL2561 Demo 全部演示结束")
end

sys.taskInit(tsl2561_demo_task_func)
