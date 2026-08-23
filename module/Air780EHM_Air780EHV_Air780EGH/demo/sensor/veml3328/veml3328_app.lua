--[[
@module  veml3328_app
@summary VEML3328 RGBW 颜色传感器应用示例
@version 1.0
@date    2026.08.07
@author  沈园园
@usage
本文件为 VEML3328 传感器的应用示例，核心业务逻辑为：
1、初始化Air780EHM/Air780EHV/Air780EGH核心板和 VEML3328 之间的软件 I2C 通信
2、基础颜色检测（连续读取5次RGBW+IR数据）
3、增益配置测试（对比1x/2x/4x增益）
4、集成时间与灵敏度测试（对比100ms/200ms集成时间）
5、低光检测与颜色分析（高灵敏度模式下的颜色比例分析）

本文件没有对外接口，直接在 main.lua 中 require "veml3328_app" 就可以加载运行；
]]

local exs_veml3328 = require "exs_veml3328"

-- 通信模式切换：1=软件 I2C（scl/sda） / 2=硬件 I2C（i2c_id）
-- VEML3328 要求 Repeated Start 读取，硬件 I2C 会发 STOP 导致读取失败
-- 因此必须使用软件 I2C 模式（MODE=1）
-- Air780EHV: 软件 I2C 使用 GPIO12(SCL)=引脚28, GPIO13(SDA)=引脚29
-- Air780EHM: 软件 I2C 使用 GPIO31(SCL)=引脚32, GPIO30(SDA)=引脚31
local MODE = 1

-- 按 MODE 组装 setup 参数
local function build_config_func()
    if MODE == 1 then
        -- 软件 I2C 模式（Air780EHV: SCL=GPIO12/引脚28, SDA=GPIO13/引脚29）
        return {scl = 12, sda = 13}
    else
        -- 硬件 I2C 模式（id=1, 引脚66/67）
        return {i2c_id = 1}
    end
end

-- VEML3328 初始化函数
-- 重要：必须返回 boolean，失败时 return false
local function init_func()
    local config = build_config_func()
    local result = exs_veml3328.setup(config)
    if not result then
        log.error("veml3328", "初始化失败")
        log.error("veml3328", "检查接线: VCC=3.3V GND SCL SDA")
        return false
    end
    log.info("veml3328", "初始化成功，版本:", exs_veml3328.version())
    return true
end

-- [1/4] 基础颜色检测测试
local function basic_detect_func()
    log.info("veml3328", "[1/4] ★ 开始基础颜色检测测试")

    -- 读取5次数据
    for i = 1, 5 do
        local data = exs_veml3328.get_data()
        if data then
            log.info("veml3328", string.format(
                "[%d] R=%d G=%d B=%d C=%d IR=%d",
                i, data.red, data.green, data.blue, data.clear, data.ir
            ))
        else
            log.error("veml3328", "读取数据失败")
        end
        sys.wait(500)  -- 等待 500ms
    end

    log.info("veml3328", "[1/4] ✓ 基础颜色检测测试完成")
end

-- [2/4] 增益配置测试
local function gain_test_func()
    log.info("veml3328", "[2/4] ★ 开始增益配置测试")

    -- 测试不同增益
    local gains = {1, 2, 4}
    for _, gain in ipairs(gains) do
        log.info("veml3328", string.format("--- 测试增益 %dx ---", gain))
        exs_veml3328.set_gain(gain)
        sys.wait(200)  -- 等待增益生效，200ms

        local data = exs_veml3328.get_data()
        if data then
            log.info("veml3328", string.format(
                "增益%dx: R=%d G=%d B=%d",
                gain, data.red, data.green, data.blue
            ))
        end
        sys.wait(300)  -- 等待 300ms
    end

    -- 恢复默认增益
    exs_veml3328.set_gain(1)
    log.info("veml3328", "[2/4] ✓ 增益配置测试完成")
end

-- [3/4] 集成时间与灵敏度测试
local function it_sens_test_func()
    log.info("veml3328", "[3/4] ★ 开始集成时间与灵敏度测试")

    -- 测试不同集成时间
    local its = {100, 200}
    for _, it in ipairs(its) do
        log.info("veml3328", string.format("--- 测试集成时间 %dms ---", it))
        exs_veml3328.set_it(it)
        sys.wait(it + 100)  -- 等待集成时间+余量

        local data = exs_veml3328.get_data()
        if data then
            log.info("veml3328", string.format(
                "IT=%dms: R=%d G=%d B=%d C=%d",
                it, data.red, data.green, data.blue, data.clear
            ))
        end
    end

    -- 恢复默认
    exs_veml3328.set_it(100)

    -- 读取配置寄存器
    local config = exs_veml3328.get_config()
    if config then
        log.info("veml3328", string.format("当前配置: 0x%04X", config))
    end

    log.info("veml3328", "[3/4] ✓ 集成时间与灵敏度测试完成")
end

-- [4/4] 低光检测与颜色分析
local function low_light_test_func()
    log.info("veml3328", "[4/4] ★ 开始低光检测与颜色分析")

    -- 设置高灵敏度配置
    exs_veml3328.set_gain(12)    -- 最高增益
    exs_veml3328.set_dg(4)        -- 最高 DG 增益
    exs_veml3328.set_it(400)      -- 最长集成时间
    exs_veml3328.set_sensitivity("high")
    sys.wait(500)  -- 等待配置生效，500ms

    log.info("veml3328", "高灵敏度模式已启用，开始颜色分析...")

    -- 读取并分析颜色比例
    for i = 1, 3 do
        local data = exs_veml3328.get_data()
        if data then
            -- 计算颜色比例
            local total = data.red + data.green + data.blue
            if total > 0 then
                local r_pct = data.red * 100.0 / total
                local g_pct = data.green * 100.0 / total
                local b_pct = data.blue * 100.0 / total
                log.info("veml3328", string.format(
                    "[%d] 颜色比例: R=%.1f%% G=%.1f%% B=%.1f%% (总=%.0f)",
                    i, r_pct, g_pct, b_pct, total
                ))
            end

            -- 判断主导颜色
            if data.red > data.green and data.red > data.blue then
                log.info("veml3328", "→ 主导颜色: 红色")
            elseif data.green > data.red and data.green > data.blue then
                log.info("veml3328", "→ 主导颜色: 绿色")
            elseif data.blue > data.red and data.blue > data.green then
                log.info("veml3328", "→ 主导颜色: 蓝色")
            end
        end
        sys.wait(1000)  -- 等待 1 秒
    end

    -- 恢复默认配置
    exs_veml3328.set_gain(1)
    exs_veml3328.set_dg(1)
    exs_veml3328.set_it(100)
    sys.wait(200)  -- 等待配置恢复，200ms

    log.info("veml3328", "[4/4] ✓ 低光检测与颜色分析完成")
end

-- 主任务协程
local function demo_task_func()
    log.info("veml3328", "====== VEML3328 传感器 Demo 开始 ======")

    sys.wait(100)  -- 等待系统稳定，100ms

    -- [1/4] 初始化
    log.info("veml3328", "[0/4] ★ 初始化传感器")
    if not init_func() then
        log.error("veml3328", "初始化失败，Demo 终止")
        return
    end

    -- [1/4] 基础颜色检测
    basic_detect_func()

    -- [2/4] 增益配置测试
    gain_test_func()

    -- [3/4] 集成时间与灵敏度测试
    it_sens_test_func()

    -- [4/4] 低光检测与颜色分析
    low_light_test_func()

    -- 释放资源
    exs_veml3328.close()
    log.info("veml3328", "====== 全部测试完成 ======")
end

sys.taskInit(demo_task_func)
