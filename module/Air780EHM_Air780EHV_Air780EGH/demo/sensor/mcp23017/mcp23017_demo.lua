--[[
@module  mcp23017_demo
@summary MCP23017 GPIO 扩展应用功能模块
@version 1.0
@date    2026.07.30
@author  江访
@usage
本文件为 MCP23017 GPIO 扩展芯片的应用示例，硬件平台为 Air780EHV，核心业务逻辑为：
1、初始化 Air780EHV 和 MCP23017 之间的 I2C 通信参数
2、MCP23017 GPIO 输出测试、输入测试、GPIO 中断测试、上拉电阻测试

本文件没有对外接口，直接在 main.lua 中 require "mcp23017_demo" 就可以加载运行；
]]


-- 加载 MCP23017 扩展库
local mcp23017 = require "exs_mcp23017"


-- MCP23017 扩展 GPIO 输出测试
-- PA0 (0x00) 每隔一秒切换输出一次高低电平，可以通过示波器或者万用表测量 MCP23017 上 PA0 引脚电平
local function gpio_output_task_func()
    mcp23017.setup(0x00, 0)

    while true do
        mcp23017.set(0x00, 0)
        sys.wait(1000)
        mcp23017.set(0x00, 1)
        sys.wait(1000)
    end
end


-- MCP23017 扩展 GPIO 输入测试
-- PA1 (0x01) 配置为输出模式，每隔一秒切换输出一次高低电平
-- PA2 (0x02) 配置为输入模式，每隔一秒调用 get 接口读取一次输入的电平
-- 将 PA1 和 PA2 两个引脚短接
local function gpio_input_task_func()
    mcp23017.setup(0x01, 0)
    mcp23017.setup(0x02)

    while true do
        mcp23017.set(0x01, 0)
        sys.wait(1000)
        log.info("mcp23017.get(0x02)", mcp23017.get(0x02))
        mcp23017.set(0x01, 1)
        sys.wait(1000)
        log.info("mcp23017.get(0x02)", mcp23017.get(0x02))
    end
end


-- PA4 引脚中断处理函数
-- id：0x04
-- level：触发中断后，某一时刻，扩展 GPIO 输入的电平状态，高电平为 1，低电平为 0
local function PA4_int_cbfunc(id, level)
    log.info("PA4_int_cbfunc", id, level)
end

-- PB4 引脚中断处理函数
-- id：0x14
-- level：触发中断后，某一时刻，扩展 GPIO 输入的电平状态，高电平为 1，低电平为 0
local function PB4_int_cbfunc(id, level)
    log.info("PB4_int_cbfunc", id, level)
end

-- MCP23017 扩展 GPIO 中断测试
-- PA3 (0x03) 配置为输出模式，每隔一秒切换输出一次高低电平
-- PA4 (0x04) 配置为中断模式，并且配置中断处理函数 PA4_int_cbfunc
-- 将 PA3 和 PA4 两个引脚短接
-- PB3 (0x13) 配置为输出模式，每隔一秒切换输出一次高低电平
-- PB4 (0x14) 配置为中断模式，并且配置中断处理函数 PB4_int_cbfunc
-- 将 PB3 和 PB4 两个引脚短接
local function gpio_int_task_func()
    mcp23017.setup(0x03, 0)
    mcp23017.setup(0x04, PA4_int_cbfunc)

    mcp23017.setup(0x13, 0)
    mcp23017.setup(0x14, PB4_int_cbfunc)

    while true do
        mcp23017.set(0x03, 0)
        mcp23017.set(0x13, 0)
        sys.wait(1000)
        mcp23017.set(0x03, 1)
        mcp23017.set(0x13, 1)
        sys.wait(1000)
    end
end


-- MCP23017 内部上拉电阻测试
-- PA5 (0x05) 配置为输入模式，启用内部上拉电阻
-- PB5 (0x15) 配置为输入模式，禁用内部上拉电阻
-- 对比两者的读取电平差异
local function gpio_pullup_task_func()
    -- 配置 PA5 为输入模式，启用上拉
    mcp23017.setup(0x05)
    mcp23017.set_pullup(0x05, true)

    -- 配置 PB5 为输入模式，禁用上拉
    mcp23017.setup(0x15)
    mcp23017.set_pullup(0x15, false)

    log.info("mcp23017", "上拉电阻测试已启动，PA5启用上拉，PB5禁用上拉")

    while true do
        local pa5_level = mcp23017.get(0x05)
        local pb5_level = mcp23017.get(0x15)
        log.info("mcp23017", string.format("PA5(上拉):%d  PB5(无上拉):%d", pa5_level, pb5_level))
        sys.wait(2000)
    end
end


-- 初始化 Air780EHV 和 MCP23017 之间的通信参数
-- 使用 Air780EHV 的 I2C1
-- 使用 Air780EHV 的 GPIO2 做为中断引脚
-- Air780EHV 核心板和 MCP23017 模块的接线方式如下：
--
-- Air780EHV 核心板                MCP23017 模块
--      VBAT  -------------------- VDD
--       GND  -------------------- GND
--     66/I2C1SDA  ---------------- SDA
--     67/I2C1SCL  ---------------- SCL
--    23/GPIO2  ------------------- INT
--    GND  ------------------- A0/A1/A2

local init_result = mcp23017.init(1, 2)
if not init_result then
    log.error("mcp23017_demo", "MCP23017 初始化失败")
    return
end

log.info("mcp23017_demo", "MCP23017 初始化成功")


-- MCP23017 的 GPIO 输出测试
sys.taskInit(gpio_output_task_func)

-- MCP23017 的 GPIO 输入测试
sys.taskInit(gpio_input_task_func)

-- MCP23017 的 GPIO 中断测试
sys.taskInit(gpio_int_task_func)

-- MCP23017 的上拉电阻测试
sys.taskInit(gpio_pullup_task_func)