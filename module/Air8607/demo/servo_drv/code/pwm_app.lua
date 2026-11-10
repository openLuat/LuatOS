--[[
@module  pwm_app
@summary PWM 输出功能模块
@version 1.0
@date    2025.10.29
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
1. 本 demo 演示所使用的是 Air8000 模组的 PWM4 通道（GPIO21，PIN24）；
2. 该引脚需要通过 LuatIO 工具进行复用配置，pins_Air8000.json 文件即复用配置后生成的文件；
3. 关于 LuatIO 工具的使用介绍以及如何生成 json 文件，请参考 https://docs.openluat.com/air780epm/common/luatio/；
3. 将通过 LuatIO 工具配置好复用关系后生成的 json 文件与脚本文件一同烧录到模组中即可实现 PWM 输出功能；

本文件没有对外接口,直接在 main.lua 中 require "pwm_app" 就可以加载运行；
]]

--[[
旧风格 PWM 演示函数
使用 pwm.open() 一次性完成配置和启动
适合固定频率/占空比、无需中途调整的场景
]]
local function task1_old_pwm()
    log.info("PWM", "旧风格 PWM 示例开始")

    -- 选择 PWM 通道 4
    -- 注意：本 demo 演示所使用的是 Air8000 模组的 PWM4 通道（GPIO21，PIN24）；
    -- 该引脚需要通过 LuatIO 工具进行复用配置，详细说明看最顶部的注意事项；
    local pwm_channel = 4

    -- 第一次输出：1 kHz，45% 占空比，分频精度 100
    local pwm_success = pwm.open(pwm_channel, 1000, 45, 0, 100)
    if pwm_success then
        log.info("PWM", "PWM4 通道开启成功: 信号频率 1000 Hz, 分频精度 100, 占空比 45%")
    else
        log.info("PWM", "PWM4 通道开启失败")
    end

    -- 持续 1 s 后关闭
    sys.wait(1000)
    pwm.close(pwm_channel)
    log.info("PWM", "PWM4 通道已关闭")

    -- 增加 1 秒的间隔时间
    sys.wait(1000)

    -- 第二次输出：500 Hz，60% 占空比，分频精度 100
    local pwm_success = pwm.open(pwm_channel, 500, 60, 0, 100)
    if pwm_success then
        log.info("PWM", "PWM4 通道开启成功: 信号频率 500 Hz, 分频精度 100, 占空比 60%")
    else
        log.info("PWM", "PWM4 通道开启失败")
    end

    -- 持续 2 s 后关闭
    sys.wait(2000)
    pwm.close(pwm_channel)
    log.info("PWM", "PWM4 通道已关闭")

    -- 增加 1 秒的间隔时间
    sys.wait(1000)

    -- 第三次输出：300 Hz，80% 占空比，分频精度 100
    local pwm_success = pwm.open(pwm_channel, 300, 80, 0, 100)
    if pwm_success then
        log.info("PWM", "PWM4 通道开启成功: 信号频率 300 Hz, 分频精度 100, 占空比 80%")
    else
        log.info("PWM", "PWM4 通道开启失败")
    end

    -- 持续 3 s 后关闭
    sys.wait(3000)
    pwm.close(pwm_channel)
    log.info("PWM", "PWM4 通道已关闭")

    log.info("PWM", "旧风格 PWM 示例结束")
end


--[[
新风格 PWM 演示函数
使用 pwm.setup() 分步完成配置与启动，支持运行中动态修改频率和占空比
适合需要实时调节输出参数的场景
]]
local function task2_new_pwm()
    log.info("PWM", "新风格 PWM 示例开始")

    -- 选择 PWM 通道 4
    -- 注意：本 demo 演示所使用的是 Air8000 模组的 PWM4 通道（GPIO21，PIN24）；
    -- 该引脚需要通过 LuatIO 工具进行复用配置，详细说明看最顶部的注意事项；
    local pwm_channel = 1

    -- 配置 PWM 参数：频率 1000 Hz、占空比 50%、分频精度 100
    local setup_success = pwm.setup(pwm_channel, 1000, 50, 1)
    if setup_success then
        log.info("PWM", "PWM4 配置成功: 信号频率 1000 Hz, 分频精度 100, 占空比 50%")
    else
        log.info("PWM", "PWM4 配置失败")
    end

    -- 启动 PWM 输出
    local pwm_success = pwm.start(pwm_channel)
    if pwm_success then
        log.info("PWM", "PWM4 启动成功")
    else
        log.info("PWM", "PWM4 启动失败")
    end


    -- 持续输出 2 秒
    sys.wait(2000)

    -- 停止分两步，避免在周期中间硬切导致最后一个脉冲被截断成尖峰：
    -- 1) 同频率下把占空比降到 0：引脚不再翻转，停在常量电平
    -- 2) 等几个周期让引脚稳定到低电平（10kHz 一个周期 100us，5ms = 50 个周期）
    -- 3) 这时再关通道，关断瞬间引脚本来就是低的，不会产生截断脉冲
    -- local duty_ok = pwm.setDuty(pwm_channel, 0)
    -- log.info("PWM", "停止第1步：占空比压 0 ->", tostring(duty_ok))
    -- sys.wait(5)

    -- 停止 PWM 输出
    local pwm_success = pwm.stop(pwm_channel)
    if pwm_success then
        log.info("PWM", "PWM4 停止成功")
    else
        log.info("PWM", "PWM4 停止失败")
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
    -- task1_old_pwm()

    while true do
        -- 间隔 3 秒
        sys.wait(3000)

        -- 运行新风格 PWM 示例
        task2_new_pwm()
    end

    log.info("PWM", "PWM 综合演示任务结束")
end

-- 创建并启动一个 task
-- 用于运行 pwm_demo_task 函数
sys.taskInit(pwm_demo_task)
