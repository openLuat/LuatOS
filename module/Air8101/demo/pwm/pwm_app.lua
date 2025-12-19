--[[
@module  pwm_app
@summary PWM 输出功能模块
@version 1.0
@date    2025.12.10
@author  马梦阳
@usage
本功能模块演示的内容为：
1. 旧风格 PWM 演示：
    使用 pwm.open() 完成 PWM 通道的配置与启动
    使用 pwm.close() 关闭 PWM 通道
    旧风格 PWM 接口不支持单独配置和动态调整占空比和信号频率
2. 新风格 PWM 演示：
    使用 pwm.setup() 完成 PWM 通道的配置
    使用 pwm.start() 启动 PWM 输出
    使用 pwm.setDuty() 动态调整占空比
    使用 pwm.setFreq() 动态调整信号频率
    使用 pwm.stop() 停止 PWM 输出
    新风格 PWM 接口支持在运行中动态调整占空比和信号频率
3. 综合任务调度：顺序运行上述两种风格示例，并在关键节点进行日志输出

注意事项：
1. 本 demo 演示所使用的是 Air8101 模组的 PWM2 通道（GPIO24，PIN33）；
2. PWM 功能需要使用 V2xxx 版本固件，固件下载链接：https://docs.openluat.com/air8101/luatos/firmware/；

本文件没有对外接口,直接在 main.lua 中 require "pwm_app" 就可以加载运行；
]]

local result = pins.setup(33, "PWM2")
if result then
    log.info("PWM", "PWM2 通道配置成功（GPIO24，PIN33）")
else
    log.error("PWM", "PWM2 通道配置失败（GPIO24，PIN33）")
end

--[[
旧风格 PWM 演示函数
使用 pwm.open() 一次性完成配置和启动
适合固定频率/占空比、无需中途调整的场景
]]
local function task1_old_pwm()
    log.info("PWM", "旧风格 PWM 示例开始")

    -- 选择 PWM 通道 2
    -- 注意：本 demo 演示所使用的是 Air8101 模组的 PWM2 通道（GPIO24，PIN33）；
    local pwm_channel = 2

    -- 第一次输出：1 kHz，45% 占空比，分频精度 100
    local pwm_success = pwm.open(pwm_channel, 1000, 45, 0, 100)
    if pwm_success then
        log.info("PWM", "PWM2 通道开启成功: 信号频率 1000 Hz, 分频精度 100, 占空比 45%")
    else
        log.info("PWM", "PWM2 通道开启失败")
    end

    -- 持续 1 s 后关闭
    sys.wait(1000)
    pwm.close(pwm_channel)
    log.info("PWM", "PWM2 通道已关闭")

    -- 增加 1 秒的间隔时间
    sys.wait(1000)

    -- 第二次输出：500 Hz，60% 占空比，分频精度 100
    local pwm_success = pwm.open(pwm_channel, 500, 60, 0, 100)
    if pwm_success then
        log.info("PWM", "PWM2 通道开启成功: 信号频率 500 Hz, 分频精度 100, 占空比 60%")
    else
        log.info("PWM", "PWM2 通道开启失败")
    end

    -- 持续 2 s 后关闭
    sys.wait(2000)
    pwm.close(pwm_channel)
    log.info("PWM", "PWM2 通道已关闭")

    -- 增加 1 秒的间隔时间
    sys.wait(1000)

    -- 第三次输出：300 Hz，80% 占空比，分频精度 100
    local pwm_success = pwm.open(pwm_channel, 300, 80, 0, 100)
    if pwm_success then
        log.info("PWM", "PWM2 通道开启成功: 信号频率 300 Hz, 分频精度 100, 占空比 80%")
    else
        log.info("PWM", "PWM2 通道开启失败")
    end

    -- 持续 3 s 后关闭
    sys.wait(3000)
    pwm.close(pwm_channel)
    log.info("PWM", "PWM2 通道已关闭")

    log.info("PWM", "旧风格 PWM 示例结束")
end


--[[
新风格 PWM 演示函数
使用 pwm.setup() 分步完成配置与启动，支持运行中动态修改频率和占空比
适合需要实时调节输出参数的场景
]]
local function task2_new_pwm()
    log.info("PWM", "新风格 PWM 示例开始")

    -- 选择 PWM 通道 2
    -- 注意：本 demo 演示所使用的是 Air8101 模组的 PWM2 通道（GPIO24，PIN33）；
    local pwm_channel = 2

    -- 配置 PWM 参数：频率 1000 Hz、占空比 50%、分频精度 100
    local setup_success = pwm.setup(pwm_channel, 1000, 50, 0, 100)
    if setup_success then
        log.info("PWM", "PWM2 配置成功: 信号频率 1000 Hz, 分频精度 100, 占空比 50%")
    else
        log.info("PWM", "PWM2 配置失败")
    end

    -- 启动 PWM 输出
    local pwm_success = pwm.start(pwm_channel)
    if pwm_success then
        log.info("PWM", "PWM2 启动成功")
    else
        log.info("PWM", "PWM2 启动失败")
    end

    -- 持续输出 2 秒
    sys.wait(2000)

    -- 动态调整占空比至 25%
    local setduty_success = pwm.setDuty(pwm_channel, 25)
    if setduty_success then
        log.info("PWM", "PWM2 占空比更新为 25%")
    else
        log.info("PWM", "PWM2 占空比设置失败")
    end

    -- 持续输出 2 秒
    sys.wait(2000)

    -- 动态调整信号频率为 2000 Hz
    local setfreq_success = pwm.setFreq(pwm_channel, 2000)
    if setfreq_success then
        log.info("PWM", "PWM2 频率更新为 2000 Hz")
    else
        log.error("PWM", "PWM2 频率设置失败")
    end

    -- 持续输出 2 秒
    sys.wait(2000)

    -- 停止 PWM 输出
    local pwm_success = pwm.stop(pwm_channel)
    if pwm_success then
        log.info("PWM", "PWM2 停止成功")
    else
        log.info("PWM", "PWM2 停止失败")
    end

    log.info("PWM", "新风格 PWM 示例结束")
end


--[[
主演示任务：
顺序调用旧风格与新风格 PWM 示例函数
并在两者之间插入 3 秒间隔方便区分新旧风格示例输出情况
]]
local function pwm_demo_task()
    log.info("PWM", "PWM 综合演示任务开始")

    -- 运行旧风格 PWM 示例
    task1_old_pwm()

    -- 间隔 3 秒
    sys.wait(3000)

    -- 运行新风格 PWM 示例
    task2_new_pwm()

    log.info("PWM", "PWM 综合演示任务结束")
end

-- 创建并启动一个 task
-- 用于运行 pwm_demo_task 函数
sys.taskInit(pwm_demo_task)
