--[[
@module  bh1750_demo
@summary BH1750 数字环境光传感器 Demo
@version 1.0
@date    2026.08.26
@author  沈园园
@usage
本文件为 exs_bh1750 扩展库的演示模块，按顺序演示以下 4 项功能：
HELLO→[1/4]→[2/4]→[3/4]→[4/4]→End
1、连续测量演示（[1/4]）- 连续 H 分辨率模式，每秒读取一次照度，共 5 次
2、单次测量演示（[2/4]）- 单次 H 分辨率模式，每次触发测量后读取，共 3 次
3、分辨率切换演示（[3/4]）- H/H2/L 三种分辨率切换，对比 lux 读数差异
4、电源管理演示（[4/4]）- MTreg 调整 / 断电 / 上电 / 复位功能演示

本文件没有对外接口，直接在 main.lua 中 require "bh1750_demo" 就可以加载运行；
注意：exs_bh1750.get_lux 内部会执行系统延时（sys.wait），必须在任务协程中调用，
因此本 demo 将初始化与全部演示放在同一个任务函数内顺序执行。
]]

local bh1750 = require "exs_bh1750"

-- ==================== 演示任务函数 ====================

-- [1/4] 连续测量演示：连续 H 分辨率模式，每秒读取一次照度，共 5 次
-- 演示 exs_bh1750.MODE_CONT_H 模式下的持续监测能力
local function continuous_demo()
    log.info("bh1750_demo", "[1/4] 连续测量演示开始（连续 H 分辨率模式）")
    for i = 1, 5 do
        local lux = bh1750.get_lux()
        if lux then
            log.info("bh1750_demo", string.format("第 %d 次读取, 照度: %.1f lux", i, lux))
        else
            log.error("bh1750_demo", "第 %d 次读取失败", i)
        end
        sys.wait(1000)
    end
    log.info("bh1750_demo", "[1/4] 连续测量演示结束")
end

-- [2/4] 单次测量演示：单次 H 分辨率模式，每次触发测量后读取，共 3 次
-- 演示 exs_bh1750.MODE_ONCE_H 模式（测量完成后自动断电，适合低功耗场景）
local function once_demo()
    log.info("bh1750_demo", "[2/4] 单次测量演示开始（单次 H 分辨率模式）")
    -- 切换到单次测量模式
    if not bh1750.set_mode(bh1750.MODE_ONCE_H) then
        log.error("bh1750_demo", "切换单次测量模式失败")
        return
    end
    for i = 1, 3 do
        -- get_lux 内部自动完成：发送测量指令 → 等待测量完成 → 读取数据
        local lux = bh1750.get_lux()
        if lux then
            log.info("bh1750_demo", string.format("第 %d 次单次测量, 照度: %.1f lux", i, lux))
        else
            log.error("bh1750_demo", "第 %d 次单次测量失败", i)
        end
        sys.wait(500)
    end
    log.info("bh1750_demo", "[2/4] 单次测量演示结束")
end

-- [3/4] 分辨率切换演示：H/H2/L 三种分辨率切换，对比 lux 读数差异
-- H：1 lux 分辨率（120ms）；H2：0.5 lux 分辨率（120ms）；L：4 lux 分辨率（16ms）
local function resolution_demo()
    log.info("bh1750_demo", "[3/4] 分辨率切换演示开始")
    -- H 分辨率（1 lux）
    if bh1750.set_mode(bh1750.MODE_CONT_H) then
        sys.wait(200)
        local lux = bh1750.get_lux()
        log.info("bh1750_demo", "H 分辨率（1 lux）, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- H2 分辨率（0.5 lux）
    if bh1750.set_mode(bh1750.MODE_CONT_H2) then
        sys.wait(200)
        local lux = bh1750.get_lux()
        log.info("bh1750_demo", "H2 分辨率（0.5 lux）, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- L 分辨率（4 lux）
    if bh1750.set_mode(bh1750.MODE_CONT_L) then
        sys.wait(100)
        local lux = bh1750.get_lux()
        log.info("bh1750_demo", "L 分辨率（4 lux）, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- 恢复 H 分辨率模式
    bh1750.set_mode(bh1750.MODE_CONT_H)
    log.info("bh1750_demo", "[3/4] 分辨率切换演示结束")
end

-- [4/4] 电源管理演示：MTreg 调整 / 断电 / 上电 / 复位功能演示
-- MTreg 范围 31~254（默认 69），值越大测量时间越长、灵敏度越高
local function power_demo()
    log.info("bh1750_demo", "[4/4] 电源管理演示开始")
    -- MTreg=31：最短测量时间，灵敏度最低
    if bh1750.set_mtreg(31) then
        bh1750.set_mode(bh1750.MODE_CONT_H)
        sys.wait(200)
        local lux = bh1750.get_lux()
        log.info("bh1750_demo", "MTreg=31（低灵敏度）, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- MTreg=254：最长测量时间，灵敏度最高
    if bh1750.set_mtreg(254) then
        bh1750.set_mode(bh1750.MODE_CONT_H)
        sys.wait(400)
        local lux = bh1750.get_lux()
        log.info("bh1750_demo", "MTreg=254（高灵敏度）, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- 恢复默认 MTreg=69
    bh1750.set_mtreg(69)
    bh1750.set_mode(bh1750.MODE_CONT_H)
    sys.wait(300)
    -- 断电（进入低功耗）
    if bh1750.power_down() then
        sys.wait(300)
        log.info("bh1750_demo", "断电后读取（应为失败或无响应）")
        local lux = bh1750.get_lux()
        log.info("bh1750_demo", "断电后 get_lux 返回: ", lux or "nil（符合预期）")
    end
    sys.wait(500)
    -- 上电 + 重新启动测量
    if bh1750.power_on() then
        bh1750.set_mode(bh1750.MODE_CONT_H)
        sys.wait(300)
        local lux = bh1750.get_lux()
        log.info("bh1750_demo", "上电恢复后, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    sys.wait(500)
    -- 复位（恢复默认配置）
    if bh1750.reset() then
        bh1750.set_mode(bh1750.MODE_CONT_H)
        sys.wait(300)
        local lux = bh1750.get_lux()
        log.info("bh1750_demo", "复位恢复后, 照度: ", lux and string.format("%.1f", lux) or "读取失败")
    end
    log.info("bh1750_demo", "[4/4] 电源管理演示结束")
end

-- ==================== 主任务 ====================

-- 主演示任务：初始化 BH1750 并顺序执行 4 项演示
local function bh1750_demo_task_func()
    log.info("bh1750_demo", "BH1750 Demo 启动")
    -- 初始化：I2C1（Air780EHV 67=SCL/66=SDA）、地址 0x23、连续 H 分辨率模式
    local result = bh1750.init()
    if not result then
        log.error("bh1750_demo", "BH1750 初始化失败，请检查接线/供电/地址配置")
        return
    end
    log.info("bh1750_demo", "BH1750 初始化成功, 版本:", bh1750.version())
    sys.wait(500)
    -- 顺序执行 4 项演示
    continuous_demo()
    once_demo()
    resolution_demo()
    power_demo()
    log.info("bh1750_demo", "BH1750 Demo 全部演示结束")
end

sys.taskInit(bh1750_demo_task_func)
