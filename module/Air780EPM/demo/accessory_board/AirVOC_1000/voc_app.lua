--[[
@module  voc_app
@summary voc_app应用功能模块 
@version 1.0
@date    2025.10.21
@author  沈园园
@usage
本文件为voc_app应用功能模块，核心业务逻辑为：
1、每隔1秒读取一次TVOC空气质量数据；

本文件没有对外接口，直接在main.lua中require "voc_app"就可以加载运行；
]]


--加载AirVOC_1000驱动文件
local air_voc = require "AirVOC_1000"


--如果使用的是Air780EPM核心板，则需要注释掉下面这行代码；
--如果使用的是Air780EPM开发板，则需要打开下面这行代码；
--这行代码的作用是：
--因为Air780EPM开发板上I2C内部没上拉,需要外部加上拉
--所以设置gpio2输出高电平,给camera_sda、camera_scl引脚提供上拉
gpio.setup(2, 1)


--每隔1秒读取一次TVOC数据
local function read_voc_task_func()
    --打开voc硬件
    air_voc.open(1)

    while true do
        --读取TVOC的ppb，ppm，quality_level值
        local ppb = air_voc.get_ppb()
        local ppm = air_voc.get_ppm()
        local level, description = air_voc.get_quality_level()
        
        --读取成功
        if ppb then
            log.info("空气质量", 
                string.format("TVOC: ppb %d, ppm %.3f, 等级 %d(%s)", 
                ppb, ppm, level, description))
        --读取失败
        else
            log.error("空气质量", "读取数据失败")
        end

        --等待1秒
        sys.wait(1000)
    end

    --关闭voc硬件
    air_voc.close()
end

--创建一个task，并且运行task的主函数read_voc_task_func
sys.taskInit(read_voc_task_func)

