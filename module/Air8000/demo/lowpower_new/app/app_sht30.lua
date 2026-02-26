--[[
@module  sht30_app
@summary sht30_app应用功能模块
@version 1.0
@date    2026.02.09
@author  马梦阳
@usage
本文件为sht30_app应用功能模块，核心业务逻辑为：
1、每隔1秒读取一次温湿度数据；

本文件没有对外接口，直接在main.lua中require "sht30_app"就可以加载运行；
]]


-- 加载AirSHT30_1000驱动文件
local air_sht30 = require "AirSHT30_1000"


-- 读取sht30温湿度数据任务
local function read_sht30_task()
    --打开sht30硬件
    air_sht30.open(1)
    --读取温湿度数据
    local temprature, humidity = air_sht30.read()

    --读取结果
    if temprature then
        -- 打印输出结果（保留2位小数）
        log.info("read_sht30_req", "temprature", string.format("%.2f ℃", temprature))
        log.info("read_sht30_req", "humidity", string.format("%.2f %%RH", humidity))        
    else
        log.error("read_sht30_task_func", "read error")
    end

    --关闭sht30硬件
    air_sht30.close()

    -- 发布读取结果
    sys.publish("READ_SHT30_RSP", temprature~=nil, temprature, humidity)
end

-- 读取sht30数据请求消息处理函数
local function read_sht30_req()
    sys.taskInit(read_sht30_task)
end

-- 订阅读取sht30数据请求消息
sys.subscribe("READ_SHT30_REQ", read_sht30_req)
