--[[
@module  opt3001_app
@summary OPT3001 数字环境光传感器应用示例
@version 1.0
@date    2026.08.06
@author  沈园园
@usage
本文件为 OPT3001 传感器的应用示例，核心业务逻辑为：
1、初始化Air780EHM/Air780EHV/Air780EGH核心板和 OPT3001 之间的 I2C 通信
2、连续读取环境光照度（自动量程）
3、单次测量模式（对比 100ms/800ms 转换时间）
4、阈值中断功能（上限/下限报警）
5、配置管理与软件复位

本文件没有对外接口，直接在 main.lua 中 require "opt3001_app" 就可以加载运行；
]]

-- 加载 OPT3001 扩展库
local opt3001 = require "exs_opt3001"

-- ==================== 硬件配置 ====================

-- 通信模式：1=软件 I2C / 2=硬件 I2C
local MODE = 2

-- 硬件 I2C 配置
local HW_I2C_CONFIG = {
    i2c_id = 1,
    int_gpio = 2,
    addr = 0x44,
}

-- 软件 I2C 配置
local SW_I2C_CONFIG = {
    scl = 67,
    sda = 66,
    int_gpio = 2,
    addr = 0x44,
}

-- 根据 MODE 选择配置
local config
if MODE == 1 then
    config = SW_I2C_CONFIG
    log.info("opt3001_app", "使用软件 I2C (SCL=" .. SW_I2C_CONFIG.scl .. ", SDA=" .. SW_I2C_CONFIG.sda .. ")")
else
    config = HW_I2C_CONFIG
    log.info("opt3001_app", "使用硬件 I2C (id=" .. HW_I2C_CONFIG.i2c_id .. ")")
end

-- ==================== [1/4] 初始化与连续读取 ====================

-- 连续读取照度任务（自动量程，800ms 转换时间）
local function continuous_read_task()
    log.info("opt3001", "[1/4] ★ 开始连续读取照度（自动量程，800ms 转换时间）")
    local count = 0
    while count < 10 do
        local data = opt3001.get_data()
        if data then
            log.info("opt3001", string.format("照度: %.2f lux (溢出=%s)", data.lux,
                data.overflow and "是" or "否"))
        else
            log.warn("opt3001", "读取失败")
        end
        sys.wait(800)     -- 等待 800ms（匹配转换时间）
        count = count + 1
    end
    log.info("opt3001", "[1/4] ✓ 连续读取完成")
end

-- ==================== [2/4] 单次测量模式 ====================

-- 单次测量对比任务（100ms vs 800ms）
local function single_shot_task()
    log.info("opt3001", "[2/4] ★ 开始单次测量模式测试")

    -- 100ms 快速模式（单次测量）
    log.info("opt3001", "--- 100ms 快速模式 ---")
    opt3001.set_config({mode = "single", ct = 100})
    sys.wait(10)          -- 等待配置生效
    for i = 1, 5 do
        local data = opt3001.get_data()
        if data then
            log.info("opt3001", string.format("[100ms] 照度: %.2f lux", data.lux))
        end
        sys.wait(200)     -- 间隔 200ms
    end

    -- 800ms 精确模式（单次测量）
    log.info("opt3001", "--- 800ms 精确模式 ---")
    opt3001.set_config({mode = "single", ct = 800})
    sys.wait(10)          -- 等待配置生效
    for i = 1, 5 do
        local data = opt3001.get_data()
        if data then
            log.info("opt3001", string.format("[800ms] 照度: %.2f lux", data.lux))
        end
        sys.wait(900)     -- 间隔 900ms
    end

    -- 恢复连续模式
    opt3001.set_config({mode = "continuous"})
    log.info("opt3001", "[2/4] ✓ 单次测量测试完成")
end

-- ==================== [3/4] 阈值中断功能 ====================

-- 中断消息监听任务
local function int_listener_task()
    log.info("opt3001", "[3/4] ★ 启动中断监听任务")
    while true do
        local ret = sys.waitUntil("exs_opt3001_INT", 3000)
        if ret then
            local cfg = opt3001.get_config()
            if cfg then
                if cfg.flag_high then
                    log.info("opt3001", "[3/4] ★ 中断触发：照度超过上限阈值！")
                end
                if cfg.flag_low then
                    log.info("opt3001", "[3/4] ★ 中断触发：照度低于下限阈值！")
                end
            end
        end
    end
end

-- 阈值中断测试任务
local function threshold_int_test_task()
    log.info("opt3001", "[3/4] ★ 开始阈值中断功能测试")

    -- 启动中断消息监听任务
    sys.taskInit(int_listener_task)

    -- 设置阈值（10 lux 低限 / 1000 lux 高限）
    local ok = opt3001.set_threshold(10, 1000)
    if ok then
        log.info("opt3001", "阈值已设置: 低限=10 lux, 高限=1000 lux")
    else
        log.warn("opt3001", "阈值设置失败")
    end

    -- 读取当前阈值
    local th = opt3001.get_threshold()
    if th then
        log.info("opt3001", string.format("当前阈值: 低限=%.2f, 高限=%.2f", th.low, th.high))
    end

    -- 等待一段时间观察中断
    log.info("opt3001", "等待中断触发（可遮挡/照射传感器改变照度）...")
    sys.wait(15000)        -- 等待 15 秒
    log.info("opt3001", "[3/4] ✓ 阈值中断测试完成")
end

-- ==================== [4/4] 配置管理与软件复位 ====================

-- 配置管理与软件复位测试
local function config_reset_task()
    log.info("opt3001", "[4/4] ★ 开始配置管理与软件复位测试")

    -- 读取当前配置
    local cfg = opt3001.get_config()
    if cfg then
        log.info("opt3001", string.format("当前配置: mode=%s ct=%dms range=%s",
            cfg.mode, cfg.ct, cfg.range))
        log.info("opt3001", string.format("标志: CRF=%s F_H=%s F_L=%s OVF=%s",
            cfg.conv_ready and "Y" or "N",
            cfg.flag_high and "Y" or "N",
            cfg.flag_low and "Y" or "N",
            cfg.overflow and "Y" or "N"))
    end

    -- 读取版本
    log.info("opt3001", "版本号: " .. opt3001.version())

    -- 软件复位
    local ok = opt3001.soft_reset()
    if ok then
        log.info("opt3001", "软件复位成功")
        sys.wait(500)      -- 等待复位完成

        -- 复位后读取一次数据验证
        local data = opt3001.get_data()
        if data then
            log.info("opt3001", string.format("复位后照度: %.2f lux", data.lux))
        end
    end

    log.info("opt3001", "[4/4] ✓ 配置管理与软件复位测试完成")
end

-- ==================== 主任务 ====================

-- 主任务：依次执行 [1/4]~[4/4] 测试
local function main_task()
    log.info("opt3001", "====== OPT3001 传感器 Demo 开始 ======")
    log.info("opt3001", string.format("初始化 OPT3001 (MODE=%d)...", MODE))

    -- [1/4] 初始化与连续读取
    local ok = opt3001.setup(config)
    if not ok then
        log.error("opt3001", "初始化失败！检查接线: VCC=3.3V GND SCL SDA")
        log.error("opt3001", "OPT3001 I2C 地址: ADDR 接地=0x44, ADDR 接 VDD=0x45")
        return
    end

    log.info("opt3001", "初始化成功，版本: " .. opt3001.version())

    -- 依次执行测试
    continuous_read_task()
    sys.wait(500)          -- 间隔 500ms

    single_shot_task()
    sys.wait(500)          -- 间隔 500ms

    threshold_int_test_task()
    sys.wait(500)          -- 间隔 500ms

    config_reset_task()

    log.info("opt3001", "====== 全部测试完成 ======")

    -- 释放资源
    sys.wait(2000)         -- 收尾等待
    opt3001.close()
end

sys.taskInit(main_task)