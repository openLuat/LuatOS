--[[
@module  scan_code
@summary AirCAMERA_1040 gc032a摄像头扫描二维码应用模块
@version 1.0
@date    2025.11.09
@author  陈取德
@usage
本demo主要使用AirCAMERA_1040 gc032a摄像头完成一次扫描二维码任务

PWRKEY按键：短按触发扫码

]] -- 
-- 摄像头扩展库模块
-- 功能：提供摄像头初始化、扫描和资源管理功能
-- 引入excamera扩展库模块
local excamera = require "excamera"
-- 硬件I2C/SPI配置，硬件版本由 main.lua 中的 _G.HARDWARE_ENV 全局变量统一控制
-- Air8201G: i2c_id=1 / Air8201H: i2c_id=0

-- I2C1总线上拉使能
gpio.setup(28, 1)
gpio.setup(24, 1)
gpio.setup(26, 1)

-------------------------------------
---PWRKEY按键：短按触发扫码---
-------------------------------------
gpio.debounce(gpio.PWR_KEY, 200)
gpio.setup(gpio.PWR_KEY, function()
    log.info("PWR_KEY", "已触发")
    sys.publish("SCAN_CODE")
end, gpio.PULLUP, gpio.FALLING)


-- 扫描功能函数
-- 作用：循环监听扫描事件，执行摄像头初始化、扫描和资源释放
local function scan_code_func()
    -- 定义变量用于存储操作结果和数据
    local result, data
    -- 无限循环，持续等待扫描事件
    while true do
        -- 配置gc032a摄像头参数表
        local spi_camera_param = {
            id = "gc032a", -- SPI摄像头仅支持"gc032a"、"gc0310"、"bf30a2"，请带引号填写
            i2c_id = (HARDWARE_ENV == "G") and 1 or 0, -- G: I2C1, H: I2C0
            work_mode = 1, -- 工作模式，0为拍照模式，1为扫描模式
            save_path = nil, -- 扫描结果为字符串返回，使用变量赋值既可
            camera_pwr = 22, -- 摄像头使能管脚，填写GPIO号即可，无则填nil
            camera_pwdn = 5, -- 摄像头pwdn开关脚，填写GPIO号即可，无则填nil
            camera_light = nil -- 摄像头补光灯控制管脚，填写GPIO号即可，无则填nil
        }
        -- 等待外部触发扫描事件(SCAN_CODE)
        sys.waitUntil("SCAN_CODE")

        -- 初始化摄像头，传入配置参数
        result = excamera.open(spi_camera_param)
        -- 记录摄像头初始化状态
        log.info("初始化状态", result)
        -- 判断摄像头初始化是否成功，不成功则直接关闭，成功则启动扫描
        if result then
            -- 执行扫描操作，5秒超时
            result, data = excamera.scan(5000)
            -- 扫描执行完成则上传，否则关闭摄像头
            if result then
                log.info("Scan result :", data )
            end
        end
        -- 关闭摄像头，释放资源
        excamera.close()

    end
end

-- 内存检查函数
-- 作用：定期监控系统内存使用情况
local function memory_check()
    -- 无限循环，定期检查内存
    while true do
        -- 等待3秒
        sys.wait(3000)
        -- 打印系统内存使用信息
        log.info("sys ram", rtos.meminfo("sys"))
        -- 打印Lua虚拟机内存使用信息
        log.info("lua ram", rtos.meminfo("lua"))
    end
end

-- 创建扫描功能任务
-- 作用：在单独的任务中运行扫描逻辑
sys.taskInit(scan_code_func)

-- 创建内存监控任务
-- 作用：在单独的任务中运行内存监控逻辑
sys.taskInit(memory_check)

