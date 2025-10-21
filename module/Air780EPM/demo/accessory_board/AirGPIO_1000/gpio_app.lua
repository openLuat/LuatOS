--[[
@module  gpio_app
@summary gpio_app应用功能模块 
@version 1.0
@date    2025.10.21
@author  沈园园
@usage
本文件为gpio_app驱动配置文件，核心业务逻辑为：
1、初始化Air780EHV和AirGPIO_1000之间的通信参数
2、GPIO输出测试，输入测试，GPIO中断测试

本文件没有对外接口，直接在main.lua中require "gpio_app"就可以加载运行；
]]

--加载AirGPIO_1000驱动文件
local air_gpio = require "AirGPIO_1000"


--AirGPIO_1000扩展GPIO输出测试
--P00每隔一秒切换输出一次高低电平，可以通过示波器或者万用表测量AirGPIO_1000上P00引脚电平
local function gpio_output_task_func()
    air_gpio.setup(0x00, 0)

    while true do
        air_gpio.set(0x00, 0)
        sys.wait(1000)
        air_gpio.set(0x00, 1)
        sys.wait(1000)
    end
end


--AirGPIO_1000扩展GPIO输入测试
--P10配置为输出模式，每隔一秒切换输出一次高低电平
--P11配置为输入模式，每隔一秒调用get接口读取一次输入的电平
--将P10和P11两个引脚短接
local function gpio_input_task_func()
    air_gpio.setup(0x10, 0)
    air_gpio.setup(0x11)

    while true do
        air_gpio.set(0x10, 0)
        sys.wait(1000)
        log.info("air_gpio.get(0x11)", air_gpio.get(0x11))
        air_gpio.set(0x10, 1)
        sys.wait(1000)
        log.info("air_gpio.get(0x11)", air_gpio.get(0x11))
    end
end

--P04引脚中断处理函数
--id：0x04
--level：触发中断后，某一时刻，扩展GPIO输入的电平状态，高电平为1， 低电平为0
local function P04_int_cbfunc(id, level)
    log.info("P04_int_cbfunc", id, level)
end

--P14引脚中断处理函数
--id：0x14
--level：触发中断后，某一时刻，扩展GPIO输入的电平状态，高电平为1， 低电平为0
local function P14_int_cbfunc(id, level)
    log.info("P14_int_cbfunc", id, level)
end

--AirGPIO_1000扩展GPIO中断测试
--P03配置为输出模式，每隔一秒切换输出一次高低电平
--P04配置为中断模式，并且配置中断处理函数P04_int_cbfunc
--将P03和P04两个引脚短接
--P13配置为输出模式，每隔一秒切换输出一次高低电平
--P14配置为中断模式，并且配置中断处理函数P14_int_cbfunc
--将P13和P14两个引脚短接
local function gpio_int_task_func()
    air_gpio.setup(0x03, 0)
    air_gpio.setup(0x04, P04_int_cbfunc)

    air_gpio.setup(0x13, 0)
    air_gpio.setup(0x14, P14_int_cbfunc)

    while true do
        air_gpio.set(0x03, 0)
        air_gpio.set(0x13, 0)
        sys.wait(1000)
        air_gpio.set(0x03, 1)
        air_gpio.set(0x13, 1)
        sys.wait(1000)
    end
end


--初始化Air780EPM和AirGPIO_1000之间的通信参数
--使用Air780EPM的I2C0
--使用Air780EPM的GPIO2做为中断引脚
--Air780EPM核心板和AirGPIO_1000配件板的接线方式如下
--Air780EPM核心板             AirGPIO_1000配件板
--3V3-----------------3V3
--       GND-----------------GND
--     66/I2C1SDA-----------------SDA
--     67/I2C1SCL-----------------SCL
--  23/GPIO2-----------------INT

--电平设为3.3v
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)

air_gpio.init(1, 2)

--AirGPIO_1000的GPIO输出测试
sys.taskInit(gpio_output_task_func)

--AirGPIO_1000的GPIO输入测试
sys.taskInit(gpio_input_task_func)

--AirGPIO_1000的GPIO中断测试
sys.taskInit(gpio_int_task_func)

