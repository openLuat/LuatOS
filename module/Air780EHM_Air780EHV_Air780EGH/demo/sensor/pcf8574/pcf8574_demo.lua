--[[
@module  pcf8574_demo
@summary PCF8574 GPIO 扩展应用功能模块
@version 1.0
@date    2026.07.31
@author  沈园园
@usage
本文件为 PCF8574 GPIO 扩展芯片的应用示例，硬件平台为 Air780EHV，核心业务逻辑为：
1、初始化 Air780EHV 和 PCF8574 之间的 I2C 通信参数
2、PCF8574 GPIO 输出测试、输入测试、GPIO 中断测试、批量读写测试

本文件没有对外接口，直接在 main.lua 中 require "pcf8574_demo" 就可以加载运行；
]]


-- 加载 PCF8574 扩展库
local pcf8574 = require "exs_pcf8574"


-- PCF8574 扩展 GPIO 输出测试
-- P0 (0x00) 每隔一秒切换输出一次高低电平，可以通过示波器或者万用表测量 PCF8574 上 P0 引脚电平
local function gpio_output_task_func()
    pcf8574.setup(0x00, 0)

    while true do
        pcf8574.set(0x00, 0)
        sys.wait(1000)
        pcf8574.set(0x00, 1)
        sys.wait(1000)
    end
end


-- PCF8574 扩展 GPIO 输入测试
-- P1 (0x01) 配置为输出模式，每隔一秒切换输出一次高低电平
-- P2 (0x02) 配置为输入模式，每隔一秒调用 get 接口读取一次输入的电平
-- 将 P1 和 P2 两个引脚短接
local function gpio_input_task_func()
    pcf8574.setup(0x01, 0)
    pcf8574.setup(0x02)

    while true do
        pcf8574.set(0x01, 0)
        sys.wait(1000)
        log.info("pcf8574.get(0x02)", pcf8574.get(0x02))
        pcf8574.set(0x01, 1)
        sys.wait(1000)
        log.info("pcf8574.get(0x02)", pcf8574.get(0x02))
    end
end

-- P4 (0x04) 引脚中断处理函数
-- id：0x04
-- level：触发中断后，某一时刻，扩展 GPIO 输入的电平状态，高电平为 1，低电平为 0
local function P4_int_cbfunc(id, level)
    log.info("P4_int_cbfunc", id, level)
end

-- P6 (0x06) 引脚中断处理函数
-- id：0x06
-- level：触发中断后，某一时刻，扩展 GPIO 输入的电平状态，高电平为 1，低电平为 0
local function P6_int_cbfunc(id, level)
    log.info("P6_int_cbfunc", id, level)
end

-- P3 (0x03) 配置为输出模式，每隔一秒切换输出一次高低电平
-- P4 (0x04) 配置为中断模式，并且配置中断处理函数 P4_int_cbfunc
-- 将 P3 和 P4 两个引脚短接
-- P5 (0x05) 配置为输出模式，每隔一秒切换输出一次高低电平
-- P6 (0x06) 配置为中断模式，并且配置中断处理函数 P6_int_cbfunc
-- 将 P5 和 P6 两个引脚短接
local function gpio_int_task_func()
    pcf8574.setup(0x03, 0)
    pcf8574.setup(0x04, P4_int_cbfunc)
    
    pcf8574.setup(0x05, 0)
    pcf8574.setup(0x06, P6_int_cbfunc)

    while true do
        pcf8574.set(0x03, 0)
        pcf8574.set(0x05, 0)
        sys.wait(1000)
        
        pcf8574.set(0x03, 1)
        pcf8574.set(0x05, 1)        
        sys.wait(1000)
    end
end


-- PCF8574 批量读写测试
-- 演示 read_all() 和 write_all() 接口的使用
local function gpio_batch_task_func()
    log.info("pcf8574_demo", "批量读写测试已启动")

    while true do
        -- 写入：P0~P3 输出低，P4~P7 输出高
        pcf8574.write_all(0xF0)
        sys.wait(500)

        -- 读取所有引脚状态
        local data = pcf8574.read_all()
        if data ~= false then
            log.info("pcf8574.read_all", string.format("0x%02X", data))
        end

        -- 写入：P0~P7 全部输出低
        pcf8574.write_all(0x00)
        sys.wait(500)

        -- 读取所有引脚状态
        data = pcf8574.read_all()
        if data ~= false then
            log.info("pcf8574.read_all", string.format("0x%02X", data))
        end

        -- 写入：P0~P7 全部输出高
        pcf8574.write_all(0xFF)
        sys.wait(500)

        -- 读取所有引脚状态
        data = pcf8574.read_all()
        if data ~= false then
            log.info("pcf8574.read_all", string.format("0x%02X", data))
        end

        sys.wait(1000)
    end
end


-- 初始化 Air780EHV 和 PCF8574 之间的通信参数
-- 使用 Air780EHV 的 I2C1
-- 使用 Air780EHV 的 GPIO2 做为中断引脚
-- Air780EHV 核心板和 PCF8574 模块的接线方式如下：
--
-- Air780EHV 核心板                PCF8574 模块
--      VBAT  -------------------- VDD
--       GND  -------------------- GND
--     66/I2C1SDA  ---------------- SDA
--     67/I2C1SCL  ---------------- SCL
--    23/GPIO2  ------------------- INT
--    GND  ------------------- A0/A1/A2

local init_result = pcf8574.init(1, 2)
if not init_result then
    log.error("pcf8574_demo", "PCF8574 初始化失败")
    return
end

log.info("pcf8574_demo", "PCF8574 初始化成功")


-- PCF8574 的 GPIO 输出测试
--sys.taskInit(gpio_output_task_func)

-- PCF8574 的 GPIO 输入测试
--sys.taskInit(gpio_input_task_func)

-- PCF8574 的 GPIO 中断测试
--sys.taskInit(gpio_int_task_func)

-- PCF8574 的批量读写测试
sys.taskInit(gpio_batch_task_func)