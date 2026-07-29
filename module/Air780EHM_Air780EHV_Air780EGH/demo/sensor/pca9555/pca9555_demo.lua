--[[
@module  gpio_app
@summary PCA9555 GPIO 扩展应用功能模块
@version 1.0
@date    2026.07.28
@author  沈园园
@usage
本文件为 PCA9555 GPIO 扩展芯片的应用示例，硬件平台为 Air780EHV，核心业务逻辑为：
1、初始化 Air780EHV 和 PCA9555 之间的 I2C 通信参数
2、PCA9555 GPIO 输出测试、输入测试、GPIO 中断测试

本文件没有对外接口，直接在 main.lua 中 require "pca9555_demo" 就可以加载运行；
]]


-- 加载 PCA9555 扩展库
local pca9555 = require "exs_pca9555"


-- PCA9555 扩展 GPIO 输出测试
-- P0.0 每隔一秒切换输出一次高低电平，可以通过示波器或者万用表测量 PCA9555 上 P0.0 引脚电平
local function gpio_output_task_func()
    pca9555.setup(0x00, 0)

    while true do
        pca9555.set(0x00, 0)
        sys.wait(1000)
        pca9555.set(0x00, 1)
        sys.wait(1000)
    end
end


-- PCA9555 扩展 GPIO 输入测试
-- P1.0 配置为输出模式，每隔一秒切换输出一次高低电平
-- P1.1 配置为输入模式，每隔一秒调用 get 接口读取一次输入的电平
-- 将 P1.0 和 P1.1 两个引脚短接
local function gpio_input_task_func()
    pca9555.setup(0x10, 0)
    pca9555.setup(0x11)

    while true do
        pca9555.set(0x10, 0)
        sys.wait(1000)
        log.info("pca9555.get(0x11)", pca9555.get(0x11))
        pca9555.set(0x10, 1)
        sys.wait(1000)
        log.info("pca9555.get(0x11)", pca9555.get(0x11))
    end
end


-- P0.4 引脚中断处理函数
-- id：0x04
-- level：触发中断后，某一时刻，扩展 GPIO 输入的电平状态，高电平为 1，低电平为 0
local function P04_int_cbfunc(id, level)
    log.info("P04_int_cbfunc", id, level)
end

-- P1.4 引脚中断处理函数
-- id：0x14
-- level：触发中断后，某一时刻，扩展 GPIO 输入的电平状态，高电平为 1，低电平为 0
local function P14_int_cbfunc(id, level)
    log.info("P14_int_cbfunc", id, level)
end

-- PCA9555 扩展 GPIO 中断测试
-- P0.3 配置为输出模式，每隔一秒切换输出一次高低电平
-- P0.4 配置为中断模式，并且配置中断处理函数 P04_int_cbfunc
-- 将 P0.3 和 P0.4 两个引脚短接
-- P1.3 配置为输出模式，每隔一秒切换输出一次高低电平
-- P1.4 配置为中断模式，并且配置中断处理函数 P14_int_cbfunc
-- 将 P1.3 和 P1.4 两个引脚短接
local function gpio_int_task_func()
    pca9555.setup(0x03, 0)
    pca9555.setup(0x04, P04_int_cbfunc)

    pca9555.setup(0x13, 0)
    pca9555.setup(0x14, P14_int_cbfunc)

    while true do
        pca9555.set(0x03, 0)
        pca9555.set(0x13, 0)
        sys.wait(1000)
        pca9555.set(0x03, 1)
        pca9555.set(0x13, 1)
        sys.wait(1000)
    end
end


-- 初始化 Air780EHV 和 PCA9555 之间的通信参数
-- 使用 Air780EHV 的 I2C1
-- 使用 Air780EHV 的 GPIO2 做为中断引脚
-- Air780EHV 核心板和 PCA9555 模块的接线方式如下：
--
-- Air780EHV 核心板                PCA9555 模块
--      VBAT  -------------------- VDD
--       GND  -------------------- GND
--     66/I2C1SDA  ---------------- SDA
--     67/I2C1SCL  ---------------- SCL
--    23/GPIO2  ------------------- INT
--    GND  ------------------- A0/A1/A2

pca9555.init(1, 2)


-- PCA9555 的 GPIO 输出测试
sys.taskInit(gpio_output_task_func)

-- PCA9555 的 GPIO 输入测试
sys.taskInit(gpio_input_task_func)

-- PCA9555 的 GPIO 中断测试
sys.taskInit(gpio_int_task_func)