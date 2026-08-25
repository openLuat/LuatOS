--[[
@module  mcp23s17_demo
@summary MCP23S17 GPIO 扩展应用功能模块
@version 1.0
@date    2026.08.24
@author  沈园园
@usage
本文件为 MCP23S17 SPI GPIO 扩展芯片的应用示例，硬件平台为 Air780EHV，核心业务逻辑为：
1、初始化 Air780EHV 和 MCP23S17 之间的 SPI 通信参数
2、MCP23S17 GPIO 输出测试、输入测试、GPIO 中断测试、上拉电阻测试

本文件没有对外接口，直接在 main.lua 中 require "mcp23s17_demo" 就可以加载运行；
]]

-- 加载 MCP23S17 扩展库
local mcp23s17 = require "exs_mcp23s17"

-- ==================== 演示硬件参数 ====================

-- SPI 总线 ID（Air780EHV 仅支持 1 路 SPI0，引脚为 PIN83/84/85/86）
local SPI_ID = 0
-- 片选引脚（Air780EHV 的 SPI0_CS 默认 GPIO8）
local CS_PIN = 8
-- 中断引脚（Air780EHV GPIO2，可选，不需要中断功能时传 nil）
local INT_PIN = 2
-- SPI 波特率（默认 1MHz，MCP23S17 最高支持 10MHz）
local BANDRATE = 1000000
-- 硬件地址 A2A1A0（默认 0，A0/A1/A2 引脚接地时用 0，范围 0~7）
local HW_ADDR = 0

-- ==================== 功能演示任务 ====================

-- MCP23S17 扩展 GPIO 输出测试
-- PA0 (0x00) 每隔一秒切换输出一次高低电平，可以通过示波器或者万用表测量 MCP23S17 上 PA0 引脚电平
local function gpio_output_task_func()
    mcp23s17.setup(0x00, 0)

    while true do
        mcp23s17.set(0x00, 0)
        sys.wait(1000)
        mcp23s17.set(0x00, 1)
        sys.wait(1000)
    end
end

-- MCP23S17 扩展 GPIO 输入测试
-- PA1 (0x01) 配置为输出模式，每隔一秒切换输出一次高低电平
-- PA2 (0x02) 配置为输入模式，每隔一秒调用 get 接口读取一次输入的电平
-- 将 PA1 和 PA2 两个引脚短接
local function gpio_input_task_func()
    mcp23s17.setup(0x01, 0)
    mcp23s17.setup(0x02)

    while true do
        mcp23s17.set(0x01, 0)
        sys.wait(1000)
        log.info("mcp23s17.get(0x02)", mcp23s17.get(0x02))
        mcp23s17.set(0x01, 1)
        sys.wait(1000)
        log.info("mcp23s17.get(0x02)", mcp23s17.get(0x02))
    end
end

-- PA3 引脚中断处理函数
-- id：0x03
-- level：触发中断后，某一时刻，扩展 GPIO 输入的电平状态，高电平为 1，低电平为 0
local function PA3_int_cbfunc(id, level)
    log.info("PA3_int_cbfunc", id, level)
end

-- PB3 引脚中断处理函数
-- id：0x13
-- level：触发中断后，某一时刻，扩展 GPIO 输入的电平状态，高电平为 1，低电平为 0
local function PB3_int_cbfunc(id, level)
    log.info("PB3_int_cbfunc", id, level)
end

-- MCP23S17 扩展 GPIO 中断测试
-- PA4 (0x04) 配置为输出模式，每隔一秒切换输出一次高低电平
-- PA3 (0x03) 配置为中断模式，并且配置中断处理函数 PA3_int_cbfunc
-- 将 PA4 和 PA3 两个引脚短接
-- PB4 (0x14) 配置为输出模式，每隔一秒切换输出一次高低电平
-- PB3 (0x13) 配置为中断模式，并且配置中断处理函数 PB3_int_cbfunc
-- 将 PB4 和 PB3 两个引脚短接
local function gpio_int_task_func()
    mcp23s17.setup(0x04, 0)
    mcp23s17.setup(0x03, PA3_int_cbfunc)

    mcp23s17.setup(0x14, 0)
    mcp23s17.setup(0x13, PB3_int_cbfunc)

    while true do
        mcp23s17.set(0x04, 0)
        mcp23s17.set(0x14, 0)
        sys.wait(1000)
        mcp23s17.set(0x04, 1)
        mcp23s17.set(0x14, 1)
        sys.wait(1000)
    end
end

-- MCP23S17 内部上拉电阻测试
-- PA5 (0x05) 配置为输入模式，启用内部上拉电阻
-- PB5 (0x15) 配置为输入模式，禁用内部上拉电阻
-- 对比两者的读取电平差异（引脚悬空时，启用上拉的 PA5 读为高电平 1，禁用上拉的 PB5 状态不定）
local function gpio_pullup_task_func()
    -- 配置 PA5 为输入模式，启用上拉
    mcp23s17.setup(0x05)
    mcp23s17.set_pullup(0x05, true)

    -- 配置 PB5 为输入模式，禁用上拉
    mcp23s17.setup(0x15)
    mcp23s17.set_pullup(0x15, false)

    log.info("mcp23s17", "上拉电阻测试已启动，PA5启用上拉，PB5禁用上拉")

    while true do
        log.info("mcp23s17", string.format("PA5(上拉):%d  PB5(无上拉):%d", mcp23s17.get(0x05), mcp23s17.get(0x15)))
        sys.wait(2000)
    end
end

-- ==================== 初始化并启动演示 ====================

-- 初始化 MCP23S17 扩展库
-- 参数说明：SPI0、CS=GPIO8、INT=GPIO2、1MHz、硬件地址 0
local init_result = mcp23s17.init(SPI_ID, CS_PIN, INT_PIN, BANDRATE, HW_ADDR)
if init_result then
    log.info("mcp23s17", "扩展库初始化成功")
    -- 启动演示任务
    sys.taskInit(gpio_output_task_func)
    sys.taskInit(gpio_input_task_func)
    sys.taskInit(gpio_int_task_func)
    sys.taskInit(gpio_pullup_task_func)
else
    log.error("mcp23s17", "扩展库初始化失败，请检查 SPI 接线与模块供电")
end
