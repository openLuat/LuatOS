--[[
@module  pca9685_demo
@summary PCA9685 16路 PWM/Servo 舵机驱动 Demo
@version 1.0
@date    2026.08.25
@author  沈园园
@usage
本文件为 exs_pca9685 扩展库的演示模块，按顺序演示以下 4 项功能：
HELLO→[1/4]→[2/4]→[3/4]→[4/4]→End
1、PWM 频率设置演示（[1/4]）- CH0 固定 50% 占空比，切换 24/50/200Hz 观察 LED 闪烁/常亮
2、呼吸灯演示（[2/4]）- CH0 占空比 0→4095→0 渐变 3 个周期
3、舵机角度演示（[3/4]）- CH1 角度 0°→180°→0° 扫描 2 个周期
4、全通道控制演示（[4/4]）- set_all_pwm 全亮/全灭 + set_output_mode 模式切换

本文件没有对外接口，直接在 main.lua 中 require "pca9685_demo" 就可以加载运行；
注意：exs_pca9685.init 内部会执行系统延时（sys.wait），必须在任务协程中调用，
因此本 demo 将初始化与全部演示放在同一个任务函数内顺序执行。
]]

local pca9685 = require "exs_pca9685"

-- ==================== 演示任务函数 ====================

-- [1/4] PWM 频率设置演示：CH0 固定 50% 占空比，切换频率观察 LED 闪烁/常亮
-- 24Hz（最低频率）肉眼可见明显闪烁；50Hz/200Hz 肉眼视为常亮
local function pwm_freq_demo()
    log.info("pca9685_demo", "[1/4] PWM 频率设置演示开始（CH0 固定 50% 占空比）")
    -- 在 CH0 设置 50% 占空比作为观察对象
    pca9685.set_pwm(0, 2048)
    -- 24Hz：最低频率，LED 肉眼可见闪烁
    pca9685.set_pwm_freq(24)
    sys.wait(2000)
    -- 50Hz：标准舵机频率，LED 肉眼视为常亮
    pca9685.set_pwm_freq(50)
    sys.wait(2000)
    -- 200Hz：高频，LED 常亮（可用示波器观察频率变化）
    pca9685.set_pwm_freq(200)
    sys.wait(2000)
    -- 恢复 50Hz（舵机标准频率，为后续舵机演示做准备）
    pca9685.set_pwm_freq(50)
    sys.wait(2000)
    log.info("pca9685_demo", "[1/4] PWM 频率设置演示结束")
end

-- [2/4] 呼吸灯演示：CH0 占空比 0→4095→0 渐变，共 3 个周期
local function breath_lamp_demo()
    log.info("pca9685_demo", "[2/4] 呼吸灯演示开始（CH0，需外接 LED）")
    for cycle = 1, 3 do
        -- 占空比从 0 渐变到 4095（渐亮）
        for duty = 0, 4095, 64 do
            pca9685.set_pwm(0, duty)
            sys.wait(20)
        end
        -- 占空比从 4095 渐变到 0（渐灭）
        for duty = 4095, 0, -64 do
            pca9685.set_pwm(0, duty)
            sys.wait(20)
        end
    end
    -- 演示结束，熄灭 CH0
    pca9685.set_pwm(0, 0)
    log.info("pca9685_demo", "[2/4] 呼吸灯演示结束")
end

-- [3/4] 舵机角度演示：CH1 角度 0°→180°→0° 扫描，共 2 个周期
local function servo_demo()
    log.info("pca9685_demo", "[3/4] 舵机角度演示开始（CH1，需外接舵机，频率 50Hz）")
    for cycle = 1, 2 do
        -- 0°→180°，每 10° 一步
        for angle = 0, 180, 10 do
            pca9685.set_servo_angle(1, angle)
            sys.wait(300)
        end
        -- 180°→0°，每 10° 一步
        for angle = 180, 0, -10 do
            pca9685.set_servo_angle(1, angle)
            sys.wait(300)
        end
    end
    log.info("pca9685_demo", "[3/4] 舵机角度演示结束")
end

-- [4/4] 全通道控制演示：set_all_pwm 全亮/全灭 + set_output_mode 模式切换
local function all_channel_demo()
    log.info("pca9685_demo", "[4/4] 全通道控制演示开始（需外接 LED）")
    -- 全通道 50% 占空比点亮（16 路同时输出）
    pca9685.set_all_pwm(2048)
    sys.wait(2000)
    -- 全通道熄灭
    pca9685.set_all_pwm(0)
    sys.wait(2000)
    -- 输出模式配置演示：推挽输出、不反转（默认模式，重新配置确认）
    pca9685.set_output_mode(true, false)
    sys.wait(1000)
    -- 输出模式配置演示：开漏输出、不反转
    pca9685.set_output_mode(false, false)
    sys.wait(1000)
    -- 恢复推挽输出、不反转
    pca9685.set_output_mode(true, false)
    log.info("pca9685_demo", "[4/4] 全通道控制演示结束")
end

-- ==================== 主任务 ====================

-- 主演示任务：初始化 PCA9685 并顺序执行 4 项演示
local function pca9685_demo_task_func()
    log.info("pca9685_demo", "PCA9685 Demo 启动")
    -- 初始化：I2C1（Air780EHV 67=SCL/66=SDA）、地址 0x40、频率 50Hz
    local result = pca9685.init(1, 0x40, 50)
    if not result then
        log.error("pca9685_demo", "PCA9685 初始化失败，请检查接线/供电/地址配置")
        return
    end
    log.info("pca9685_demo", "PCA9685 初始化成功, 版本:", pca9685.version())
    sys.wait(500)
    -- 顺序执行 4 项演示
    pwm_freq_demo()
    breath_lamp_demo()
    servo_demo()
    all_channel_demo()
    log.info("pca9685_demo", "PCA9685 Demo 全部演示结束")
end

sys.taskInit(pca9685_demo_task_func)
