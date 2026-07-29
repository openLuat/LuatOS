--[[
@module  take_photo_http_post
@summary AirCAMERA_1050 gc0310摄像头拍照上传应用模块
@version 1.0
@date    2025.11.09
@author  陈取德
@usage
本demo主要使用AirCAMERA_1050 gc0310摄像头完成一次拍照上传任务

PWRKEY按键：短按触发拍照

]] -- 摄像头拍照模块
-- 功能：提供摄像头初始化、拍照和资源管理功能
-- 引入excamera扩展库模块
local excamera = require "excamera"
-- 引入httpplus扩展库模块
local httpplus = require "httpplus"
-- 硬件I2C/SPI配置，硬件版本由 main.lua 中的 _G.HARDWARE_ENV 全局变量统一控制
-- Air8201G: i2c_id=1 / Air8201H: i2c_id=0

-- I2C1总线上拉使能
gpio.setup(28, 1)
gpio.setup(24, 1)
gpio.setup(26, 1)

-------------------------------------
---PWRKEY按键：短按触发拍照---
-------------------------------------
gpio.debounce(gpio.PWR_KEY, 200)
gpio.setup(gpio.PWR_KEY, function()
    log.info("PWR_KEY", "已触发")
    sys.publish("ONCE_CAPTURE")
end, gpio.PULLUP, gpio.FALLING)


-- 定义照片保存方式，有三种类型：
-- 1、ZBUFF保存，输入"ZBUFF"即可，excamera库会自动处理ZBUFF
-- 2、保存到内存文件系统中，路径名需指向/ram/文件夹
-- 3、保存到内置FLASH文件系统中
-- 选择其中一个即可，注释另两个路径变量
local save_method = "ZBUFF"
-- local save_method = "/ram/test.jpg"
-- local save_method = "/test.jpg"

-- 拍照功能函数
-- 作用：循环监听拍照事件，执行摄像头初始化、拍照和资源释放
local function capture_func()
    -- 定义变量用于存储操作结果和数据
    local result, data
    -- 无限循环，持续等待拍照事件
    while true do
        -- 配置gc0310摄像头参数表
        local spi_camera_param = {
            id = "gc0310", -- SPI摄像头仅支持"gc032a"、"gc0310"、"bf30a2"，请带引号填写
            i2c_id = (HARDWARE_ENV == "G") and 1 or 0, -- G: I2C1, H: I2C0
            work_mode = 0, -- 工作模式，0为拍照模式，1为扫描模式
            save_path = save_method, -- 拍照结果存储路径，可用"ZBUFF"交由excamera库内部管理
            camera_pwr = 22, -- 摄像头使能管脚，填写GPIO号即可，无则填nil
            camera_pwdn = 5, -- 摄像头pwdn开关脚，填写GPIO号即可，无则填nil
            camera_light = nil -- 摄像头补光灯控制管脚，填写GPIO号即可，无则填nil
        }
        -- 等待外部触发拍照事件(ONCE_CAPTURE)
        sys.waitUntil("ONCE_CAPTURE")

        -- 初始化摄像头，传入配置参数
        result = excamera.open(spi_camera_param)
        -- 记录摄像头初始化状态
        log.info("初始化状态", result)
        -- 判断摄像头初始化是否成功，不成功则直接关闭，成功则启动拍照
        if result then
            -- 执行拍照操作
            result, data = excamera.photo()
            -- 拍照执行完成则上传，否则关闭摄像头
            if result then
                -- 通过网卡状态判断WIFI是否连接成功，WIFI连接成功后再运行照片上传任务。
                while not socket.adapter(socket.dft()) do
                    -- 在此处阻塞等待WIFI连接成功的消息"IP_READY"，避免联网过快，丢失了"IP_READY"信息而导致一直被卡住。
                    -- 或者等待30秒超时退出阻塞等待状态
                    log.warn("tcp_client_main_task_func", "wait IP_READY")
                    sys.waitUntil("IP_READY", 30000)
                end
                if type(data) == "userdata" then
                    data = data:query()
                else
                    data = io.readFile(data)
                end
                -- 通过网卡(本demo使用的是socket.LWIP_STA网卡)将拍摄到的照片数据result上传到服务器air32.cn
                -- 如果上传成功，电脑上浏览器打开https://www.air32.cn/upload/jpg/，打开对应的测试日期目录，点击具体的测试时间照片，可以查看摄像头拍照上传的照片
                -- 执行httpplus.request后，等待服务器的http应答，此处会阻塞当前task，等待整个过程成功结束或者出现错误异常结束
                -- code表示结果，number类型，详细说明参考API手册，一般来说：
                --             200表示成功
                --             小于0的值表示出错，例如-8表示超时错误
                --             其余结果值参考API手册
                -- 因为Air32.com平台已经不开放使用了，所以该DEMO仅作上传照片至服务器的演示作用，使用时请将上传URL修改为您自己的服务器地址
                -- 或者通过excloud扩展库上传到合宙IOT平台uploadtest.luatos.com，详见：photo_to_aircloud.lua  
                local code = httpplus.request({
                    url = "http://upload.air32.cn/api/upload/jpg",
                    method = "POST",
                    body = data
                })
                -- 打印http传输状态
                log.info("http_upload_photo_task_func", "httpplus.request", code)
            end
        end
        -- 判断是否ZBUFF存储方式，如果是文件系统保存则删除本地文件
        if save_method ~= "ZBUFF" then
            os.remove(spi_camera_param.save_path)
        end
        -- 关闭摄像头，释放资源
        -- 使用ZBUFF存储方式时，close传入true后，excamera内部创建的ZBUFF会缩减至0字节，放出内存但是不释放ZBUFF，便于下次拍照时调用；
        -- 重复申请和释放ZBUFF会导致垃圾内存堆积，影响系统内存；
        excamera.close(true)

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

-- 创建拍照功能任务
-- 作用：在单独的任务中运行拍照逻辑
sys.taskInit(capture_func)

-- 创建内存监控任务
-- 作用：在单独的任务中运行内存监控逻辑
sys.taskInit(memory_check)
