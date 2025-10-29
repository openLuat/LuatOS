--[[
@module  sht30_app
@summary sht30_app应用功能模块 
@version 1.0
@date    2025.10.22
@author  沈园园
@usage
本文件为sht30_app应用功能模块，核心业务逻辑为：
1、每隔1秒读取一次温湿度数据；

本文件没有对外接口，直接在main.lua中require "sht30_app"就可以加载运行；
]]


--加载AirSHT30_1000驱动文件
local air_sht30 = require "AirSHT30_1000"


--每隔1秒读取一次温湿度数据
local function read_sht30_task_func()
    
    --打开sht30硬件
    air_sht30.open(1)

    while true do
        --读取温湿度数据
        local temprature, humidity = air_sht30.read()

        --读取成功
        if temprature then
            -- 打印输出结果（保留2位小数）
            log.info("read_sht30_task_func", "temprature", string.format("%.2f ℃", temprature))
            log.info("read_sht30_task_func", "humidity", string.format("%.2f %%RH", humidity))
        --读取失败
        else
            log.error("read_sht30_task_func", "read error")
        end

        --等待1秒
        sys.wait(1000)
    end

    --关闭sht30硬件
    air_sht30.close()
end

--创建一个task，并且运行task的主函数read_sht30_task_func
sys.taskInit(read_sht30_task_func)

