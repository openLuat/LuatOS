--[[
@module  pcf8574_app
@summary PCF8574 GPIO 扩展应用业务模块
@version 1.0
@date    2026.08.06
@author  沈园园
@usage
本文件为 PCF8574 GPIO 扩展芯片的应用示例，核心业务逻辑为：
1、初始化主控和 PCF8574 之间的 I2C 通信参数
2、PCF8574 GPIO 输出测试、输入测试、中断测试、批量读写测试

本文件没有对外接口，直接在 main.lua 中 require "pcf8574_app" 就可以加载运行
]]

local exs_pcf8574 = require "exs_pcf8574"

-- 通信模式切换：1=软件 I2C（scl/sda） / 2=硬件 I2C（i2c_id）
local MODE = 2

-- 按 MODE 组装 setup 参数
local function build_config_func()
    if MODE == 1 then
        return {scl = 67, sda = 66}             -- 软件 I2C
    elseif MODE == 2 then
        return {i2c_id = 1, int_gpio = 2}        -- 硬件 I2C + 中断
    else
        return {i2c_id = 1}                       -- 硬件 I2C 无中断
    end
end

-- PCF8574 初始化函数
local function init_func()
    local config = build_config_func()
    local result = exs_pcf8574.setup(config)
    if not result then
        log.error("pcf8574", "初始化失败")
        log.error("pcf8574", "检查接线: VCC=3.3V GND SCL SDA，A0/A1/A2 地址跳线是否正确")
        return false
    end
    log.info("pcf8574", "初始化成功，版本:", exs_pcf8574.version())
    return true
end

-- [1/5] GPIO 输出测试
-- P0 (0x00) 每隔一秒切换输出一次高低电平
local function gpio_output_task_func()
    log.info("pcf8574", "[1/5] ★ 开始 GPIO 输出测试")
    exs_pcf8574.pin_setup(0x00, 0)

    local count = 0
    while count < 6 do
        exs_pcf8574.set(0x00, 0)
        sys.wait(1000)       -- 等待 1 秒，观察 LED 亮灭
        exs_pcf8574.set(0x00, 1)
        sys.wait(1000)       -- 等待 1 秒，观察 LED 亮灭
        count = count + 1
    end

    exs_pcf8574.pin_close(0x00)
    log.info("pcf8574", "[1/5] ✓ GPIO 输出测试完成")
end

-- [2/5] GPIO 输入测试
-- P1 (0x01) 配置为输出，P2 (0x02) 配置为输入
-- 将 P1 和 P2 短接，通过 P1 输出高低电平，读取 P2 电平
local function gpio_input_task_func()
    log.info("pcf8574", "[2/5] ★ 开始 GPIO 输入测试")
    exs_pcf8574.pin_setup(0x01, 0)   -- P1 输出
    exs_pcf8574.pin_setup(0x02)      -- P2 输入

    local count = 0
    while count < 5 do
        exs_pcf8574.set(0x01, 0)
        sys.wait(500)        -- 等待 500ms
        local level = exs_pcf8574.get(0x02)
        log.info("pcf8574", string.format("P1=0, P2 读取: %d", level))

        exs_pcf8574.set(0x01, 1)
        sys.wait(500)        -- 等待 500ms
        level = exs_pcf8574.get(0x02)
        log.info("pcf8574", string.format("P1=1, P2 读取: %d", level))
        count = count + 1
    end

    exs_pcf8574.pin_close(0x01)
    exs_pcf8574.pin_close(0x02)
    log.info("pcf8574", "[2/5] ✓ GPIO 输入测试完成")
end

-- P4 中断回调函数
local function P4_int_cbfunc(pin, level)
    log.info("pcf8574", string.format("★ 中断触发: pin=%d level=%d", pin, level))
end

-- [3/5] GPIO 中断测试
-- P3 (0x03) 配置为输出，P4 (0x04) 配置为中断
-- 将 P3 和 P4 短接，P3 电平变化时触发 P4 中断
-- 注意：此演示使用轮询方式检测引脚变化（适用于无INT引脚的PCF8574模块）
local function gpio_int_task_func()
    log.info("pcf8574", "[3/5] ★ 开始 GPIO 中断测试（轮询模式）")

    -- 步骤1：先将 P3 设为高电平（确保 P4 初始为高）
    exs_pcf8574.pin_setup(0x03, 1)   -- P3 输出高
    log.info("pcf8574", "P3 输出高电平，等待稳定...")
    sys.wait(100)

    -- 步骤2：配置 P4 为中断模式（注册回调）
    exs_pcf8574.pin_setup(0x04, P4_int_cbfunc)
    log.info("pcf8574", "P4 已配置为中断模式")

    -- 步骤3：启动轮询定时器（每100ms检测一次）
    local poll_timer = sys.timerLoopStart(function()
        exs_pcf8574.poll_int()
    end, 100)
    log.info("pcf8574", "轮询定时器已启动（每100ms检测一次）")

    -- 步骤4：执行中断触发测试
    local count = 0
    while count < 4 do
        log.info("pcf8574", string.format("--- 循环 %d: P3 拉低 → 触发 P4 中断 ---", count + 1))
        exs_pcf8574.set(0x03, 0)
        sys.wait(2000)  -- 等待 2 秒，观察中断日志

        log.info("pcf8574", string.format("--- 循环 %d: P3 拉高 → P4 恢复高电平 ---", count + 1))
        exs_pcf8574.set(0x03, 1)
        sys.wait(1000)

        count = count + 1
    end

    -- 步骤5：停止轮询定时器
    sys.timerStop(poll_timer)

    exs_pcf8574.pin_close(0x03)
    exs_pcf8574.pin_close(0x04)
    log.info("pcf8574", "[3/5] ✓ GPIO 中断测试完成")
end

-- [4/5] 批量读写测试
-- 演示 read_all() 和 write_all() 接口的使用
local function gpio_batch_task_func()
    log.info("pcf8574", "[4/5] ★ 开始批量读写测试")

    local steps = {
        {name = "P0~P3 输出低，P4~P7 输出高", data = 0xF0},
        {name = "全部输出低", data = 0x00},
        {name = "全部输出高", data = 0xFF},
        {name = "交替输出（0x55）", data = 0x55},
    }

    for i = 1, #steps do
        local step = steps[i]
        exs_pcf8574.write_all(step.data)
        sys.wait(500)        -- 等待 500ms，观察 LED 状态

        local d = exs_pcf8574.read_all()
        if d ~= false then
            log.info("pcf8574", string.format("%s: 写入=0x%02X 读取=0x%02X", step.name, step.data, d))
        end
    end

    log.info("pcf8574", "[4/5] ✓ 批量读写测试完成")
end

-- [5/5] 数据读取与资源释放
local function read_data_and_close_func()
    log.info("pcf8574", "[5/5] ★ 读取最终状态并释放资源")

    local data = exs_pcf8574.get_data()
    if data then
        log.info("pcf8574", "最终引脚状态:", json.encode(data))
    end

    exs_pcf8574.close()
    log.info("pcf8574", "[5/5] ✓ 资源已释放")
    log.info("pcf8574", "====== 全部测试完成 ======")
end

-- 主任务协程：按顺序执行 5 项测试
local function demo_main_task_func()
    sys.wait(100)       -- 等待系统稳定，100ms

    local ok = init_func()
    if not ok then return end

    log.info("pcf8574", string.format("====== PCF8574 Demo 开始 (MODE=%d) ======", MODE))

    gpio_output_task_func()
    gpio_input_task_func()
    gpio_int_task_func()
    gpio_batch_task_func()
    read_data_and_close_func()
end

sys.taskInit(demo_main_task_func)