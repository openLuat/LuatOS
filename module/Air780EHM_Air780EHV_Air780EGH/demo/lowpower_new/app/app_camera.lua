--[[
@module  take_photo
@summary 摄像头拍照控制模块
@version 1.0
@date    2026.02.12
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


--[[
拍照功能task
@function camera_take_photo_task
@local
@return nil
]]
local function camera_take_photo_task()
    -- 定义变量用于存储操作结果和数据
    local result, data

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
            id = "gc032a",           -- SPI摄像头型号
            i2c_id = 1,              -- 模块上使用的I2C编号
            work_mode = 0,           -- 工作模式：0为拍照模式，1为扫描模式
            save_path = "ZBUFF",     -- 拍照结果存储路径
            camera_pwr = 2,          -- 摄像头使能管脚GPIO号
            camera_pwdn = 5,         -- 摄像头pwdn开关脚GPIO号
            camera_light = nil       -- 摄像头补光灯控制管脚GPIO号
        }

        -- 等待外部触发拍照事件(CAMERA_TAKE_PHOTO_REQ)
        sys.waitUntil("CAMERA_TAKE_PHOTO_REQ")

        -- 打印内存信息
        log.info("mem.lua", rtos.meminfo())
        log.info("mem.sys", rtos.meminfo("sys"))

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
    end
end

-- 创建拍照功能任务
sys.taskInit(camera_take_photo_task)