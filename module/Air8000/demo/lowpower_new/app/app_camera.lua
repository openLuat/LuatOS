--[[
@module  take_photo
@summary 摄像头拍照控制模块
@version 1.0
@date    2026.02.25
@author  马梦阳
@usage
本模块负责摄像头拍照控制，核心业务逻辑为：
1、摄像头初始化：根据配置参数初始化gc032a摄像头硬件
2、拍照执行：接收拍照指令，执行拍照操作
3、数据返回：拍照成功后发布照片数据
4、资源管理：拍照完成后关闭摄像头释放资源

对外接口：
1、事件发布：
   - "CAPTURE_COMPLETE"：拍照完成时发布，携带照片数据
2、消息订阅：
   - "ONCE_CAPTURE"：等待拍照指令

使用说明：
1、摄像头配置：支持gc032a型号
2、工作模式：拍照模式（work_mode=0）
3、数据存储：使用ZBUFF格式存储照片数据
4、GPIO配置：支持摄像头使能、电源控制和补光灯控制
]]

require "gc032a"
-- 引入excamera扩展库模块
local excamera = require "excamera"

require "drv_normal"
require "drv_lowpower"

-- 获取当前使用的模组型号
local module = hmeta.model()

log.info("app_camera", "当前使用的模组是：", module)

--[[
拍照功能task
@function camera_take_photo_task
@local
@return nil
]]
local function camera_take_photo_task()
    -- 定义变量用于存储操作结果和数据
    local result, data, i2c_id, camera_pwr, camera_pwdn, camera_light

    -- 项目演示硬件环境为Air8000A整机开发板；
    -- Air8000A整机开发板摄像头部分使用的i2c_id为0，对应管脚编号为80和81；
    -- 同时摄像头使能管脚为GPIO147，摄像头pwdn开关脚为GPIO153，没有使用摄像头补光灯控制管脚；
    -- 如果客户使用的是Air8000A整机开发板，则不需要修改下方的参数；
    -- 如果客户使用的是其他开发板，需要参考模组硬件资料，根据硬件实际情况进行配置；
    i2c_id = 0         -- 定义I2C总线编号为0，根据实际情况修改
    camera_pwr = 147   -- 定义摄像头使能管脚GPIO号为147，根据实际情况修改
    camera_pwdn = 153  -- 定义摄像头pwdn开关脚GPIO号为153，根据实际情况修改
    camera_light = nil -- 定义摄像头补光灯控制管脚GPIO号为nil，根据实际情况修改

    -- 无限循环，持续等待拍照事件
    while true do
        --[[
        配置gc032a摄像头参数表
        @table spi_camera_param
        @field id string 摄像头型号，支持"gc032a"、"gc0310"、"bf30a2"
        @field i2c_id number I2C总线编号
        @field work_mode number 工作模式，0为拍照模式，1为扫描模式
        @field save_path string 拍照结果存储路径，"ZBUFF"表示由excamera库管理
        @field camera_pwr number 摄像头使能管脚GPIO号，无则填nil
        @field camera_pwdn number 摄像头pwdn开关脚GPIO号，无则填nil
        @field camera_light number 摄像头补光灯控制管脚GPIO号，无则填nil
        ]]
        local spi_camera_param = {
            id = "gc032a",              -- SPI摄像头型号
            i2c_id = i2c_id,            -- 模块上使用的I2C编号
            work_mode = 0,              -- 工作模式：0为拍照模式，1为扫描模式
            save_path = "ZBUFF",        -- 拍照结果存储路径
            camera_pwr = camera_pwr,    -- 摄像头使能管脚GPIO号
            camera_pwdn = camera_pwdn,  -- 摄像头pwdn开关脚GPIO号
            camera_light = camera_light -- 摄像头补光灯控制管脚GPIO号
        }

        -- 等待外部触发拍照事件(CAMERA_TAKE_PHOTO_REQ)
        sys.waitUntil("CAMERA_TAKE_PHOTO_REQ")

        -- 打印内存信息
        log.info("mem.lua", rtos.meminfo())
        log.info("mem.sys", rtos.meminfo("sys"))

        -- 在低功耗模式或者PSM+模式下，无法通过4G模组端控制WiFi芯片；
        -- 如果客户在配置摄像头部分相关管脚使用的是WiFi芯片端的GPIO，则需要退出低功耗模式或者PSM+模式，在常规模式下执行配置操作；
        -- 如果客户在配置摄像头部分相关管脚使用的全是4G芯片端的GPIO，则无需退出休眠模式，全程在对应休眠模式下执行即可；
        if camera_pwr > 100 or camera_pwdn > 100 or camera_light > 100 then
            -- 发布“DRV_SET_NORMAL”消息，通知drv_normal驱动模块配置为常规模式；
            sys.publish("DRV_SET_NORMAL")
            -- 等待2秒，等待4G芯片与WiFi芯片之间的通信恢复
            sys.wait(2000)
        end

        -- 项目演示硬件环境为Air8000A整机开发板；
        -- 在Air8000A整机开发板上，ES8311音频与摄像头部分使用的是同一个I2C通道；
        -- GPIO164为ES8311音频的LDO使能引脚，需要将GPIO164设置为输出高电平，否则I2C0的SDA和SCLK管脚电平只有2.8V左右，无法达到稳定的3.3V；
        -- 最终会造成I2C初始化不成功，摄像头拍照功能失败；
        -- 
        -- GPIO164为WiFi芯片的GPIO管脚，需要Air8000系列模组内部包含有WiFi芯片；
        -- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W内部包含有WiFi芯片；
        -- Air8000D/Air8000DB/Air8000T模组内部未包含WiFi芯片；
        -- 需要根据型号判断是否设置GPIO164为输出高电平；
        -- 
        -- 如果客户使用的是其他开发板，则不需要关注此处配置；
        if i2c_id == 0 and (module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or module == "Air8000AB" or module == "Air8000W") then
            gpio.setup(164, 1, gpio.PULLUP)
        end

        -- 初始化摄像头，传入配置参数
        result = excamera.open(spi_camera_param)
        -- 记录摄像头初始化状态
        log.info("camera_take_photo_task excamera.open", result)

        -- 判断摄像头初始化是否成功，不成功则直接关闭，成功则启动拍照
        if result then
            -- 执行拍照操作
            result, data = excamera.photo()
            log.info("camera_take_photo_task excamera.photo", result, type(data), data:used())
        end

        -- 发布拍照结果响应消息，携带操作结果和数据
        sys.publish("CAMERA_TAKE_PHOTO_RSP", result, data)

        -- 关闭摄像头，保留zbuff内存资源
        excamera.close(true)

        -- 在低功耗模式或者PSM+模式下，无法通过4G模组端控制WiFi芯片；
        -- 如果客户在配置摄像头部分相关管脚使用的是WiFi芯片端的GPIO，则需要退出低功耗模式或者PSM+模式，在常规模式下进行执行配置操作；
        -- 如果客户在配置摄像头部分相关管脚使用的全是4G芯片端的GPIO，则无需退出休眠模式，全程在对应休眠模式下执行即可；
        -- 前面如果切换到了常规模式，在执行完拍照操作后，需要重新切换回低功耗模式；
        if camera_pwr > 100 or camera_pwdn > 100 or camera_light > 100 then
            sys.publish("DRV_SET_LOWPOWER")
        end
    end
end

-- 创建拍照功能任务
sys.taskInit(camera_take_photo_task)
