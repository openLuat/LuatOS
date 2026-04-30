--[[
@module http_upload_file
@summary TF卡大文件httpplus上传模块
@version 1.0.0
@date 2025.08.25
@author 王棚嶙
@usage
本文件演示通过httpplus库将TF卡中的大文件上传到HTTP服务器：
1. 网络就绪检测
2. TF卡文件系统挂载
3. 大文件上传功能
4. 上传结果记录
本文件没有对外接口，直接在main.lua中require "http_upload_file"即可
]]
-- 加载httpplus扩展库，不可省略
local httpplus = require "httpplus"

local exmux = require "exmux"
-- 硬件I2C/SPI配置，当您使用合宙开发板时，请根据具体的开发板版本选择对应的变量，
-- exmux库将会自动处理开发板上的I2C/SPI外设，确保总线通讯正常
-- 当您使用自己的制作的板子，请参考exmux库的文档，配置对应的变量：https://docs.openluat.com/osapi/ext/exmux/
-- local HARDWARE_ENV = "DEV_BOARD_8000_V2.0"
local HARDWARE_ENV = "DEV_BOARD_780_V1.2"
-- local HARDWARE_ENV = "DEV_BOARD_780_V1.3"

local function http_upload_task()
    -- 阶段1: 网络就绪检测
    while not socket.adapter(socket.dft()) do
        log.warn("HTTP上传", "等待网络连接", socket.dft())
        -- 待IP_READY消息，超时设为1秒
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息
    log.info("HTTP上传", "网络已就绪", socket.dft())
    -- 初始化外设分组开关状态
    exmux.setup(HARDWARE_ENV)
    -- 打开外设分组
    exmux.open("spi0")

    -- 在Air780EHM/EHV/EGH核心板上TF卡的的pin_cs为gpio8，spi_id为0.请根据实际硬件修改
    spi_id, pin_cs = 0, 8
    spi.setup(spi_id, nil, 0, 0, 8, 2000000)
    -- 初始化后拉高pin_cs,准备开始挂载TF卡
    gpio.setup(pin_cs, 1)
    

    -- 挂载文件系统
    local mount_ok = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)
    if not mount_ok then
        log.error("HTTP上传", "文件系统挂载失败")
        fatfs.unmount("/sd")
        spi.close(spi_id)
        return
    end

    -- 阶段3: 检查要上传的文件是否存在
    -- 替换为实际的文件路径
    local upload_file_path ="/sd/3_23MB.bin" 
    if not io.exists(upload_file_path) then
        log.error("HTTP上传", "要上传的文件不存在", upload_file_path)
        fatfs.unmount("/sd")
        spi.close(spi_id)
        return
    end

    -- 获取文件大小
    local file_size = io.fileSize(upload_file_path)
    log.info("HTTP上传", "准备上传文件", upload_file_path, "大小:", file_size, "字节")

    -- 阶段4: 执行文件上传
    log.info("HTTP上传", "开始上传任务")
    
    -- 使用httpplus库上传文件，参考httpplus_app_post_file的实现
    -- hhtplus.request接口支持单文件上传、多文件上传、单文本上传、多文本上传、单/多文本+单/多文件上传
    -- http://airtest.openluat.com:2900/uploadFileToStatic 仅支持单文件上传，并且上传的文件name必须使用"uploadFile"
    -- 所以此处仅演示了单文件上传功能，并且"uploadFile"不能改成其他名字，否则会出现上传失败的应答
    local code, response = httpplus.request({
        url = "http://airtest.openluat.com:2900/uploadFileToStatic",
        files = {
            -- 服务器要求文件名必须为"uploadFile"
            ["uploadFile"] = upload_file_path, 
        },
    })

    -- 阶段5: 记录上传结果
    log.info("HTTP上传", "上传完成", 
        code == 200 and "success" or "error", 
        code)
    
    if code == 200 then
        log.info("HTTP上传", "服务器响应头", json.encode(response.headers or {}))
        local body = response.body and response.body:query()
        log.info("HTTP上传", "服务器响应体长度", body and body:len() or 0)
        
        -- 可以进一步解析服务器响应
        if body then
            log.info("HTTP上传", "服务器响应内容", body:len() > 512 and "内容过长，不显示" or body)
        end
    else
        log.error("HTTP上传", "上传失败", code)
    end

    -- 阶段6: 资源清理
    fatfs.unmount("/sd")
    spi.close(spi_id)
    log.info("HTTP上传", "资源清理完成")
    -- 关闭外设分组
    exmux.close("spi0")
end

-- 创建上传任务
sys.taskInit(http_upload_task)